import AppKit
import Foundation
import Observation

/// The objects every scene shares: settings, devices, permissions, and the recording session.
@MainActor
@Observable
final class AppModel {
    static let shared = AppModel.live()

    let settings: SettingsStore
    let devices: AudioDeviceCatalog
    let permissions: PermissionsManager
    let session: RecordingSession
    let quit: QuitCoordinator

    @ObservationIgnored private var activationObserver: NSObjectProtocol?

    init(settings: SettingsStore, devices: AudioDeviceCatalog, permissions: PermissionsManager,
         session: RecordingSession, confirmStopAndQuit: @escaping @MainActor () async -> Bool) {
        self.settings = settings
        self.devices = devices
        self.permissions = permissions
        self.session = session
        quit = QuitCoordinator(session: session, confirmStopAndQuit: confirmStopAndQuit)
    }

    static func live() -> AppModel {
        let settings = SettingsStore()
        let permissions = PermissionsManager()
        let session = RecordingSession(dependencies: RecordingSession.Dependencies(
            settings: { settings.recordingSettings },
            permittedSources: { permissions.permittedSources },
            makeEngine: { $0 ? VoiceProcessingCaptureEngine() as any CaptureEngine : AggregateCaptureEngine() },
            makeWriter: { AACRecordingWriter() },
            finalizer: AudioFinalizer(),
            storage: FileSystemStorageGuard()))
        return AppModel(settings: settings, devices: AudioDeviceCatalog(), permissions: permissions, session: session,
                        confirmStopAndQuit: QuitCoordinator.showConfirmationAlert)
    }

    // MARK: Launch

    /// Whether the process is hosting unit tests, which must not trigger permission prompts.
    nonisolated static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    /// Refreshes permissions when the app becomes active and, on the first launch, asks for them.
    func launch() {
        guard !Self.isRunningTests else { return }
        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [permissions] _ in
            MainActor.assumeIsolated { permissions.refresh() }
        }
        permissions.refresh()
        Task { await requestPermissionsOnFirstLaunch() }
    }

    /// Shows the microphone and system audio prompts once (permissions spec), without onboarding.
    func requestPermissionsOnFirstLaunch() async {
        guard !settings.hasRequestedPermissions else { return }
        await permissions.requestAll()
        settings.hasRequestedPermissions = true
    }

    // MARK: Recording

    /// The record/stop control is usable: stopping always is; starting needs a permitted source.
    var canToggleRecording: Bool {
        switch session.state {
        case .idle: permissions.canRecord
        case .recording: true
        case .starting, .finishing: false
        }
    }

    func toggleRecording() async {
        if session.isRecording {
            await session.stop()
        } else {
            await startRecording()
        }
    }

    func startRecording() async {
        guard session.state == .idle else { return }
        // Asks only if the microphone was never decided, e.g. if the first-launch prompt was skipped.
        await permissions.requestMicrophoneIfNeeded()
        await session.start()
    }

    /// Settings that must not change while a recording runs or is being saved.
    var recordingSettingsAreLocked: Bool { session.state != .idle }
}
