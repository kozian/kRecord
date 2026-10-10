import AppKit

/// Opens the Settings window in front of other apps (menu-bar spec, "Settings from menu").
@MainActor
enum SettingsWindow {
    /// Calls `open` (the SwiftUI `openSettings` action), then activates the app and orders the Settings
    /// window front. Deferred to the next run loop pass: an action of a menu bar menu runs while the
    /// menu is still closing, and an activation requested then is lost; the window may also not exist yet.
    static func show(using open: () -> Void) {
        open()
        DispatchQueue.main.async {
            // Not the cooperative `activate()`: macOS declines it while another app is active, which
            // leaves the window behind that app (verified with the DEBUG remote control and Finder active).
            NSApp.activate(ignoringOtherApps: true)
            guard let window else { return }
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
        }
    }

    /// The SwiftUI Settings window, once it has been opened.
    static var window: NSWindow? {
        NSApp.windows.first { $0.identifier?.rawValue == "com_apple_SwiftUI_Settings_window" }
    }
}
