import Foundation
import Testing
@testable import kRecord

@MainActor
struct AppModelTests {
    // MARK: Record control

    @Test func canStartWhenASourceIsPermitted() {
        let app = TestApp(microphone: .denied)
        // System audio status is unknown, so recording stays possible without the microphone.
        #expect(app.model.canToggleRecording)
    }

    @Test func cannotStartWhenNothingIsPermitted() {
        let app = TestApp(microphone: .denied)
        app.provider.state.withLock { $0.systemAudio = .denied }
        app.permissions.refresh()
        #expect(!app.model.canToggleRecording)
    }

    @Test func controlFollowsSessionState() async {
        let app = TestApp()
        #expect(app.model.canToggleRecording)
        #expect(!app.model.recordingSettingsAreLocked)

        await app.model.toggleRecording()
        #expect(app.session.state == .recording)
        #expect(app.model.canToggleRecording)
        #expect(app.model.recordingSettingsAreLocked)

        app.finalizer.hold()
        let stopping = Task { await app.model.toggleRecording() }
        while !app.finalizer.isWaiting { await Task.yield() }
        #expect(app.session.state == .finishing)
        #expect(!app.model.canToggleRecording)
        #expect(app.model.recordingSettingsAreLocked)

        app.finalizer.release()
        await stopping.value
        #expect(app.session.state == .idle)
        #expect(!app.model.recordingSettingsAreLocked)
    }

    @Test func startAsksForUndecidedMicrophoneFirst() async {
        let app = TestApp(microphone: .notDetermined)
        await app.model.startRecording()
        #expect(app.provider.state.withLock { $0.microphoneRequests } == 1)
        #expect(app.session.state == .recording)
        #expect(app.engine.configurations.first?.sources == .all)
    }

    @Test func startRecordsOnlySystemAudioWhenMicrophoneIsDenied() async {
        let app = TestApp(microphone: .denied)
        await app.model.startRecording()
        #expect(app.provider.state.withLock { $0.microphoneRequests } == 0)
        #expect(app.engine.configurations.first?.sources == .system)
    }

    @Test func microphoneOffIsNotRequestedOrRecorded() async {
        let app = TestApp(microphone: .notDetermined)
        app.settings.recordsMicrophone = false
        await app.model.startRecording()
        #expect(app.provider.state.withLock { $0.microphoneRequests } == 0)
        #expect(app.engine.configurations.first?.sources == .system)
    }

    @Test func bothSourcesOffDisableTheControl() {
        let app = TestApp()
        app.settings.recordsMicrophone = false
        app.settings.recordsSystemAudio = false
        #expect(!app.model.canToggleRecording)
    }

    // MARK: First launch

    @Test func firstLaunchRequestsPermissionsOnce() async {
        let app = TestApp(microphone: .notDetermined)
        await app.model.requestPermissionsOnFirstLaunch()
        #expect(app.provider.state.withLock { $0.microphoneRequests } == 1)
        #expect(app.provider.state.withLock { $0.systemPromptTriggers } == 1)
        #expect(app.settings.hasRequestedPermissions)

        await app.model.requestPermissionsOnFirstLaunch()
        #expect(app.provider.state.withLock { $0.microphoneRequests } == 1)
        #expect(app.provider.state.withLock { $0.systemPromptTriggers } == 1)
    }

    @Test func launchDoesNotPromptInsideTests() async {
        let app = TestApp(microphone: .notDetermined)
        app.model.launch()
        await Task.yield()
        #expect(app.provider.state.withLock { $0.microphoneRequests } == 0)
    }

    // MARK: Quit

    @Test func quitWhileIdleNeedsNoConfirmation() async {
        let app = TestApp()
        #expect(!app.model.quit.needsHandling)
        #expect(await app.model.quit.shouldQuit())
        #expect(app.confirmation.asked == 0)
    }

    @Test func confirmedQuitStopsAndSavesTheRecording() async {
        let app = TestApp()
        await app.model.startRecording()
        #expect(app.model.quit.needsHandling)

        #expect(await app.model.quit.shouldQuit())
        #expect(app.confirmation.asked == 1)
        #expect(app.session.state == .idle)
        #expect(app.finalizer.requests.count == 1)
    }

    @Test func cancelledQuitKeepsRecording() async {
        let app = TestApp()
        app.confirmation.answer(false)
        await app.model.startRecording()

        #expect(await !app.model.quit.shouldQuit())
        #expect(app.confirmation.asked == 1)
        #expect(app.session.state == .recording)
        #expect(app.finalizer.requests.isEmpty)
    }

    @Test func quitWaitsForSavingWithoutAsking() async {
        let app = TestApp()
        await app.model.startRecording()
        app.finalizer.hold()
        let stopping = Task { await app.session.stop() }
        while !app.finalizer.isWaiting { await Task.yield() }

        let quitting = Task { await app.model.quit.shouldQuit() }
        for _ in 0..<10 { await Task.yield() }
        app.finalizer.release()
        await stopping.value
        #expect(await quitting.value)
        #expect(app.confirmation.asked == 0)
        #expect(app.session.state == .idle)
    }
}
