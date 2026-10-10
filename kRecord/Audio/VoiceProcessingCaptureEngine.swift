@preconcurrency import AVFoundation
import CoreAudio
import Foundation
import Synchronization

/// Capture with echo cancellation (design D6): the microphone goes through `AVAudioEngine` with
/// macOS voice processing, system audio through a tap-only aggregate (`AggregateCaptureEngine`
/// with `.system`). Microphone buffers are placed on the system audio timeline by host time,
/// which absorbs the voice-processing latency, clock drift, and gaps.
actor VoiceProcessingCaptureEngine: CaptureEngine {
    private let systemEngine = AggregateCaptureEngine()
    private var configuration: CaptureConfiguration?
    private var microphone: Microphone?
    private var microphonePath: VoiceMicrophonePath?
    private var systemRunning = false
    private var monitor: DeviceMonitor?
    /// The device the last microphone rebuild aimed for; a failed device is retried when this changes.
    private var wantedInput: AudioObjectID?
    private var forwardTask: Task<Void, Never>?
    private var supervisionTask: Task<Void, Never>?
    /// Device changes are handled only once `start` finished; one check runs right after it.
    private var running = false
    /// System audio normally arrives every few milliseconds; this long without it is a stall.
    private static let stallTimeout: Duration = .milliseconds(500)
    /// System timeline progress seen by the supervision task.
    private var lastSystemFrames = -1
    private var systemStalledSince: ContinuousClock.Instant?
    private let eventHub = CaptureEventHub()

    /// The running voice-processing engine and the input device it records.
    private struct Microphone {
        let engine: AVAudioEngine
        let device: AudioObjectID?
        let observer: NSObjectProtocol
    }

    init() {}

    nonisolated func events() -> AsyncStream<CaptureEvent> {
        eventHub.makeStream()
    }

    func start(_ configuration: CaptureConfiguration) async throws(CaptureError) -> CaptureStreams {
        precondition(self.configuration == nil, "capture already running")
        guard !configuration.sources.isEmpty else { throw .noSources }

        // Without the microphone there is nothing to cancel: plain system capture.
        guard configuration.sources.contains(.microphone) else {
            let streams = try await startSystem(configuration)
            self.configuration = configuration
            return streams
        }

        // Voice processing reconfigures the output device when it starts. Starting it before the
        // system capture keeps that reconfiguration from disturbing the running aggregate.
        let captureSystem = configuration.sources.contains(.system)
        let rate = AACEncoding.sampleRate
        let ring = RingBuffer(channels: CaptureStreams.microphoneChannels,
                              capacityFrames: Int(rate * AggregateCaptureEngine.ringSeconds))
        let path = VoiceMicrophonePath(ring: ring, alignsToSystem: captureSystem, sampleRate: rate)
        let wanted = AggregateCaptureEngine.resolveInputDevice(selectedUID: configuration.inputDeviceUID)
        microphone = try startMicrophone(wanted: wanted, path: path)
        wantedInput = wanted
        microphonePath = path
        self.configuration = configuration

        if captureSystem {
            do throws(CaptureError) {
                let system = try await startSystem(CaptureConfiguration(inputDeviceUID: nil, sources: .system))
                guard system.sampleRate == rate, let timeline = await systemEngine.systemTimeline() else {
                    throw .sampleRateMismatch
                }
                path.attach(timeline: timeline, levels: system.levels)
                startMonitor()
                supervisionTask = Task { [weak self] in
                    while !Task.isCancelled {
                        try? await Task.sleep(for: .milliseconds(250))
                        await self?.supervise()
                    }
                }
                finishStart()
                return CaptureStreams(sampleRate: rate, microphone: ring, system: system.system, levels: system.levels)
            } catch {
                await stop()
                throw error
            }
        }
        startMonitor()
        finishStart()
        return CaptureStreams(sampleRate: rate, microphone: ring, system: nil, levels: path.levels)
    }

    func stop() async {
        monitor?.stop()
        monitor = nil
        running = false
        supervisionTask?.cancel()
        supervisionTask = nil
        stopMicrophone()
        if systemRunning {
            await systemEngine.stop()
            systemRunning = false
        }
        // Separate files end together: the microphone gets silence up to the system track's length.
        microphonePath?.padToTimeline()
        microphonePath = nil
        configuration = nil
        forwardTask?.cancel()
        forwardTask = nil
        eventHub.finish()
    }

    // MARK: - Device changes (fix-device-switching design D1–D4)

    private func startMonitor() {
        let monitor = DeviceMonitor { [weak self] in
            Task { await self?.handleDeviceChange() }
        }
        monitor.start()
        monitor.watchInput(microphone?.device)
        self.monitor = monitor
    }

    /// Rebuilds the microphone when the wanted device changed, the current one died, or the
    /// voice-processing engine stopped. Runs without suspending, so changes are handled one at a time.
    private func handleDeviceChange() {
        guard running, let configuration, let path = microphonePath else { return }
        let wanted = AggregateCaptureEngine.resolveInputDevice(selectedUID: configuration.inputDeviceUID)
        let deviceLost = microphone?.device.map { !CoreAudioHAL.isAlive($0) } ?? false
        let engineStopped = microphone.map { !$0.engine.isRunning } ?? false
        guard wanted != wantedInput || deviceLost || engineStopped else { return }
        // Voice processing stops its engine on configuration changes it causes itself, e.g. right
        // after starting on a device that is not the default input; restarting it is enough then.
        if wanted == wantedInput, !deviceLost, let microphone, (try? microphone.engine.start()) != nil {
            return
        }

        let previousDevice = microphone?.device
        stopMicrophone()
        wantedInput = wanted
        do throws(CaptureError) {
            microphone = try startMicrophone(wanted: wanted, path: path)
        } catch {
            // No microphone left: system audio continues, the microphone track is padded with
            // silence, and the next device change tries again (D4). Microphone-only capture fails.
            microphone = nil
            if !configuration.sources.contains(.system) {
                eventHub.yield(.failed(error))
                return
            }
        }
        monitor?.watchInput(microphone?.device)
        if let device = microphone?.device, device != previousDevice {
            eventHub.yield(.inputDeviceChanged(name: CoreAudioHAL.name(of: device) ?? ""))
        }
        // The system aggregate keeps running: a voice-processing restart under it costs about
        // 0.1 s of system audio, a rebuild of the aggregate about 0.9 s (design D3). If it stalls,
        // `supervise` rebuilds it.
    }

    private func finishStart() {
        running = true
        // A change during start was ignored; catch up on it.
        handleDeviceChange()
    }

    /// Every 250 ms while system audio is captured. Without a microphone, pads the microphone track
    /// with silence: the mixed writer advances both tracks together, so the system ring must not
    /// wait for it (D4). Rebuilds the system aggregate when its timeline stopped advancing for
    /// `stallTimeout` (D3): seen when the last microphone disappeared under voice processing.
    private func supervise() async {
        guard running, let path = microphonePath else { return }
        // Safe without a lock: with `microphone` nil no voice-processing tap writes to the path,
        // and `handleDeviceChange` sets it without suspending.
        if microphone == nil { path.padToTimeline() }

        let frames = path.systemFrameCount ?? 0
        let now = ContinuousClock.now
        guard frames == lastSystemFrames else {
            lastSystemFrames = frames
            systemStalledSince = nil
            return
        }
        guard let since = systemStalledSince else {
            systemStalledSince = now
            return
        }
        guard now - since >= Self.stallTimeout else { return }
        systemStalledSince = now
        do throws(CaptureError) {
            try await systemEngine.rebuildDevice()
        } catch {
            eventHub.yield(.failed(error))
        }
    }

    // MARK: - Private

    private func startSystem(_ configuration: CaptureConfiguration) async throws(CaptureError) -> CaptureStreams {
        let systemEvents = systemEngine.events()
        let streams = try await systemEngine.start(configuration)
        systemRunning = true
        forwardTask = Task { [eventHub] in
            for await event in systemEvents { eventHub.yield(event) }
        }
        return streams
    }

    private func stopMicrophone() {
        guard let microphone else { return }
        NotificationCenter.default.removeObserver(microphone.observer)
        microphone.engine.inputNode.removeTap(onBus: 0)
        microphone.engine.stop()
        self.microphone = nil
    }

    /// Starts voice processing on `wanted`, falling back to the default input (audio-capture spec).
    private func startMicrophone(wanted: AudioObjectID?, path: VoiceMicrophonePath) throws(CaptureError) -> Microphone {
        var candidates: [AudioObjectID?] = [wanted]
        if let fallback = CoreAudioHAL.defaultInputDevice(), fallback != wanted { candidates.append(fallback) }
        var lastError = CaptureError.noInputDevice
        for candidate in candidates {
            guard let candidate else { continue }
            do throws(CaptureError) {
                return try startMicrophone(device: candidate, path: path)
            } catch {
                lastError = error
            }
        }
        throw lastError
    }

    /// A fresh voice-processing engine on `device` (D2): a running one keeps its device binding.
    private func startMicrophone(device: AudioObjectID, path: VoiceMicrophonePath) throws(CaptureError) -> Microphone {
        let engine = AVAudioEngine()
        let input = engine.inputNode
        if device != CoreAudioHAL.defaultInputDevice() {
            do {
                try input.auAudioUnit.setDeviceID(device)
            } catch {
                throw .coreAudio(operation: "setDeviceID", status: OSStatus((error as NSError).code))
            }
        }
        do {
            try input.setVoiceProcessingEnabled(true)
        } catch {
            throw .coreAudio(operation: "setVoiceProcessingEnabled", status: OSStatus((error as NSError).code))
        }
        // Keep other audio (the meeting) as loud as voice processing allows (spike: ~7.6 dB remain).
        input.voiceProcessingOtherAudioDuckingConfiguration =
            AVAudioVoiceProcessingOtherAudioDuckingConfiguration(enableAdvancedDucking: false, duckingLevel: .min)

        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { throw .unsupportedFormat }
        path.prepare(inputFormat: format)

        input.installTap(onBus: 0, bufferSize: 1_024, format: format) { buffer, time in
            path.append(buffer, time: time)
        }
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            throw .coreAudio(operation: "voice processing engine start", status: OSStatus((error as NSError).code))
        }
        // A configuration change stops the engine; the rebuild decides what to start instead (D1).
        let observer = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: nil
        ) { [weak self] _ in
            Task { await self?.handleDeviceChange() }
        }
        return Microphone(engine: engine, device: device, observer: observer)
    }
}

/// Moves voice-processed microphone buffers into the microphone ring, aligned to system audio.
/// Called on the engine's tap thread (not real-time); only that thread uses the mutable state.
final class VoiceMicrophonePath: @unchecked Sendable {
    private let ring: RingBuffer
    private let alignsToSystem: Bool
    private let sampleRate: Double
    /// Set once system capture runs; read on the tap thread.
    private let shared = Mutex<(timeline: TimelineAnchor?, levels: LevelSnapshot)>((nil, LevelSnapshot()))
    private var converter: AVAudioConverter?
    private var converted: AVAudioPCMBuffer?
    private var framesWritten = 0
    private let silence = [Float](repeating: 0, count: 4_800)

    /// Delay voice processing adds between capture and the host time stamped on its buffers.
    /// The API reports about 1.5 ms (`presentationLatency`), but clicks played through the speakers
    /// arrive 38.7 ms later than with direct capture; this measured value is subtracted so both
    /// capture paths produce the same alignment (design D6).
    static let processingLatency: Double = 0.0387
    private static let latencyTicks = UInt64(processingLatency * MicAlignment.hostTicksPerSecond)

    init(ring: RingBuffer, alignsToSystem: Bool, sampleRate: Double) {
        self.ring = ring
        self.alignsToSystem = alignsToSystem
        self.sampleRate = sampleRate
    }

    var levels: LevelSnapshot { shared.withLock { $0.levels } }

    /// System frames recorded so far, once system capture runs.
    var systemFrameCount: Int? { shared.withLock { $0.timeline?.frameCount } }

    /// Starts placing microphone audio on the system timeline; earlier buffers are dropped.
    func attach(timeline: TimelineAnchor, levels: LevelSnapshot) {
        shared.withLock { $0 = (timeline, levels) }
    }

    /// Sample rate the converter takes, or `nil` when the input already runs at the recording rate.
    var convertsFrom: Double? { converter?.inputFormat.sampleRate }

    /// Voice processing may run at another rate than the system track; convert if so. Called for
    /// every new voice-processing engine, while no tap delivers buffers.
    func prepare(inputFormat: AVAudioFormat) {
        converter = nil
        converted = nil
        guard inputFormat.sampleRate != sampleRate,
              let target = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate,
                                         channels: 1, interleaved: false) else { return }
        // Voice processing reports several identical channels; channel 0 is the processed voice.
        let mono = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: inputFormat.sampleRate,
                                 channels: 1, interleaved: false)
        converter = mono.flatMap { AVAudioConverter(from: $0, to: target) }
    }

    func append(_ buffer: AVAudioPCMBuffer, time: AVAudioTime) {
        guard let channel = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return }
        var samples = UnsafePointer(channel)
        var frames = Int(buffer.frameLength)
        if let converter, let output = convert(buffer, with: converter) {
            samples = UnsafePointer(output.floatChannelData![0])
            frames = Int(output.frameLength)
        }

        let (timeline, levels) = shared.withLock { $0 }
        if alignsToSystem {
            guard let timeline, time.isHostTimeValid, let anchor = timeline.latest() else { return }
            let captureHostTime = time.hostTime > Self.latencyTicks ? time.hostTime - Self.latencyTicks : 0
            switch MicAlignment.action(bufferHostTime: captureHostTime, frames: frames, micFramesWritten: framesWritten,
                                       anchor: anchor, sampleRate: sampleRate,
                                       hostTicksPerSecond: MicAlignment.hostTicksPerSecond) {
            case .drop:
                return
            case let .write(silence: padding, dropLeading: leading):
                writeSilence(padding)
                samples += leading
                frames -= leading
            }
        }
        ring.write(samples, frameCount: frames, sourceChannels: 1)
        framesWritten += frames
        levels.publish(AudioLevel.measure(samples, frameCount: frames), for: .microphone)
    }

    /// Writes silence up to the system timeline's frame count, so the microphone track is as long
    /// as the system track. Call after the tap and the system capture stopped.
    func padToTimeline() {
        guard alignsToSystem, let timeline = shared.withLock({ $0.timeline }) else { return }
        writeSilence(max(0, timeline.frameCount - framesWritten))
    }

    private func writeSilence(_ frames: Int) {
        var remaining = frames
        while remaining > 0 {
            let chunk = min(remaining, silence.count)
            ring.write(silence, frameCount: chunk, sourceChannels: 1)
            framesWritten += chunk
            remaining -= chunk
        }
    }

    private func convert(_ buffer: AVAudioPCMBuffer, with converter: AVAudioConverter) -> AVAudioPCMBuffer? {
        guard let mono = AVAudioPCMBuffer(pcmFormat: converter.inputFormat, frameCapacity: buffer.frameLength) else {
            return nil
        }
        mono.floatChannelData![0].update(from: buffer.floatChannelData![0], count: Int(buffer.frameLength))
        mono.frameLength = buffer.frameLength
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * sampleRate / buffer.format.sampleRate) + 32
        if converted == nil || converted!.frameCapacity < capacity {
            converted = AVAudioPCMBuffer(pcmFormat: converter.outputFormat, frameCapacity: capacity)
        }
        guard let output = converted else { return nil }
        var supplied = false
        var error: NSError?
        converter.convert(to: output, error: &error) { _, status in
            if supplied {
                status.pointee = .noDataNow
                return nil
            }
            supplied = true
            status.pointee = .haveData
            return mono
        }
        return error == nil ? output : nil
    }
}
