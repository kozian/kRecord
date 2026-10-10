import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Closing the main window leaves the app (and a running recording) alive in the menu bar.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// Clicking the Dock icon with no window open shows the main window again.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let quit = AppModel.shared.quit
        guard quit.needsHandling else { return .terminateNow }
        Task {
            sender.reply(toApplicationShouldTerminate: await quit.shouldQuit())
        }
        return .terminateLater
    }
}
