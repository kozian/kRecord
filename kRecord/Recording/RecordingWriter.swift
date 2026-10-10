import AVFoundation
import Foundation

/// Intermediate crash-safe files of one recording (design D5). `nil` for a source that is not captured.
struct IntermediateFiles: Equatable, Sendable {
    var microphone: URL?
    var system: URL?

    var all: [URL] { [microphone, system].compactMap { $0 } }
}

struct WrittenFrames: Equatable, Sendable {
    var microphone: Int
    var system: Int
}

enum RecordingWriterError: Error, Equatable, Sendable {
    case cannotCreateFile(URL)
    case writeFailed(URL)
}

/// Drains capture ring buffers to intermediate files while a recording runs (design D4, D5).
protocol RecordingWriter: AnyObject, Sendable {
    /// Creates the files and starts draining `streams` into them.
    func start(streams: CaptureStreams, files: IntermediateFiles) async throws(RecordingWriterError)

    /// Reports the first write failure during the recording, then ends. Call before `start`.
    func failures() -> AsyncStream<RecordingWriterError>

    /// Drains everything left in the ring buffers and closes the files.
    /// Call after the capture engine has stopped.
    func finish() async throws(RecordingWriterError) -> WrittenFrames
}

/// Writes 16-bit PCM CAF files. CAF stores the audio data size as "unknown" until the file is
/// closed, so a file that is never closed (crash, force quit) remains playable up to about the last
/// write: the file layer may keep up to a few tens of milliseconds in memory that are lost.
actor CAFRecordingWriter: RecordingWriter {
    static let drainInterval: Duration = .milliseconds(50)

    private struct Track {
        let ring: RingBuffer
        let file: AVAudioFile
        let buffer: AVAudioPCMBuffer
        let scratch: UnsafeMutablePointer<Float>
        var droppedFramesSeen = 0
        var framesWritten = 0
    }

    private let chunkFrames: Int
    private var microphone: Track?
    private var system: Track?
    private var drainTask: Task<Void, Never>?
    private var failureContinuation: AsyncStream<RecordingWriterError>.Continuation?
    private var failure: RecordingWriterError?

    /// - Parameter chunkFrames: maximum frames moved per read; one second at 48 kHz by default.
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

    func start(streams: CaptureStreams, files: IntermediateFiles) async throws(RecordingWriterError) {
        precondition(drainTask == nil, "writer already started")
        if let ring = streams.microphone, let url = files.microphone {
            microphone = try makeTrack(ring: ring, url: url, sampleRate: streams.sampleRate)
        }
        if let ring = streams.system, let url = files.system {
            do {
                system = try makeTrack(ring: ring, url: url, sampleRate: streams.sampleRate)
            } catch {
                closeTracks()
                throw error
            }
        }
        drainTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.drainInterval)
                guard let self, await self.drainAvailable() else { return }
            }
        }
    }

    func finish() async throws(RecordingWriterError) -> WrittenFrames {
        drainTask?.cancel()
        await drainTask?.value
        drainTask = nil
        if failure == nil { _ = drainAvailable() }
        let frames = WrittenFrames(microphone: microphone?.framesWritten ?? 0, system: system?.framesWritten ?? 0)
        closeTracks()
        failureContinuation?.finish()
        failureContinuation = nil
        if let failure { throw failure }
        return frames
    }

    /// Writes all frames currently available. Returns `false` after a write failure.
    @discardableResult
    func drainAvailable() -> Bool {
        guard failure == nil else { return false }
        do {
            if var track = microphone {
                try drain(&track)
                microphone = track
            }
            if var track = system {
                try drain(&track)
                system = track
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

    // MARK: - Private

    private func makeTrack(ring: RingBuffer, url: URL, sampleRate: Double) throws(RecordingWriterError) -> Track {
        let channels = AVAudioChannelCount(ring.channels)
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: channels,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
        ]
        guard let file = try? AVAudioFile(forWriting: url, settings: settings,
                                          commonFormat: .pcmFormatFloat32, interleaved: false),
              let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate,
                                         channels: channels, interleaved: false),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(chunkFrames))
        else { throw .cannotCreateFile(url) }
        let scratch = UnsafeMutablePointer<Float>.allocate(capacity: chunkFrames * ring.channels)
        return Track(ring: ring, file: file, buffer: buffer, scratch: scratch)
    }

    private func drain(_ track: inout Track) throws(RecordingWriterError) {
        // Frames the producer had to drop are replaced by silence to keep the timeline aligned.
        let dropped = track.ring.droppedFrames
        var silence = dropped - track.droppedFramesSeen
        track.droppedFramesSeen = dropped
        while silence > 0 {
            let frames = min(silence, chunkFrames)
            try write(&track, frames: frames) { channel, destination in
                destination.update(repeating: 0, count: frames)
            }
            silence -= frames
        }

        while true {
            let frames = track.ring.read(into: track.scratch, maxFrames: chunkFrames)
            guard frames > 0 else { return }
            let channels = track.ring.channels
            let scratch = track.scratch
            try write(&track, frames: frames) { channel, destination in
                for frame in 0..<frames {
                    destination[frame] = scratch[frame * channels + channel]
                }
            }
        }
    }

    private func write(_ track: inout Track, frames: Int,
                       fill: (Int, UnsafeMutablePointer<Float>) -> Void) throws(RecordingWriterError) {
        guard let channelData = track.buffer.floatChannelData else { throw .writeFailed(track.file.url) }
        for channel in 0..<track.ring.channels {
            fill(channel, channelData[channel])
        }
        track.buffer.frameLength = AVAudioFrameCount(frames)
        do {
            try track.file.write(from: track.buffer)
        } catch {
            throw .writeFailed(track.file.url)
        }
        track.framesWritten += frames
    }

    private func closeTracks() {
        for track in [microphone, system].compactMap({ $0 }) {
            track.file.close()
            track.scratch.deallocate()
        }
        microphone = nil
        system = nil
    }
}
