import Foundation
import Synchronization
@testable import kRecord

/// Answers the quit confirmation and counts how often it was asked.
final class QuitConfirmation: Sendable {
    private let state = Mutex((answer: true, asked: 0))
    var asked: Int { state.withLock { $0.asked } }
    func answer(_ value: Bool) { state.withLock { $0.answer = value } }
    func ask() -> Bool { state.withLock { state in
        state.asked += 1
        return state.answer
    } }
}

/// An `AppModel` wired to fakes, with the fakes exposed for scripting.
@MainActor
final class TestApp {
    let engine = FakeCaptureEngine()
    let writer = FakeRecordingWriter()
    let finalizer = FakeFinalizer()
    let storage = FakeStorageGuard()
    let clock = FakeClock()
    let provider = FakeAuthorizationProvider()
    let folderAccess = FakeFolderAccess()
    let confirmation = QuitConfirmation()
    let settings: SettingsStore
    let devices: AudioDeviceCatalog
    let permissions: PermissionsManager
    let session: RecordingSession
    let model: AppModel

    init(devices inputDevices: [InputDevice] = [InputDevice(uid: "builtin", name: "Studio Display Microphone"),
                                                InputDevice(uid: "usb", name: "USB Microphone")],
         microphone: PermissionStatus = .granted) {
        let defaults = UserDefaults(suiteName: "TestApp-\(UUID().uuidString)")!
        let folder = URL(fileURLWithPath: "/tmp/kRecordTestApp", isDirectory: true)
        let settings = SettingsStore(defaults: defaults, folderAccess: folderAccess.folderAccess, defaultFolder: folder)
        provider.state.withLock { $0.microphone = microphone }
        let permissions = PermissionsManager(provider: provider, openURL: { _ in })
        let session = RecordingSession(dependencies: RecordingSession.Dependencies(
            settings: { settings.recordingSettings },
            permittedSources: { permissions.permittedSources },
            makeEngine: { [engine] _ in engine },
            makeWriter: { [writer] in writer },
            finalizer: finalizer,
            storage: storage,
            clock: clock.sessionClock,
            refreshInterval: nil))
        let devices = AudioDeviceCatalog(list: { inputDevices }, observeChanges: false)
        let confirmation = confirmation
        self.settings = settings
        self.devices = devices
        self.permissions = permissions
        self.session = session
        model = AppModel(settings: settings, devices: devices, permissions: permissions, session: session,
                         confirmStopAndQuit: { confirmation.ask() })
    }
}
