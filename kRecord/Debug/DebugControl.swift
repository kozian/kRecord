#if DEBUG
import AppKit
import Foundation

/// Remote control of a running DEBUG build for verification over SSH.
///
///     open -n kRecord.app --args -KRDebugControl YES
///     echo <command> > ~/Music/kRecord/.debug-command
///
/// Commands: `closeMainWindow`, `openSettings`, `startRecording`, `stopRecording`, `logState`, `quit`,
/// `confirmAlert`, `cancelAlert` (press the default or the Escape button of the modal alert).
/// Output goes to `~/Music/kRecord/debug-control.log`.
@MainActor
enum DebugControl {
    private static let commandFile = HomeDirectory.defaultRecordingsFolder.appending(path: ".debug-command")

    static func runIfRequested() {
        guard UserDefaults.standard.bool(forKey: "KRDebugControl") else { return }
        // Polled by a timer that also runs in the modal panel mode, so it keeps firing while an alert
        // is up; dispatch-queue notifications do not.
        let timer = Timer(timeInterval: 0.25, repeats: true) { _ in
            MainActor.assumeIsolated { poll() }
        }
        for mode: RunLoop.Mode in [.common, .modalPanel, .eventTracking] { RunLoop.main.add(timer, forMode: mode) }
        log("ready")
    }

    private static func poll() {
        guard let data = try? Data(contentsOf: commandFile), let text = String(data: data, encoding: .utf8) else { return }
        try? FileManager.default.removeItem(at: commandFile)
        for command in text.split(whereSeparator: \.isNewline) { handle(String(command)) }
    }

    private static func handle(_ command: String) {
        let model = AppModel.shared
        switch command {
        case "closeMainWindow":
            mainWindow?.performClose(nil)
            log("closed main window")
        case "openSettings":
            // The app menu's "Settings…" item, as a click on it would do.
            if let menu = NSApp.mainMenu?.items.first?.submenu,
               let index = menu.items.firstIndex(where: { $0.title.hasPrefix("Settings") }) {
                menu.performActionForItem(at: index)
                log("performed menu item '\(menu.items[index].title)'")
            } else {
                log("no Settings menu item")
            }
        case "startRecording":
            Task {
                await model.startRecording()
                log("started: state=\(model.session.state) error=\(String(describing: model.session.lastError))")
            }
        case "stopRecording":
            Task {
                await model.session.stop()
                log("stopped: state=\(model.session.state) outputs=\(model.session.lastResult?.outputs.map(\.lastPathComponent) ?? [])")
            }
        case "quit":
            log("quit requested")
            // From its own timer: `terminate:` spins a nested run loop, and the polling timer must
            // stay free to fire inside it (to answer the alert).
            NSApp.perform(#selector(NSApplication.terminate(_:)), with: nil, afterDelay: 0)
        case "confirmAlert":
            log("confirm alert pressed: \(pressAlertButton(keyEquivalent: "\r"))")
        case "cancelAlert":
            log("cancel alert pressed: \(pressAlertButton(keyEquivalent: "\u{1b}"))")
        default:
            break
        }
        if command == "logState" { logState() }
    }

    private static func pressAlertButton(keyEquivalent: String) -> Bool {
        guard let window = NSApp.modalWindow, let content = window.contentView else { return false }
        func find(in view: NSView) -> NSButton? {
            if let button = view as? NSButton, button.keyEquivalent == keyEquivalent { return button }
            return view.subviews.lazy.compactMap(find(in:)).first
        }
        guard let button = find(in: content) else { return false }
        button.performClick(nil)
        return true
    }

    private static var mainWindow: NSWindow? {
        NSApp.windows.first { $0.title == "kRecord" }
    }

    private static func logState() {
        let model = AppModel.shared
        log("state=\(model.session.state) elapsed=\(model.session.formattedElapsedTime) " +
            "activationPolicy=\(NSApp.activationPolicy().rawValue)")
        if let modal = NSApp.modalWindow {
            var texts: [String] = []
            func collect(_ view: NSView) {
                if let field = view as? NSTextField, !field.stringValue.isEmpty { texts.append(field.stringValue) }
                if let button = view as? NSButton, !button.title.isEmpty { texts.append("[\(button.title)]") }
                view.subviews.forEach(collect)
            }
            if let content = modal.contentView { collect(content) }
            log("MODAL ALERT: \(texts)")
        }
        for window in NSApp.windows {
            log("window \(type(of: window)) title='\(window.title)' visible=\(window.isVisible) " +
                "size=\(Int(window.frame.width))x\(Int(window.frame.height)) origin=\(Int(window.frame.minX)),\(Int(window.frame.minY)) level=\(window.level.rawValue)")
        }
        for item in NSApp.mainMenu?.items ?? [] {
            let titles = item.submenu?.items.map { $0.isSeparatorItem ? "-" : $0.title } ?? []
            log("menu '\(item.title)': \(titles)")
        }
    }

    private static func log(_ message: String) {
        let url = HomeDirectory.defaultRecordingsFolder.appending(path: "debug-control.log")
        let data = Data("\(Date().formatted(.iso8601)) \(message)\n".utf8)
        if let handle = try? FileHandle(forWritingTo: url) {
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
            try? handle.close()
        } else {
            try? data.write(to: url)
        }
    }
}
#endif
