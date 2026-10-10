import SwiftUI

@main
struct KRecordApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    private let model = AppModel.shared
    /// Mirrors `SettingsStore.showsMenuBarItem`: the scene body does not track the observable
    /// store, but `AppStorage` updates scenes when the stored value changes (design D1).
    @AppStorage(SettingsStore.Key.showsMenuBarItem) private var showsMenuBarItem = true

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
        // No title bar, window buttons kept; the window is dragged by its background (refine-main-window D3).
        .windowStyle(.hiddenTitleBar)
        .windowBackgroundDragBehavior(.enabled)
        .windowResizability(.contentSize)

        // Shown while the "Show in menu bar" setting is on (design D1); macOS also clears it when
        // the user removes the item by ⌘-dragging it out of the menu bar.
        MenuBarExtra(isInserted: $showsMenuBarItem) {
            MenuBarContent(model: model)
        } label: {
            MenuBarLabel(model: model)
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView(model: model)
        }
        .windowResizability(.contentSize)
    }
}
