import AppKit
import AVFoundation
import Foundation
import Observation

enum PermissionStatus: Equatable, Sendable {
    case granted
    case denied
    case notDetermined
    /// macOS does not say whether the permission is granted (system audio recording).
    case unknown
}

/// The privacy permission system calls, behind a protocol so the status mapping is testable.
protocol AuthorizationProvider: Sendable {
    func microphoneStatus() -> PermissionStatus
    func requestMicrophoneAccess() async -> Bool
    /// No public API reports this, so production returns `.unknown` (design D9).
    func systemAudioStatus() -> PermissionStatus
    /// Makes macOS show the system audio recording prompt if it has not been answered yet.
    func triggerSystemAudioPrompt() async
}

struct SystemAuthorizationProvider: AuthorizationProvider {
    func microphoneStatus() -> PermissionStatus {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: .granted
        case .denied, .restricted: .denied
        case .notDetermined: .notDetermined
        @unknown default: .unknown
        }
    }

    func requestMicrophoneAccess() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .audio)
    }

    func systemAudioStatus() -> PermissionStatus { .unknown }

    /// The prompt appears when a tap starts delivering audio, so run a short system-only capture.
    func triggerSystemAudioPrompt() async {
        let engine = AggregateCaptureEngine()
        if (try? await engine.start(CaptureConfiguration(inputDeviceUID: nil, sources: .system))) != nil {
            try? await Task.sleep(for: .milliseconds(300))
        }
        await engine.stop()
    }
}

/// The Privacy & Security panes that can be opened from the app.
enum PrivacyPane: Sendable {
    case microphone
    case systemAudio

    var url: URL {
        switch self {
        case .microphone: URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!
        case .systemAudio: URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AudioCapture")!
        }
    }
}

/// Tracks the microphone and system audio permissions (permissions spec).
@MainActor
@Observable
final class PermissionsManager {
    private(set) var microphone: PermissionStatus
    private(set) var systemAudio: PermissionStatus

    @ObservationIgnored private let provider: AuthorizationProvider
    @ObservationIgnored private let openURL: @MainActor (URL) -> Void

    init(provider: AuthorizationProvider = SystemAuthorizationProvider(),
         openURL: @escaping @MainActor (URL) -> Void = { NSWorkspace.shared.open($0) }) {
        self.provider = provider
        self.openURL = openURL
        microphone = provider.microphoneStatus()
        systemAudio = provider.systemAudioStatus()
    }

    /// Re-reads the statuses; call at launch and when the app becomes active so changes made in
    /// System Settings show up without a restart.
    func refresh() {
        microphone = provider.microphoneStatus()
        systemAudio = provider.systemAudioStatus()
    }

    /// The sources a recording may capture. A source is blocked only when macOS reports it denied;
    /// an unknown system audio status counts as permitted.
    var permittedSources: CaptureSources {
        var sources: CaptureSources = []
        if microphone == .granted { sources.insert(.microphone) }
        if systemAudio != .denied { sources.insert(.system) }
        return sources
    }

    var canRecord: Bool { !permittedSources.isEmpty }

    /// The microphone is denied: a warning is shown and recordings contain system audio only.
    var microphoneIsBlocked: Bool { microphone == .denied }

    /// Asks for the microphone if it was never decided. Returns whether it is granted afterwards.
    @discardableResult
    func requestMicrophoneIfNeeded() async -> Bool {
        if microphone == .notDetermined { _ = await provider.requestMicrophoneAccess() }
        refresh()
        return microphone == .granted
    }

    /// First-launch prompts: microphone, then system audio recording.
    func requestAll() async {
        await requestMicrophoneIfNeeded()
        await provider.triggerSystemAudioPrompt()
        refresh()
    }

    func openSettings(_ pane: PrivacyPane) {
        openURL(pane.url)
    }
}
