import AppKit
import SwiftUI

/// The menu bar item's menu (menu-bar spec): start/stop, Settings…, Quit.
struct MenuBarContent: View {
    let model: AppModel

    var body: some View {
        Button(model.session.isRecording ? "Stop Recording" : "Start Recording") {
            Task { await model.toggleRecording() }
        }
        .disabled(!model.canToggleRecording)

        SettingsLink {
            Text("Settings…")
        }
        // A menu item does not bring the Settings window to the front by itself.
        .simultaneousGesture(TapGesture().onEnded { NSApp.activate() })

        Divider()

        Button("Quit") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}

/// The menu bar icon: a grey template symbol when idle, a red one while recording, with the
/// elapsed time next to it when the setting is on.
struct MenuBarLabel: View {
    let model: AppModel

    var body: some View {
        HStack(spacing: 4) {
            Image(nsImage: Self.icon(recording: model.session.isRecording))
            if model.settings.showTimeInMenuBar, model.session.isRecording {
                Text(verbatim: model.session.formattedElapsedTime).monospacedDigit()
            }
        }
        .accessibilityLabel(Text(model.session.isRecording ? "kRecord, recording" : "kRecord"))
    }

    static func icon(recording: Bool) -> NSImage {
        let name = recording ? "record.circle.fill" : "record.circle"
        let base = NSImage(systemSymbolName: name, accessibilityDescription: nil) ?? NSImage()
        guard recording else {
            base.isTemplate = true
            return base
        }
        let configuration = NSImage.SymbolConfiguration(paletteColors: [.systemRed])
        let red = base.withSymbolConfiguration(configuration) ?? base
        red.isTemplate = false
        return red
    }
}
