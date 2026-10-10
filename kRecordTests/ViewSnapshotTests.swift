import AppKit
import SwiftUI
import Testing
@testable import kRecord

/// Renders the views in several states into PNG files for visual review, and checks that each one
/// renders to a non-empty image. Files go to `<temporary directory>/kRecordSnapshots/`.
@MainActor
struct ViewSnapshotTests {
    static let outputDirectory = FileManager.default.temporaryDirectory
        .appending(path: "kRecordSnapshots", directoryHint: .isDirectory)

    @discardableResult
    private func render(_ view: some View, name: String, dark: Bool = false) throws -> NSBitmapImageRep {
        let hosting = NSHostingView(rootView: view.environment(\.controlActiveState, .key))
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: hosting.fittingSize),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window.contentView = hosting
        window.setFrameOrigin(NSPoint(x: -20_000, y: -20_000))
        window.layoutIfNeeded()
        hosting.layoutSubtreeIfNeeded()
        let size = hosting.fittingSize
        window.setContentSize(size)
        hosting.layoutSubtreeIfNeeded()

        let bitmap = try #require(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        let png = try #require(bitmap.representation(using: .png, properties: [:]))
        try FileManager.default.createDirectory(at: Self.outputDirectory, withIntermediateDirectories: true)
        try png.write(to: Self.outputDirectory.appending(path: "\(name).png"))
        #expect(bitmap.pixelsWide > 20 && bitmap.pixelsHigh > 10)
        return bitmap
    }

    /// All AppKit controls below `view`, with their enabled state.
    private func controls(in view: NSView) -> [(kind: String, title: String, enabled: Bool)] {
        var found: [(String, String, Bool)] = []
        if let control = view as? NSControl {
            let title = (control as? NSButton)?.title ?? ""
            found.append((String(describing: type(of: control)), title, control.isEnabled))
        }
        for subview in view.subviews { found += controls(in: subview) }
        return found
    }

    private func hostedControls(_ view: some View) -> [(kind: String, title: String, enabled: Bool)] {
        let hosting = NSHostingView(rootView: view)
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: hosting.fittingSize),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        return controls(in: hosting)
    }

    // MARK: Main window

    @Test func mainWindowIdle() throws {
        let app = TestApp()
        try render(MainWindowView(model: app.model), name: "main-idle")
        try render(MainWindowView(model: app.model), name: "main-idle-dark", dark: true)
    }

    /// For checking that the microphone picker spans the same width whatever devices it lists.
    @Test func mainWindowPickerWidths() throws {
        try render(MainWindowView(model: TestApp(devices: [InputDevice(uid: "a", name: "Mic")]).model),
                   name: "main-picker-short")
        try render(MainWindowView(model: TestApp(devices: [InputDevice(uid: "b", name: "A Very Long USB Microphone Name 2000")]).model),
                   name: "main-picker-long")
    }

    @Test func mainWindowRecording() async throws {
        let app = TestApp()
        await app.model.startRecording()
        app.engine.pump(frames: 4_800)
        app.clock.advance(by: 754)
        app.session.refresh()
        try render(MainWindowView(model: app.model), name: "main-recording")
    }

    @Test func mainWindowSaving() async throws {
        let app = TestApp()
        await app.model.startRecording()
        app.finalizer.hold()
        let stopping = Task { await app.session.stop() }
        while !app.finalizer.isWaiting { await Task.yield() }
        try render(MainWindowView(model: app.model), name: "main-saving")
        app.finalizer.release()
        await stopping.value
    }

    @Test func mainWindowMicrophoneDenied() throws {
        let app = TestApp(microphone: .denied)
        try render(MainWindowView(model: app.model), name: "main-microphone-denied")
    }

    @Test func mainWindowNothingPermitted() throws {
        let app = TestApp(microphone: .denied)
        app.provider.state.withLock { $0.systemAudio = .denied }
        app.permissions.refresh()
        try render(MainWindowView(model: app.model), name: "main-nothing-permitted")
    }

    @Test func mainWindowSilentSystemAudioHint() async throws {
        let app = TestApp()
        app.writer.state.withLock { $0.result = WriterResult(streams: [], systemAudioSilent: true) }
        await app.model.startRecording()
        await app.session.stop()
        let withHint = NSHostingView(rootView: MainWindowView(model: app.model)).fittingSize.height

        // "Don't show again" turns the setting off; the hint is then not shown (permissions spec).
        app.settings.warnsAboutSilentSystemAudio = false
        let withoutHint = NSHostingView(rootView: MainWindowView(model: app.model)).fittingSize.height
        #expect(withoutHint < withHint - 20)
    }

    @Test func mainWindowError() async throws {
        let app = TestApp()
        await app.model.startRecording()
        app.storage.report(.diskFull)
        for _ in 0..<20 { await Task.yield() }
        try render(MainWindowView(model: app.model), name: "main-error")
    }

    @Test func mainWindowSourceSwitches() async throws {
        let app = TestApp()
        app.settings.recordsMicrophone = false
        try render(MainWindowView(model: app.model), name: "main-microphone-off")
        app.settings.recordsSystemAudio = false
        try render(MainWindowView(model: app.model), name: "main-both-off")
        #expect(!app.model.canToggleRecording)

        app.settings.recordsSystemAudio = true
        await app.model.startRecording()
        app.engine.pump(frames: 4_800)
        app.session.refresh()
        try render(MainWindowView(model: app.model), name: "main-microphone-off-recording")
        await app.session.stop()
    }

    @Test func mainWindowUnavailableMicrophoneSelected() throws {
        let app = TestApp()
        app.settings.selectMicrophone(InputDevice(uid: "gone", name: "Podcast Mic"))
        try render(MainWindowView(model: app.model), name: "main-mic-unavailable")
    }

    // MARK: Settings

    @Test func settingsDefault() throws {
        let app = TestApp()
        try render(SettingsView(model: app.model), name: "settings-default")
        try render(SettingsView(model: app.model), name: "settings-default-dark", dark: true)
    }

    @Test func settingsWithNoticeAndCustomValues() throws {
        let app = TestApp()
        try app.settings.chooseDestinationFolder(URL(fileURLWithPath: "/Volumes/Meetings/Recordings"))
        app.settings.saveAsM4A = false
        app.settings.separateFiles = true
        let restarted = SettingsStore(defaults: UserDefaults(suiteName: "unused-\(UUID().uuidString)")!,
                                      folderAccess: app.folderAccess.folderAccess,
                                      defaultFolder: URL(fileURLWithPath: "/tmp/kRecordTestApp"))
        _ = restarted
        try render(SettingsView(model: app.model), name: "settings-custom")
    }

    @Test func settingsLockedWhileRecording() async throws {
        let app = TestApp()
        func switches() -> [Bool] {
            hostedControls(SettingsView(model: app.model)).filter { $0.kind == "PlatformSwitch" }.map { $0.enabled }
        }
        // Save as m4a, separate files, echo cancellation, silent audio warning, show in menu bar, menu bar time.
        #expect(switches() == [true, true, true, true, true, true])

        await app.model.startRecording()
        try render(SettingsView(model: app.model), name: "settings-locked")
        // The recording options are locked; the menu bar settings apply immediately (settings spec).
        #expect(switches() == [false, false, false, true, true, true])

        await app.session.stop()
        #expect(switches() == [true, true, true, true, true, true])

        // Without the menu bar item, its time setting cannot be changed.
        app.settings.showsMenuBarItem = false
        #expect(switches() == [true, true, true, true, true, false])
    }

    // MARK: Menu bar

    @Test func menuBarIcon() throws {
        try render(MenuBarLabel(model: TestApp().model).padding(8).background(.bar), name: "menubar-idle")
        try render(MenuBarLabel(model: TestApp().model).padding(8).background(.bar), name: "menubar-idle-dark", dark: true)
    }

    @Test func menuBarRecordingWithTime() async throws {
        let app = TestApp()
        app.settings.showTimeInMenuBar = true
        await app.model.startRecording()
        app.clock.advance(by: 754)
        app.session.refresh()
        try render(MenuBarLabel(model: app.model).padding(8).background(.bar), name: "menubar-recording-time")
        try render(MenuBarLabel(model: app.model).padding(8).background(.bar), name: "menubar-recording-time-dark", dark: true)
        app.settings.showTimeInMenuBar = false
        try render(MenuBarLabel(model: app.model).padding(8).background(.bar), name: "menubar-recording")
    }

    @Test func menuBarIconColors() {
        #expect(MenuBarLabel.icon(recording: false).isTemplate)
        #expect(!MenuBarLabel.icon(recording: true).isTemplate)
    }
}
