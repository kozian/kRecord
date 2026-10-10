import AppKit
import SwiftUI

/// The Settings window (settings spec).
struct SettingsView: View {
    let model: AppModel
    @State private var folderError = false

    private var settings: SettingsStore { model.settings }
    private var isLocked: Bool { model.recordingSettingsAreLocked }

    var body: some View {
        Form {
            Section("Destination") {
                if settings.showsFolderUnavailableNotice {
                    Banner(systemImage: "exclamationmark.triangle.fill", tint: .orange,
                           message: Text("The previously selected folder is unavailable. The default folder is used instead."),
                           onDismiss: { settings.dismissFolderUnavailableNotice() })
                }
                LabeledContent("Folder") {
                    Text(verbatim: Self.displayPath(settings.destinationFolder))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                        .help(Text(verbatim: settings.destinationFolder.path))
                }
                HStack {
                    Button("Choose…", action: chooseFolder).disabled(isLocked)
                    Button("Show in Finder") { model.revealRecordingsFolder() }
                }
            }

            Section("Recording") {
                MicrophonePicker(settings: settings, devices: model.devices, isLocked: isLocked)
                Toggle("Save as m4a", isOn: bound(\.saveAsM4A))
                    .disabled(isLocked)
                Toggle("Save microphone and system audio as separate files", isOn: bound(\.separateFiles))
                    .disabled(isLocked)
                Toggle("Echo cancellation", isOn: bound(\.echoCancellation))
                    .disabled(isLocked)
                Text("Echo cancellation removes sound from your speakers that the microphone picks up. Other audio may be quieter while it is on.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Menu Bar") {
                Toggle("Show recording time in menu bar", isOn: bound(\.showTimeInMenuBar))
            }
        }
        .formStyle(.grouped)
        // Everything fits, so the window is sized to the form instead of scrolling it (design D6).
        .scrollDisabled(true)
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
        .alert("The folder can't be used", isPresented: $folderError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("kRecord couldn't get lasting access to that folder. Choose another one.")
        }
    }

    private func bound(_ keyPath: ReferenceWritableKeyPath<SettingsStore, Bool>) -> Binding<Bool> {
        Binding(get: { settings[keyPath: keyPath] }, set: { settings[keyPath: keyPath] = $0 })
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = settings.destinationFolder
        panel.prompt = String(localized: "Choose")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try settings.chooseDestinationFolder(url)
        } catch {
            folderError = true
        }
    }

    /// The path with the real home folder shown as `~`.
    static func displayPath(_ url: URL) -> String {
        let home = HomeDirectory.real.path
        let path = url.path
        guard path == home || path.hasPrefix(home + "/") else { return path }
        return "~" + path.dropFirst(home.count)
    }
}
