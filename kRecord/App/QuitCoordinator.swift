import AppKit
import Foundation

/// Decides whether the app may quit (recording-session spec: confirm quit while recording).
@MainActor
struct QuitCoordinator {
    let session: RecordingSession
    /// Asks whether to stop the recording and quit; `false` keeps the app and the recording running.
    let confirmStopAndQuit: @MainActor () async -> Bool

    /// Quitting needs more than answering `terminateNow` unless the session is idle.
    var needsHandling: Bool { session.state != .idle }

    /// Returns `true` when the app may quit. A recording is stopped and saved first, after the user
    /// confirmed; a recording that is being saved is waited for.
    func shouldQuit() async -> Bool {
        while true {
            switch session.state {
            case .idle:
                return true
            case .recording:
                guard await confirmStopAndQuit() else { return false }
                await session.stop()
            case .starting, .finishing:
                await session.waitUntilIdle()
            }
        }
    }

    /// The standard confirmation alert.
    static func showConfirmationAlert() async -> Bool {
        let alert = NSAlert()
        alert.messageText = String(localized: "Stop recording and quit?")
        alert.informativeText = String(localized: "The recording will be saved before kRecord quits.")
        alert.addButton(withTitle: String(localized: "Stop Recording and Quit"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        NSApp.activate()
        return alert.runModal() == .alertFirstButtonReturn
    }
}
