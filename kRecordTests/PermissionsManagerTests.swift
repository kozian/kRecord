import Foundation
import Synchronization
import Testing
@testable import kRecord

final class FakeAuthorizationProvider: AuthorizationProvider {
    struct State {
        var microphone: PermissionStatus = .notDetermined
        var systemAudio: PermissionStatus = .unknown
        var userAllowsMicrophone = true
        var microphoneRequests = 0
        var systemPromptTriggers = 0
    }

    let state = Mutex(State())

    func microphoneStatus() -> PermissionStatus { state.withLock { $0.microphone } }
    func systemAudioStatus() -> PermissionStatus { state.withLock { $0.systemAudio } }

    func requestMicrophoneAccess() async -> Bool {
        state.withLock { state in
            state.microphoneRequests += 1
            state.microphone = state.userAllowsMicrophone ? .granted : .denied
            return state.userAllowsMicrophone
        }
    }

    func triggerSystemAudioPrompt() async {
        state.withLock { $0.systemPromptTriggers += 1 }
    }
}

final class OpenedURLs: Sendable {
    private let urls = Mutex<[URL]>([])
    var all: [URL] { urls.withLock { $0 } }
    func record(_ url: URL) { urls.withLock { $0.append(url) } }
}

@MainActor
struct PermissionsManagerTests {
    private let provider = FakeAuthorizationProvider()
    private let opened = OpenedURLs()

    private func makeManager() -> PermissionsManager {
        PermissionsManager(provider: provider, openURL: { [opened] url in opened.record(url) })
    }

    @Test(arguments: [
        (PermissionStatus.granted, PermissionStatus.unknown, CaptureSources.all),
        (.granted, .granted, .all),
        (.granted, .denied, .microphone),
        (.denied, .unknown, .system),
        (.denied, .granted, .system),
        (.notDetermined, .unknown, .system),
        (.denied, .denied, CaptureSources()),
        (.notDetermined, .denied, CaptureSources()),
    ])
    func permittedSourcesFollowStatuses(microphone: PermissionStatus, system: PermissionStatus, expected: CaptureSources) {
        provider.state.withLock {
            $0.microphone = microphone
            $0.systemAudio = system
        }
        let manager = makeManager()
        #expect(manager.permittedSources == expected)
        #expect(manager.canRecord == !expected.isEmpty)
    }

    /// With the status of system audio unknown, recording stays possible even without the microphone.
    @Test func unknownSystemAudioKeepsRecordingEnabled() {
        provider.state.withLock { $0.microphone = .denied }
        let manager = makeManager()
        #expect(manager.microphoneIsBlocked)
        #expect(manager.canRecord)
    }

    @Test func refreshPicksUpChangesFromSystemSettings() {
        provider.state.withLock { $0.microphone = .denied }
        let manager = makeManager()
        #expect(manager.microphoneIsBlocked)

        provider.state.withLock { $0.microphone = .granted }
        #expect(manager.microphoneIsBlocked)
        manager.refresh()
        #expect(!manager.microphoneIsBlocked)
        #expect(manager.permittedSources == .all)
    }

    @Test func requestAllAsksMicrophoneAndTriggersSystemPrompt() async {
        let manager = makeManager()
        await manager.requestAll()
        #expect(provider.state.withLock { $0.microphoneRequests } == 1)
        #expect(provider.state.withLock { $0.systemPromptTriggers } == 1)
        #expect(manager.microphone == .granted)
    }

    @Test func deniedPromptBlocksMicrophone() async {
        provider.state.withLock { $0.userAllowsMicrophone = false }
        let manager = makeManager()
        await manager.requestAll()
        #expect(manager.microphoneIsBlocked)
        #expect(manager.permittedSources == .system)
    }

    @Test func microphoneIsNotRequestedAgainOnceDecided() async {
        provider.state.withLock { $0.microphone = .denied }
        let manager = makeManager()
        let granted = await manager.requestMicrophoneIfNeeded()
        #expect(!granted)
        #expect(provider.state.withLock { $0.microphoneRequests } == 0)
    }

    @Test func opensThePrivacyPanes() {
        let manager = makeManager()
        manager.openSettings(.microphone)
        manager.openSettings(.systemAudio)
        #expect(opened.all.map(\.absoluteString) == [
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone",
            "x-apple.systempreferences:com.apple.preference.security?Privacy_AudioCapture",
        ])
    }
}
