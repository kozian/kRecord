@preconcurrency import AVFoundation
import CoreAudio
import Foundation
import Synchronization

/// Captures the microphone and all system audio through one private aggregate device (design D2):
/// the input device is the clock, a global stereo process tap is drift-compensated against it, and
/// one IOProc receives both on a shared sample clock.
actor AggregateCaptureEngine: CaptureEngine {
    static let ringSeconds = 10.0

    /// One capture from `start` to `stop`. Survives aggregate rebuilds (design D3).
    private struct Capture {
        let configuration: CaptureConfiguration
        let sampleRate: Double
        let tap: ProcessTap?
        let microphone: RingBuffer?
        let system: RingBuffer?
        let levels: LevelSnapshot
        let timeline: TimelineAnchor
    }

    /// The current aggregate device; replaced when the input device changes.
    private struct Device {
        let aggregate: AudioObjectID
        let ioProc: AudioDeviceIOProcID
        let clock: AudioObjectID
        let input: AudioObjectID?
    }

    private let eventHub = CaptureEventHub()
    private var capture: Capture?
    private var device: Device?
    private var keepAlive: SilentOutput?
    private var monitor: DeviceMonitor?

    init() {}

    nonisolated func events() -> AsyncStream<CaptureEvent> {
        eventHub.makeStream()
    }

    func start(_ configuration: CaptureConfiguration) async throws(CaptureError) -> CaptureStreams {
        precondition(capture == nil, "capture already running")
        guard !configuration.sources.isEmpty else { throw .noSources }

        let input = configuration.sources.contains(.microphone)
            ? Self.resolveInputDevice(selectedUID: configuration.inputDeviceUID) : nil
        if configuration.sources == .microphone, input == nil { throw .noInputDevice }
        let captureSystem = configuration.sources.contains(.system)

        // Everything created below is released again if start fails.
        var tap: ProcessTap?
        var started = false
        defer {
            if !started {
                tap?.destroy()
                keepAlive?.stop()
                keepAlive = nil
            }
        }

        // A global tap stalls the aggregate while no process plays audio; a silent output from
        // this process keeps it running (design D2, spike finding).
        if captureSystem {
            let silentOutput = SilentOutput()
            keepAlive = silentOutput
            try silentOutput.start()
            tap = try ProcessTap.makeGlobalStereo()
        }

        // The sample rate of the first aggregate that works defines the recording.
        let probe = try Self.makeAggregate(candidates: Self.inputCandidates(input, sources: configuration.sources),
                                           tap: tap, sampleRate: nil)
        let rate = CoreAudioHAL.nominalSampleRate(of: probe.layout.aggregate) ?? AACEncoding.sampleRate
        let capacity = Int(rate * Self.ringSeconds)
        // The microphone ring exists even without a device so a later device can join and the
        // track stays aligned (silence is written while there is no microphone).
        let capture = Capture(
            configuration: configuration, sampleRate: rate, tap: tap,
            microphone: configuration.sources.contains(.microphone)
                ? RingBuffer(channels: CaptureStreams.microphoneChannels, capacityFrames: capacity) : nil,
            system: captureSystem
                ? RingBuffer(channels: CaptureStreams.systemChannels, capacityFrames: capacity) : nil,
            levels: LevelSnapshot(),
            timeline: TimelineAnchor())
        do {
            device = try Self.startIO(layout: probe.layout, input: probe.input, capture: capture)
        } catch {
            AudioHardwareDestroyAggregateDevice(probe.layout.aggregate)
            throw error
        }
        self.capture = capture
        started = true

        let monitor = DeviceMonitor { [weak self] in
            Task { await self?.handleDeviceChange() }
        }
        monitor.start()
        monitor.watchInput(probe.input)
        self.monitor = monitor

        return CaptureStreams(sampleRate: rate, microphone: capture.microphone, system: capture.system,
                              levels: capture.levels)
    }

    /// Host time to system frame mapping of the running capture, for aligning another microphone
    /// source to the system audio track (design D6).
    func systemTimeline() -> TimelineAnchor? {
        capture?.timeline
    }

    func stop() async {
        monitor?.stop()
        monitor = nil
        tearDownDevice()
        capture?.tap?.destroy()
        capture = nil
        keepAlive?.stop()
        keepAlive = nil
        eventHub.finish()
    }

    // MARK: - Device changes (design D3)

    private func handleDeviceChange() {
        guard let capture, let device else { return }
        let desiredInput = capture.configuration.sources.contains(.microphone)
            ? Self.resolveInputDevice(selectedUID: capture.configuration.inputDeviceUID) : nil
        let inputLost = device.input.map { !CoreAudioHAL.isAlive($0) } ?? false
        let inputChanged = desiredInput != device.input || inputLost
        // Without a microphone the output device is the clock; follow the new default output.
        let clockChanged = device.input == nil && CoreAudioHAL.defaultOutputDevice() != device.clock
        guard inputChanged || clockChanged else { return }

        tearDownDevice()
        do throws(CaptureError) {
            let built = try Self.makeAggregate(
                candidates: Self.inputCandidates(desiredInput, sources: capture.configuration.sources),
                tap: capture.tap, sampleRate: capture.sampleRate)
            do throws(CaptureError) {
                self.device = try Self.startIO(layout: built.layout, input: built.input, capture: capture)
            } catch {
                AudioHardwareDestroyAggregateDevice(built.layout.aggregate)
                throw error
            }
            monitor?.watchInput(built.input)
            if let input = built.input, input != device.input || inputLost {
                eventHub.yield(.inputDeviceChanged(name: CoreAudioHAL.name(of: input) ?? ""))
            }
        } catch {
            eventHub.yield(.failed(error))
        }
    }

    private func tearDownDevice() {
        guard let device else { return }
        AudioDeviceStop(device.aggregate, device.ioProc)
        AudioDeviceDestroyIOProcID(device.aggregate, device.ioProc)
        AudioHardwareDestroyAggregateDevice(device.aggregate)
        self.device = nil
    }

    /// Frames already in the rings were captured at `rate`; a new aggregate must run at it too.
    static func matchSampleRate(of aggregate: AudioObjectID, to rate: Double) throws(CaptureError) {
        guard CoreAudioHAL.nominalSampleRate(of: aggregate) != rate else { return }
        var address = CoreAudioHAL.address(kAudioDevicePropertyNominalSampleRate)
        var value = Float64(rate)
        _ = AudioObjectSetPropertyData(aggregate, &address, 0, nil, UInt32(MemoryLayout<Float64>.size), &value)
        guard CoreAudioHAL.nominalSampleRate(of: aggregate) == rate else { throw .sampleRateMismatch }
    }

    // MARK: - Setup

    /// Input devices to try, in order: the resolved device, the default input, and (when system
    /// audio is captured) no microphone at all, which keeps the recording going with a silent
    /// microphone track. For example, an aggregate device cannot be nested in our aggregate.
    static func inputCandidates(_ resolved: AudioObjectID?, sources: CaptureSources) -> [AudioObjectID?] {
        var candidates: [AudioObjectID?] = []
        if let resolved { candidates.append(resolved) }
        if let fallback = CoreAudioHAL.defaultInputDevice(), fallback != resolved { candidates.append(fallback) }
        if sources.contains(.system) || candidates.isEmpty { candidates.append(nil) }
        return candidates
    }

    /// Creates the first aggregate that works from `candidates`; with `sampleRate`, it must run at that rate.
    static func makeAggregate(candidates: [AudioObjectID?], tap: ProcessTap?,
                              sampleRate: Double?) throws(CaptureError) -> (layout: AggregateLayout, input: AudioObjectID?) {
        var lastError = CaptureError.noInputDevice
        for input in candidates {
            if input == nil, tap == nil { break }
            do throws(CaptureError) {
                let layout = try makeAggregate(input: input, tap: tap)
                if let sampleRate {
                    do throws(CaptureError) {
                        try matchSampleRate(of: layout.aggregate, to: sampleRate)
                    } catch {
                        AudioHardwareDestroyAggregateDevice(layout.aggregate)
                        throw error
                    }
                }
                return (layout, input)
            } catch {
                lastError = error
            }
        }
        throw lastError
    }

    /// The selected device if it is connected, otherwise the system default input (audio-capture spec).
    static func resolveInputDevice(selectedUID: String?) -> AudioObjectID? {
        if let selectedUID, let device = CoreAudioHAL.device(forUID: selectedUID), CoreAudioHAL.isAlive(device),
           !CoreAudioHAL.inputStreams(of: device).isEmpty {
            return device
        }
        return CoreAudioHAL.defaultInputDevice()
    }

    struct AggregateLayout {
        let aggregate: AudioObjectID
        let clock: AudioObjectID
        let micBufferIndex: Int?
        let tapBufferIndex: Int?
    }

    static func makeAggregate(input: AudioObjectID?, tap: ProcessTap?) throws(CaptureError) -> AggregateLayout {
        // The clock is the microphone; for system-only capture it is the default output device.
        let clock: AudioObjectID
        if let input {
            clock = input
        } else if let output = CoreAudioHAL.defaultOutputDevice() {
            clock = output
        } else {
            throw .coreAudio(operation: "no output device", status: 0)
        }
        guard let clockUID = CoreAudioHAL.uid(of: clock) else {
            throw .coreAudio(operation: "device UID", status: 0)
        }

        var description: [String: Any] = [
            kAudioAggregateDeviceNameKey: "kRecord Capture",
            kAudioAggregateDeviceUIDKey: "com.kozian.kRecord.capture.\(UUID().uuidString)",
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceMainSubDeviceKey: clockUID,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: clockUID]],
        ]
        if let tap {
            description[kAudioAggregateDeviceTapListKey] = [[
                kAudioSubTapUIDKey: tap.uuid.uuidString,
                kAudioSubTapDriftCompensationKey: true,
            ]]
            description[kAudioAggregateDeviceTapAutoStartKey] = true
        }

        var aggregate = AudioObjectID(kAudioObjectUnknown)
        try CoreAudioHAL.check(AudioHardwareCreateAggregateDevice(description as CFDictionary, &aggregate),
                               "AudioHardwareCreateAggregateDevice")

        // Input buffers: the clock device's input streams, then the tap stream (design D2).
        let clockStreams = CoreAudioHAL.inputStreams(of: clock).count
        let layout = AggregateLayout(aggregate: aggregate, clock: clock,
                                     micBufferIndex: input != nil ? 0 : nil,
                                     tapBufferIndex: tap != nil ? clockStreams : nil)
        do {
            try validateStreamFormats(aggregate: aggregate, layout: layout)
        } catch {
            AudioHardwareDestroyAggregateDevice(aggregate)
            throw error
        }
        return layout
    }

    /// The IOProc reads interleaved Float32; anything else is rejected rather than misread.
    private static func validateStreamFormats(aggregate: AudioObjectID, layout: AggregateLayout) throws(CaptureError) {
        let streams = CoreAudioHAL.inputStreams(of: aggregate)
        for index in [layout.micBufferIndex, layout.tapBufferIndex].compactMap({ $0 }) {
            guard index < streams.count, let format = CoreAudioHAL.virtualFormat(of: streams[index]),
                  format.mFormatID == kAudioFormatLinearPCM,
                  format.mFormatFlags & kAudioFormatFlagIsFloat != 0,
                  format.mFormatFlags & kAudioFormatFlagIsNonInterleaved == 0,
                  format.mBitsPerChannel == 32
            else { throw .unsupportedFormat }
        }
        if let tapIndex = layout.tapBufferIndex,
           CoreAudioHAL.virtualFormat(of: streams[tapIndex])?.mChannelsPerFrame != 2 {
            throw .unsupportedFormat
        }
    }

    private static func startIO(layout: AggregateLayout, input: AudioObjectID?,
                                capture: Capture) throws(CaptureError) -> Device {
        let context = AggregateIOContext(microphone: capture.microphone, system: capture.system,
                                         levels: capture.levels, timeline: capture.timeline,
                                         micBufferIndex: layout.micBufferIndex,
                                         tapBufferIndex: layout.tapBufferIndex)
        var ioProc: AudioDeviceIOProcID?
        try CoreAudioHAL.check(
            AudioDeviceCreateIOProcIDWithBlock(&ioProc, layout.aggregate, nil) { _, input, inputTime, _, _ in
                context.process(input, time: inputTime)
            },
            "AudioDeviceCreateIOProcIDWithBlock")
        guard let ioProc else { throw .coreAudio(operation: "AudioDeviceCreateIOProcIDWithBlock", status: 0) }
        do {
            try CoreAudioHAL.check(AudioDeviceStart(layout.aggregate, ioProc), "AudioDeviceStart")
        } catch {
            AudioDeviceDestroyIOProcID(layout.aggregate, ioProc)
            throw error
        }
        return Device(aggregate: layout.aggregate, ioProc: ioProc, clock: layout.clock, input: input)
    }
}

// MARK: - Real-time context

/// State touched by the IOProc. Everything it uses is preallocated; `process` is real-time safe.
final class AggregateIOContext: @unchecked Sendable {
    let microphone: RingBuffer?
    let system: RingBuffer?
    let levels: LevelSnapshot
    private let timeline: TimelineAnchor
    private let micBufferIndex: Int?
    private let tapBufferIndex: Int?
    /// Silence written in place of a missing buffer so both sources keep the same frame count.
    private let silence: UnsafeMutablePointer<Float>
    private static let silenceFrames = 8_192

    init(microphone: RingBuffer?, system: RingBuffer?, levels: LevelSnapshot, timeline: TimelineAnchor,
         micBufferIndex: Int?, tapBufferIndex: Int?) {
        self.microphone = microphone
        self.system = system
        self.levels = levels
        self.timeline = timeline
        self.micBufferIndex = micBufferIndex
        self.tapBufferIndex = tapBufferIndex
        silence = .allocate(capacity: Self.silenceFrames * 2)
        silence.initialize(repeating: 0, count: Self.silenceFrames * 2)
    }

    deinit {
        silence.deallocate()
    }

    func process(_ input: UnsafePointer<AudioBufferList>, time: UnsafePointer<AudioTimeStamp>) {
        let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
        let micFrames = write(buffers, index: micBufferIndex, to: microphone, source: .microphone)
        let systemFrames = write(buffers, index: tapBufferIndex, to: system, source: .system)
        // Keep the timelines equal if one stream delivered nothing in this cycle.
        if microphone != nil, system != nil, micFrames != systemFrames {
            let missing = abs(micFrames - systemFrames)
            writeSilence(frames: missing, to: micFrames < systemFrames ? microphone! : system!)
        }
        let systemAdvance = microphone != nil ? max(micFrames, systemFrames) : systemFrames
        if system != nil, systemAdvance > 0, time.pointee.mFlags.contains(.hostTimeValid) {
            timeline.advance(frames: systemAdvance, firstFrameHostTime: time.pointee.mHostTime)
        }
    }

    private func write(_ buffers: UnsafeMutableAudioBufferListPointer, index: Int?, to ring: RingBuffer?,
                       source: LevelSnapshot.Source) -> Int {
        guard let ring, let index, index < buffers.count else { return 0 }
        let buffer = buffers[index]
        let channels = Int(buffer.mNumberChannels)
        guard channels >= ring.channels, let data = buffer.mData?.assumingMemoryBound(to: Float.self) else { return 0 }
        let frames = Int(buffer.mDataByteSize) / (MemoryLayout<Float>.size * channels)
        ring.write(data, frameCount: frames, sourceChannels: channels)

        var level = AudioLevel.measure(data, frameCount: frames, stride: channels)
        if source == .system {
            let right = AudioLevel.measure(data + 1, frameCount: frames, stride: channels)
            level = AudioLevel(peak: max(level.peak, right.peak), rms: max(level.rms, right.rms))
        }
        levels.publish(level, for: source)
        return frames
    }

    private func writeSilence(frames: Int, to ring: RingBuffer) {
        var remaining = frames
        while remaining > 0 {
            let chunk = min(remaining, Self.silenceFrames)
            ring.write(silence, frameCount: chunk, sourceChannels: ring.channels)
            remaining -= chunk
        }
    }
}

// MARK: - Process tap

struct ProcessTap {
    let id: AudioObjectID
    let uuid: UUID

    /// A private stereo mixdown of all processes' output (design D1).
    static func makeGlobalStereo() throws(CaptureError) -> ProcessTap {
        let description = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
        description.uuid = UUID()
        description.name = "kRecord System Audio"
        description.isPrivate = true
        description.muteBehavior = .unmuted
        var id = AudioObjectID(kAudioObjectUnknown)
        try CoreAudioHAL.check(AudioHardwareCreateProcessTap(description, &id), "AudioHardwareCreateProcessTap")
        return ProcessTap(id: id, uuid: description.uuid)
    }

    func destroy() {
        AudioHardwareDestroyProcessTap(id)
    }
}

// MARK: - Silent keep-alive output

/// Plays digital silence to the default output so the global process tap keeps delivering audio
/// (design D2). Restarts itself when the output configuration changes (design D3).
final class SilentOutput {
    private var engine: AVAudioEngine?
    private var observer: NSObjectProtocol?

    func start() throws(CaptureError) {
        let engine = AVAudioEngine()
        let format = engine.outputNode.inputFormat(forBus: 0)
        let source = AVAudioSourceNode { isSilence, _, _, bufferList in
            for buffer in UnsafeMutableAudioBufferListPointer(bufferList) {
                if let data = buffer.mData { memset(data, 0, Int(buffer.mDataByteSize)) }
            }
            // Reporting silence would let the engine skip rendering, which stops the output.
            isSilence.pointee = false
            return noErr
        }
        engine.attach(source)
        engine.connect(source, to: engine.mainMixerNode, format: format)
        do {
            try engine.start()
        } catch {
            throw .coreAudio(operation: "keep-alive output", status: OSStatus((error as NSError).code))
        }
        observer = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
        ) { [weak engine] _ in
            // The engine stops itself on a configuration change, e.g. a new default output.
            try? engine?.start()
        }
        self.engine = engine
    }

    func stop() {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        engine?.stop()
        engine = nil
    }
}

// MARK: - Events

/// Hands out the event stream of the current capture; safe to use from any context.
final class CaptureEventHub: Sendable {
    private let continuation = Mutex<AsyncStream<CaptureEvent>.Continuation?>(nil)

    func makeStream() -> AsyncStream<CaptureEvent> {
        let (stream, newContinuation) = AsyncStream<CaptureEvent>.makeStream()
        continuation.withLock { $0 = newContinuation }
        return stream
    }

    func yield(_ event: CaptureEvent) {
        _ = continuation.withLock { $0?.yield(event) }
    }

    func finish() {
        continuation.withLock {
            $0?.finish()
            $0 = nil
        }
    }
}
