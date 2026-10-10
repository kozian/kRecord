import Foundation
import Testing
@testable import kRecord

@MainActor
final class RecordingSessionTests {
    let engine = FakeCaptureEngine()
    let writer = FakeRecordingWriter()
    let finalizer = FakeFinalizer()
    let storage = FakeStorageGuard()
    let clock = FakeClock()
    var settings = RecordingSettings.defaults
    var permitted: CaptureSources = .all
    var engineRequests: [Bool] = []

    init() {
        settings.destinationFolder = URL(fileURLWithPath: "/tmp/kRecordSessionTests", isDirectory: true)
    }

    lazy var session = RecordingSession(dependencies: RecordingSession.Dependencies(
        settings: { [unowned self] in settings },
        permittedSources: { [unowned self] in permitted },
        makeEngine: { [unowned self] echoCancellation in
            engineRequests.append(echoCancellation)
            return engine
        },
        makeWriter: { [writer] in writer },
        finalizer: finalizer,
        storage: storage,
        clock: clock.sessionClock,
        refreshInterval: nil))

    /// Lets monitoring tasks deliver events to the main actor.
    private func settle() async {
        for _ in 0..<20 { await Task.yield() }
    }

    // MARK: Start and stop

    @Test func startThenStopSavesRecording() async throws {
        await session.start()
        #expect(session.state == .recording)
        #expect(engine.isRunning)
        #expect(engine.configurations == [CaptureConfiguration(inputDeviceUID: nil, sources: .all)])

        await session.stop()
        #expect(session.state == .idle)
        #expect(!engine.isRunning)
        #expect(writer.state.withLock { $0.finished })
        let request = try #require(finalizer.requests.first)
        #expect(request.format == .aac)
        #expect(!request.separateFiles)
        #expect(request.baseName == FileNaming.baseName(for: clock.date))
        #expect(request.intermediates.microphone?.lastPathComponent == "\(request.baseName) (recording mic).caf")
        #expect(request.intermediates.system?.lastPathComponent == "\(request.baseName) (recording system).caf")
        #expect(session.lastError == nil)
        #expect(session.lastResult != nil)
    }

    @Test func elapsedTimeFollowsClock() async {
        await session.start()
        #expect(session.formattedElapsedTime == "00:00:00")
        clock.advance(by: 65.4)
        session.refresh()
        #expect(session.formattedElapsedTime == "00:01:05")
        clock.advance(by: 3_600)
        session.refresh()
        #expect(session.formattedElapsedTime == "01:01:05")
        await session.stop()
        #expect(session.formattedElapsedTime == "00:00:00")
    }

    @Test func elapsedFormat() {
        #expect(RecordingSession.format(elapsedSeconds: 0) == "00:00:00")
        #expect(RecordingSession.format(elapsedSeconds: 754) == "00:12:34")
        #expect(RecordingSession.format(elapsedSeconds: 36_000) == "10:00:00")
    }

    @Test func stopWhenIdleDoesNothing() async {
        await session.stop()
        #expect(session.state == .idle)
        #expect(finalizer.requests.isEmpty)
    }

    // MARK: Settings snapshot and engine choice

    @Test func settingsAreSnapshotAtStart() async throws {
        settings.format = .wav
        settings.separateFiles = true
        settings.inputDeviceUID = "usb-mic"
        await session.start()
        settings.format = .alac
        settings.separateFiles = false
        await session.stop()

        let request = try #require(finalizer.requests.first)
        #expect(request.format == .wav)
        #expect(request.separateFiles)
        #expect(engine.configurations.first?.inputDeviceUID == "usb-mic")
    }

    @Test func echoCancellationSettingChoosesEngine() async {
        await session.start()
        await session.stop()
        settings.echoCancellation = true
        await session.start()
        await session.stop()
        #expect(engineRequests == [false, true])
    }

    // MARK: Permissions

    @Test func startBlockedWithoutPermissions() async {
        permitted = []
        #expect(!session.canStart)
        await session.start()
        #expect(session.state == .idle)
        #expect(session.lastError == .noPermission)
        #expect(engine.configurations.isEmpty)
    }

    @Test func recordsOnlyPermittedSources() async {
        permitted = .system
        await session.start()
        #expect(engine.configurations.first?.sources == .system)
        await session.stop()
        let request = finalizer.requests.first
        #expect(request?.intermediates.microphone == nil)
        #expect(request?.intermediates.system != nil)
    }

    // MARK: Finishing

    @Test func startBlockedWhileFinishing() async {
        await session.start()
        finalizer.hold()
        let stopping = Task { await session.stop() }
        while !finalizer.isWaiting { await Task.yield() }

        #expect(session.state == .finishing)
        #expect(!session.canStart)
        await session.start()
        #expect(engine.configurations.count == 1)

        finalizer.release()
        await stopping.value
        #expect(session.state == .idle)
        #expect(session.canStart)
    }

    // MARK: Errors

    @Test func unwritableFolderBlocksStart() async {
        storage.state.withLock { $0.prepareError = .folderNotWritable(URL(fileURLWithPath: "/x")) }
        await session.start()
        #expect(session.state == .idle)
        #expect(session.lastError == .folderNotWritable)
        #expect(engine.configurations.isEmpty)
    }

    @Test func captureStartFailure() async {
        engine.failNextStart(with: .coreAudio(operation: "test", status: -1))
        await session.start()
        #expect(session.state == .idle)
        #expect(session.lastError == .captureFailed)
    }

    @Test func writerStartFailureStopsCapture() async {
        writer.state.withLock { $0.startError = .cannotCreateFile(URL(fileURLWithPath: "/x")) }
        await session.start()
        #expect(session.state == .idle)
        #expect(session.lastError == .writeFailed)
        #expect(!engine.isRunning)
    }

    @Test(arguments: [
        (StorageError.diskFull, RecordingError.diskFull),
        (StorageError.folderUnavailable(URL(fileURLWithPath: "/Volumes/USB")), RecordingError.folderUnavailable),
    ])
    func storageProblemDuringRecordingStopsWithError(problem: StorageError, expected: RecordingError) async {
        await session.start()
        storage.report(problem)
        await settle()
        #expect(session.state == .idle)
        #expect(session.lastError == expected)
        // Audio written so far is still finalized.
        #expect(finalizer.requests.count == 1)
    }

    @Test func captureFailureDuringRecordingStopsWithError() async {
        await session.start()
        engine.emit(.failed(.coreAudio(operation: "device", status: -1)))
        await settle()
        #expect(session.state == .idle)
        #expect(session.lastError == .captureFailed)
    }

    @Test func writeFailureDuringRecordingStopsWithError() async {
        await session.start()
        writer.fail(.writeFailed(URL(fileURLWithPath: "/x")))
        await settle()
        #expect(session.state == .idle)
        #expect(session.lastError == .writeFailed)
    }

    @Test func saveFailureKeepsErrorUntilDismissed() async {
        finalizer.state.withLock { $0.error = .cannotWriteOutput(URL(fileURLWithPath: "/x")) }
        await session.start()
        await session.stop()
        #expect(session.lastError == .saveFailed)
        session.dismissError()
        #expect(session.lastError == nil)
    }

    @Test func newRecordingClearsPreviousError() async {
        finalizer.state.withLock { $0.error = .cannotWriteOutput(URL(fileURLWithPath: "/x")) }
        await session.start()
        await session.stop()
        finalizer.state.withLock { $0.error = nil }
        await session.start()
        #expect(session.lastError == nil)
        await session.stop()
    }

    @Test func silentSystemAudioIsReported() async {
        finalizer.state.withLock { $0.result = FinalizationResult(outputs: [], systemAudioSilent: true) }
        await session.start()
        await session.stop()
        #expect(session.lastResult?.systemAudioSilent == true)
    }

    @Test func everyErrorHasAMessage() {
        let errors: [RecordingError] = [.noPermission, .folderNotWritable, .folderUnavailable, .diskFull,
                                        .captureFailed, .writeFailed, .saveFailed]
        #expect(Set(errors.map(\.message)).count == errors.count)
    }
}
