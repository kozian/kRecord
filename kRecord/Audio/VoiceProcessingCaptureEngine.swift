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
    private var engine: AVAudioEngine?
    private var configurationObserver: NSObjectProtocol?
    private var microphonePath: VoiceMicrophonePath?
    private var forwardTask: Task<Void, Never>?
    private let eventHub = CaptureEventHub()

    init() {}

    nonisolated func events() -> AsyncStream<CaptureEvent> {
        eventHub.makeStream()
    }

    func start(_ configuration: CaptureConfiguration) async throws(CaptureError) -> CaptureStreams {
        precondition(engine == nil, "capture already running")
        guard !configuration.sources.isEmpty else { throw .noSources }

        // Without the microphone there is nothing to cancel: plain system capture.
        guard configuration.sources.contains(.microphone) else {
            return try await startSystemOnly(configuration)
        }

        // Voice processing reconfigures the output device when it starts. Starting it before the
        // system capture keeps that reconfiguration from disturbing the running aggregate.
        let captureSystem = configuration.sources.contains(.system)
        let rate = OutputFormat.sampleRate
        let ring = RingBuffer(channels: CaptureStreams.microphoneChannels,
                              capacityFrames: Int(rate * AggregateCaptureEngine.ringSeconds))
        let path = VoiceMicrophonePath(ring: ring, alignsToSystem: captureSystem, sampleRate: rate)
        try startMicrophone(configuration: configuration, path: path)
        microphonePath = path

        guard captureSystem else {
            return CaptureStreams(sampleRate: rate, microphone: ring, system: nil, levels: path.levels)
        }
        do throws(CaptureError) {
            let systemEvents = systemEngine.events()
            let system = try await systemEngine.start(CaptureConfiguration(inputDeviceUID: nil, sources: .system))
            guard system.sampleRate == rate, let timeline = await systemEngine.systemTimeline() else {
                throw .sampleRateMismatch
            }
            forwardTask = Task { [eventHub] in
                for await event in systemEvents { eventHub.yield(event) }
            }
            path.attach(timeline: timeline, levels: system.levels)
            return CaptureStreams(sampleRate: rate, microphone: ring, system: system.system, levels: system.levels)
        } catch {
            await stop()
            throw error
        }
    }

    func stop() async {
        if let configurationObserver { NotificationCenter.default.removeObserver(configurationObserver) }
        configurationObserver = nil
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
        microphonePath = nil
        await stopSystem()
        eventHub.finish()
    }

    // MARK: - Private

    private func startSystemOnly(_ configuration: CaptureConfiguration) async throws(CaptureError) -> CaptureStreams {
        let systemEvents = systemEngine.events()
        let streams = try await systemEngine.start(configuration)
        forwardTask = Task { [eventHub] in
            for await event in systemEvents { eventHub.yield(event) }
        }
        return streams
    }

    private func stopSystem() async {
        await systemEngine.stop()
        forwardTask?.cancel()
        forwardTask = nil
    }

    private func startMicrophone(configuration: CaptureConfiguration, path: VoiceMicrophonePath) throws(CaptureError) {
        let engine = AVAudioEngine()
        let input = engine.inputNode
        if let device = AggregateCaptureEngine.resolveInputDevice(selectedUID: configuration.inputDeviceUID),
           device != CoreAudioHAL.defaultInputDevice() {
            // Best effort: on failure the engine keeps using the default input (fallback rule).
            try? input.auAudioUnit.setDeviceID(device)
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
        // A device change stops the engine; restart it. The timeline alignment fills the gap.
        configurationObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
        ) { [weak engine] _ in
            try? engine?.start()
        }
        self.engine = engine
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

    /// Starts placing microphone audio on the system timeline; earlier buffers are dropped.
    func attach(timeline: TimelineAnchor, levels: LevelSnapshot) {
        shared.withLock { $0 = (timeline, levels) }
    }

    /// Voice processing may run at another rate than the system track; convert if so.
    func prepare(inputFormat: AVAudioFormat) {
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
