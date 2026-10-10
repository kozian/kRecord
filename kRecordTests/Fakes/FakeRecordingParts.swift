import Foundation
import Synchronization
@testable import kRecord

/// Writer that drains nothing; tests trigger failures and control `finish`.
final class FakeRecordingWriter: RecordingWriter {
    struct State {
        var plan: WriterPlan?
        var result = WriterResult(streams: [], systemAudioSilent: false)
        var startError: RecordingWriterError?
        var finishError: RecordingWriterError?
        var failures: AsyncStream<RecordingWriterError>.Continuation?
        var finished = false
    }

    let state = Mutex(State())

    func failures() -> AsyncStream<RecordingWriterError> {
        let (stream, continuation) = AsyncStream<RecordingWriterError>.makeStream()
        state.withLock { $0.failures = continuation }
        return stream
    }

    func start(streams: CaptureStreams, plan: WriterPlan) async throws(RecordingWriterError) {
        let error: RecordingWriterError? = state.withLock {
            $0.plan = plan
            return $0.startError
        }
        if let error { throw error }
    }

    func fail(_ error: RecordingWriterError) {
        _ = state.withLock { $0.failures?.yield(error) }
    }

    var plan: WriterPlan? { state.withLock { $0.plan } }

    func finish() async throws(RecordingWriterError) -> WriterResult {
        let (error, result) = state.withLock {
            $0.finished = true
            $0.failures?.finish()
            return ($0.finishError, $0.result)
        }
        if let error { throw error }
        return result
    }
}

/// Finalizer that records requests and can hold `finalize` until the test releases it.
final class FakeFinalizer: Finalizer {
    struct State {
        var requests: [FinalizationRequest] = []
        var outputs: [URL] = []
        var error: FinalizerError?
        var holding = false
        var waiting: CheckedContinuation<Void, Never>?
    }

    let state = Mutex(State())

    var requests: [FinalizationRequest] { state.withLock { $0.requests } }

    /// Makes the next `finalize` wait until `release()`.
    func hold() {
        state.withLock { $0.holding = true }
    }

    func release() {
        let waiting = state.withLock { state in
            state.holding = false
            defer { state.waiting = nil }
            return state.waiting
        }
        waiting?.resume()
    }

    var isWaiting: Bool { state.withLock { $0.waiting != nil } }

    func finalize(_ request: FinalizationRequest) async throws(FinalizerError) -> [URL] {
        let holding = state.withLock {
            $0.requests.append(request)
            return $0.holding
        }
        if holding {
            await withCheckedContinuation { continuation in
                state.withLock { $0.waiting = continuation }
            }
        }
        let (outputs, error) = state.withLock { ($0.outputs, $0.error) }
        if let error { throw error }
        return outputs
    }
}

/// Storage guard with an injectable start error and a monitor the test can trigger.
final class FakeStorageGuard: StorageGuard {
    struct State {
        var prepareError: StorageError?
        var prepared: [URL] = []
        var monitor: AsyncStream<StorageError>.Continuation?
    }

    let state = Mutex(State())

    func prepare(_ folder: URL) throws(StorageError) {
        let error: StorageError? = state.withLock {
            $0.prepared.append(folder)
            return $0.prepareError
        }
        if let error { throw error }
    }

    func monitor(_ folder: URL) -> AsyncStream<StorageError> {
        let (stream, continuation) = AsyncStream<StorageError>.makeStream()
        state.withLock { $0.monitor = continuation }
        return stream
    }

    func report(_ problem: StorageError) {
        _ = state.withLock { $0.monitor?.yield(problem) }
    }
}

/// Manually advanced clock.
final class FakeClock: Sendable {
    private let uptimeValue = Mutex<TimeInterval>(1_000)
    let date: Date

    init(date: Date = Date(timeIntervalSince1970: 1_791_000_000)) {
        self.date = date
    }

    func advance(by seconds: TimeInterval) {
        uptimeValue.withLock { $0 += seconds }
    }

    var sessionClock: SessionClock {
        SessionClock(date: { [date] in date }, uptime: { [self] in uptimeValue.withLock { $0 } })
    }
}
