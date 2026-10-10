import AVFoundation
import Foundation

/// The files a recording writes while it runs (design D5).
enum WriterPlan: Equatable, Sendable {
    /// One stereo stream: system audio with the microphone mixed into the center.
    case mixed(URL)
    /// Separate streams; `nil` for a source that is not captured.
    case separate(microphone: URL?, system: URL?)
}

/// A finished AAC stream and the number of audio frames encoded into it.
struct RecordedStream: Equatable, Sendable {
    var url: URL
    var frames: Int
}

struct WriterResult: Equatable, Sendable {
    var streams: [RecordedStream]
    /// System audio was captured but every sample was digital zero, which usually means the system
    /// audio recording permission is denied (permissions spec).
    var systemAudioSilent: Bool
}

enum RecordingWriterError: Error, Equatable, Sendable {
    case cannotCreateFile(URL)
    case writeFailed(URL)
}

/// Drains capture ring buffers into AAC streams while a recording runs (design D4, D5).
protocol RecordingWriter: AnyObject, Sendable {
    /// Creates the files and starts draining `streams` into them.
    func start(streams: CaptureStreams, plan: WriterPlan) async throws(RecordingWriterError)

    /// Reports the first write failure during the recording, then ends. Call before `start`.
    func failures() -> AsyncStream<RecordingWriterError>

    /// Encodes everything left in the ring buffers and closes the files.
    /// Call after the capture engine has stopped.
    func finish() async throws(RecordingWriterError) -> WriterResult
}

enum AudioMix {
    /// Each source is mixed at -3 dB so that two loud sources rarely clip.
    static let gain: Float = 0.707_945_8

    /// Mixes mono `microphone` into the center of interleaved stereo `system` (either may be absent)
    /// and writes clamped left/right samples.
    static func mix(microphone: UnsafePointer<Float>?, system: UnsafePointer<Float>?, frames: Int,
                    left: UnsafeMutablePointer<Float>, right: UnsafeMutablePointer<Float>) {
        for frame in 0..<frames {
            let mic = microphone?[frame] ?? 0
            let systemLeft = system?[frame * 2] ?? 0
            let systemRight = system?[frame * 2 + 1] ?? 0
            left[frame] = min(max(gain * (systemLeft + mic), -1), 1)
            right[frame] = min(max(gain * (systemRight + mic), -1), 1)
        }
    }
}

/// Encodes AAC into ADTS `.aac` files. An ADTS stream is a sequence of self-describing frames,
/// so a file that is never closed (crash, force quit) stays playable up to about the last write.
actor AACRecordingWriter: RecordingWriter {
    static let drainInterval: Duration = .milliseconds(50)

    private let chunkFrames: Int
    private var plan: WriterPlan?
    private var microphone: SourceQueue?
    private var system: SourceQueue?
    private var outputs: [AACStreamFile] = []
    private var micScratch: UnsafeMutablePointer<Float>?
    private var systemScratch: UnsafeMutablePointer<Float>?
    private var systemSawSignal = false
    private var drainTask: Task<Void, Never>?
    private var failureContinuation: AsyncStream<RecordingWriterError>.Continuation?
    private var failure: RecordingWriterError?

    /// - Parameter chunkFrames: maximum frames encoded per step; one second at 48 kHz by default.
    init(chunkFrames: Int = 48_000) {
        self.chunkFrames = chunkFrames
    }

    nonisolated func failures() -> AsyncStream<RecordingWriterError> {
        let (stream, continuation) = AsyncStream<RecordingWriterError>.makeStream()
        Task { await self.setFailureContinuation(continuation) }
        return stream
    }

    private func setFailureContinuation(_ continuation: AsyncStream<RecordingWriterError>.Continuation) {
        if let failure {
            continuation.yield(failure)
            continuation.finish()
        } else {
            failureContinuation = continuation
        }
    }

    func start(streams: CaptureStreams, plan: WriterPlan) async throws(RecordingWriterError) {
        precondition(drainTask == nil, "writer already started")
        self.plan = plan
        microphone = streams.microphone.map(SourceQueue.init)
        system = streams.system.map(SourceQueue.init)
        micScratch = .allocate(capacity: chunkFrames)
        systemScratch = .allocate(capacity: chunkFrames * 2)

        let rate = streams.sampleRate
        switch plan {
        case let .mixed(url):
            outputs = [try AACStreamFile(url: url, channels: 2, inputSampleRate: rate, capacity: chunkFrames)]
        case let .separate(microphoneURL, systemURL):
            if microphone != nil, let microphoneURL {
                outputs.append(try AACStreamFile(url: microphoneURL, channels: 1, inputSampleRate: rate,
                                                 capacity: chunkFrames))
            }
            if system != nil, let systemURL {
                do {
                    outputs.append(try AACStreamFile(url: systemURL, channels: 2, inputSampleRate: rate,
                                                     capacity: chunkFrames))
                } catch {
                    closeOutputs()
                    throw error
                }
            }
        }

        drainTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.drainInterval)
                guard let self, await self.drainAvailable() else { return }
            }
        }
    }

    func finish() async throws(RecordingWriterError) -> WriterResult {
        drainTask?.cancel()
        await drainTask?.value
        drainTask = nil
        if failure == nil { _ = drain(final: true) }
        let result = WriterResult(streams: outputs.map { RecordedStream(url: $0.url, frames: $0.encodedFrames) },
                                  systemAudioSilent: system != nil && !systemSawSignal)
        closeOutputs()
        failureContinuation?.finish()
        failureContinuation = nil
        if let failure { throw failure }
        return result
    }

    /// Encodes the frames that are available from every source. Returns `false` after a write failure.
    @discardableResult
    func drainAvailable() -> Bool {
        drain(final: false)
    }

    // MARK: - Draining

    /// In mixed mode both sources advance together; `final` also flushes a source that is ahead.
    private func drain(final: Bool) -> Bool {
        guard failure == nil, let plan else { return false }
        microphone?.collectDrops()
        system?.collectDrops()
        do {
            switch plan {
            case .mixed:
                let available = [microphone?.available, system?.available].compactMap { $0 }
                let frames = (final ? available.max() : available.min()) ?? 0
                try encodeMixed(frames: frames)
            case .separate:
                try encodeSeparately()
            }
            return true
        } catch {
            failure = error
            failureContinuation?.yield(error)
            failureContinuation?.finish()
            failureContinuation = nil
            return false
        }
    }

    private func encodeMixed(frames total: Int) throws(RecordingWriterError) {
        guard let output = outputs.first, let micScratch, let systemScratch else { return }
        var remaining = total
        while remaining > 0 {
            let frames = min(remaining, chunkFrames)
            let micFrames = microphone.map { $0.read(into: micScratch, frames: min(frames, $0.available)) }
            let systemFrames = system.map { $0.read(into: systemScratch, frames: min(frames, $0.available)) }
            // A source that ran short is padded with silence (only at the very end of a recording).
            if let micFrames, micFrames < frames { (micScratch + micFrames).update(repeating: 0, count: frames - micFrames) }
            if let systemFrames, systemFrames < frames {
                (systemScratch + systemFrames * 2).update(repeating: 0, count: (frames - systemFrames) * 2)
            }
            if systemFrames != nil { noteSystemSignal(systemScratch, samples: frames * 2) }
            let channels = output.channelData
            AudioMix.mix(microphone: microphone != nil ? micScratch : nil, system: system != nil ? systemScratch : nil,
                         frames: frames, left: channels[0], right: channels[1])
            try output.write(frames: frames)
            remaining -= frames
        }
    }

    private func encodeSeparately() throws(RecordingWriterError) {
        guard let systemScratch else { return }
        for output in outputs {
            let isMicrophone = output.channels == 1
            guard let source = isMicrophone ? microphone : system else { continue }
            while source.available > 0 {
                let frames = min(source.available, chunkFrames)
                let channels = output.channelData
                if isMicrophone {
                    _ = source.read(into: channels[0], frames: frames)
                } else {
                    _ = source.read(into: systemScratch, frames: frames)
                    noteSystemSignal(systemScratch, samples: frames * 2)
                    for frame in 0..<frames {
                        channels[0][frame] = systemScratch[frame * 2]
                        channels[1][frame] = systemScratch[frame * 2 + 1]
                    }
                }
                try output.write(frames: frames)
            }
        }
    }

    private func noteSystemSignal(_ samples: UnsafePointer<Float>, samples count: Int) {
        guard !systemSawSignal else { return }
        for index in 0..<count where samples[index] != 0 {
            systemSawSignal = true
            return
        }
    }

    private func closeOutputs() {
        outputs.forEach { $0.close() }
        outputs = []
        micScratch?.deallocate()
        systemScratch?.deallocate()
        micScratch = nil
        systemScratch = nil
    }
}

/// A ring buffer plus silence owed for frames the producer had to drop, so the timeline stays aligned.
private final class SourceQueue {
    let ring: RingBuffer
    private var droppedSeen = 0
    private var pendingSilence = 0

    init(_ ring: RingBuffer) {
        self.ring = ring
    }

    var available: Int { pendingSilence + ring.availableFrames }

    func collectDrops() {
        let dropped = ring.droppedFrames
        pendingSilence += dropped - droppedSeen
        droppedSeen = dropped
    }

    /// Reads up to `frames` interleaved frames: owed silence first, then ring data.
    func read(into destination: UnsafeMutablePointer<Float>, frames: Int) -> Int {
        let silence = min(frames, pendingSilence)
        destination.update(repeating: 0, count: silence * ring.channels)
        pendingSilence -= silence
        let fromRing = ring.read(into: destination + silence * ring.channels, maxFrames: frames - silence)
        return silence + fromRing
    }
}
