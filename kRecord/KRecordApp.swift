import SwiftUI

@main
struct KRecordApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    private let model = AppModel.shared

    init() {
        #if DEBUG
        DebugRecording.runIfRequested()
        #endif
        AppModel.shared.launch()
        #if DEBUG
        DebugControl.runIfRequested()
        #endif
    }

    var body: some Scene {
        Window("kRecord", id: "main") {
            MainWindowView(model: model)
        }
        .windowResizability(.contentSize)

        MenuBarExtra {
            MenuBarContent(model: model)
        } label: {
            MenuBarLabel(model: model)
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView(model: model)
        }
    }
}
