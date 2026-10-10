import Foundation
import Synchronization
@testable import kRecord

/// Deterministic `CaptureEngine` for tests: frames are produced only when the test calls `pump`.
///
/// Frame `n` (counted from the start of the capture) has microphone sample `micSample(n)` and
/// system samples `systemSample(n, channel)`, so tests can verify exact content and alignment.
final class FakeCaptureEngine: CaptureEngine {
    struct State {
        var configurations: [CaptureConfiguration] = []
        var startError: CaptureError?
        var streams: CaptureStreams?
        var continuation: AsyncStream<CaptureEvent>.Continuation?
        var framesProduced = 0
        var stopCount = 0
    }

    let sampleRate: Double
    let capacityFrames: Int
    let state = Mutex(State())

    init(sampleRate: Double = 48_000, capacityFrames: Int = 48_000 * 5) {
        self.sampleRate = sampleRate
        self.capacityFrames = capacityFrames
    }

    static func micSample(_ frame: Int) -> Float {
        Float(frame % 1000) / 1000
    }

    static func systemSample(_ frame: Int, channel: Int) -> Float {
        channel == 0 ? -Float(frame % 1000) / 1000 : Float(frame % 500) / 1000
    }

    var configurations: [CaptureConfiguration] { state.withLock { $0.configurations } }
    var stopCount: Int { state.withLock { $0.stopCount } }
    var isRunning: Bool { state.withLock { $0.streams != nil } }

    func failNextStart(with error: CaptureError) {
        state.withLock { $0.startError = error }
    }

    func events() -> AsyncStream<CaptureEvent> {
        let (stream, continuation) = AsyncStream<CaptureEvent>.makeStream()
        state.withLock { $0.continuation = continuation }
        return stream
    }

    func emit(_ event: CaptureEvent) {
        _ = state.withLock { $0.continuation?.yield(event) }
    }

    func start(_ configuration: CaptureConfiguration) async throws(CaptureError) -> CaptureStreams {
        let result: Result<CaptureStreams, CaptureError> = state.withLock { state in
            state.configurations.append(configuration)
            if let error = state.startError {
                state.startError = nil
                return .failure(error)
            }
            if configuration.sources.isEmpty { return .failure(.noSources) }
            let streams = CaptureStreams(
                sampleRate: sampleRate,
                microphone: configuration.sources.contains(.microphone)
                    ? RingBuffer(channels: CaptureStreams.microphoneChannels, capacityFrames: capacityFrames) : nil,
                system: configuration.sources.contains(.system)
                    ? RingBuffer(channels: CaptureStreams.systemChannels, capacityFrames: capacityFrames) : nil,
                levels: LevelSnapshot())
            state.streams = streams
            state.framesProduced = 0
            return .success(streams)
        }
        return try result.get()
    }

    /// Produces `frames` deterministic frames into every active ring buffer and publishes levels.
    func pump(frames: Int) {
        state.withLock { state in
            guard let streams = state.streams, frames > 0 else { return }
            let first = state.framesProduced
            var mic = [Float](repeating: 0, count: frames)
            var system = [Float](repeating: 0, count: frames * 2)
            for i in 0..<frames {
                mic[i] = Self.micSample(first + i)
                system[i * 2] = Self.systemSample(first + i, channel: 0)
                system[i * 2 + 1] = Self.systemSample(first + i, channel: 1)
            }
            if let ring = streams.microphone {
                ring.write(mic, frameCount: frames, sourceChannels: 1)
                streams.levels.publish(AudioLevel.measure(mic, frameCount: frames), for: .microphone)
            }
            if let ring = streams.system {
                ring.write(system, frameCount: frames, sourceChannels: 2)
                streams.levels.publish(AudioLevel.measure(system, frameCount: frames, stride: 2), for: .system)
            }
            state.framesProduced += frames
        }
    }

    func stop() async {
        state.withLock { state in
            state.streams = nil
            state.stopCount += 1
            state.continuation?.finish()
            state.continuation = nil
        }
    }
}
