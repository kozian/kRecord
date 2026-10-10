import Foundation
import Observation
import Synchronization
import Testing
@testable import kRecord

@MainActor
struct SettingsStoreTests {
    private let defaultFolder = URL(fileURLWithPath: "/Users/test/Music/kRecord", isDirectory: true)
    private let customFolder = URL(fileURLWithPath: "/Volumes/Meetings/Recordings", isDirectory: true)
    private let suiteName = "SettingsStoreTests-\(UUID().uuidString)"
    private let access = FakeFolderAccess()

    private var defaults: UserDefaults { UserDefaults(suiteName: suiteName)! }

    private func makeStore() -> SettingsStore {
        SettingsStore(defaults: defaults, folderAccess: access.folderAccess, defaultFolder: defaultFolder)
    }

    // MARK: Defaults

    @Test func firstLaunchDefaults() {
        let store = makeStore()
        #expect(store.destinationFolder == defaultFolder)
        #expect(store.isUsingDefaultFolder)
        #expect(store.inputDeviceUID == nil)
        #expect(store.inputDeviceName == nil)
        #expect(store.saveAsM4A)
        #expect(!store.separateFiles)
        #expect(!store.echoCancellation)
        #expect(!store.showTimeInMenuBar)
        #expect(store.showsMenuBarItem)
        #expect(!store.hasRequestedPermissions)
        #expect(!store.showsFolderUnavailableNotice)
        #expect(store.recordsMicrophone)
        #expect(store.recordsSystemAudio)
        #expect(store.enabledSources == .all)
    }

    @Test func sourceSwitchesPersistAndReachTheSnapshot() {
        let first = makeStore()
        first.recordsMicrophone = false
        #expect(first.enabledSources == .system)
        #expect(first.recordingSettings.enabledSources == .system)

        let second = makeStore()
        #expect(!second.recordsMicrophone)
        #expect(second.recordsSystemAudio)
        second.recordsSystemAudio = false
        #expect(second.enabledSources.isEmpty)
        #expect(!makeStore().recordsSystemAudio)
    }

    @Test func realDefaultFolderIsMusicKRecord() {
        let store = SettingsStore(defaults: defaults)
        #expect(store.destinationFolder.path.hasSuffix("/Music/kRecord"))
        #expect(!store.destinationFolder.path.contains("/Library/Containers/"))
    }

    // MARK: Persistence

    @Test func settingsPersistAcrossInstances() {
        let first = makeStore()
        first.selectMicrophone(InputDevice(uid: "usb-1", name: "USB Mic"))
        first.saveAsM4A = false
        first.separateFiles = true
        first.echoCancellation = true
        first.showTimeInMenuBar = true
        first.showsMenuBarItem = false
        first.hasRequestedPermissions = true

        let second = makeStore()
        #expect(second.inputDeviceUID == "usb-1")
        #expect(second.inputDeviceName == "USB Mic")
        #expect(!second.saveAsM4A)
        #expect(second.separateFiles)
        #expect(second.echoCancellation)
        #expect(second.showTimeInMenuBar)
        #expect(!second.showsMenuBarItem)
        #expect(second.hasRequestedPermissions)
    }

    @Test func selectingSystemDefaultClearsMicrophone() {
        let store = makeStore()
        store.selectMicrophone(InputDevice(uid: "usb-1", name: "USB Mic"))
        store.selectMicrophone(nil)
        #expect(store.inputDeviceUID == nil)
        #expect(store.inputDeviceName == nil)
        #expect(makeStore().inputDeviceUID == nil)
    }

    @Test func recordingSettingsSnapshot() {
        let store = makeStore()
        store.selectMicrophone(InputDevice(uid: "usb-1", name: "USB Mic"))
        store.saveAsM4A = false
        store.separateFiles = true
        store.echoCancellation = true
        #expect(store.recordingSettings == RecordingSettings(
            destinationFolder: defaultFolder, inputDeviceUID: "usb-1", saveAsM4A: false,
            separateFiles: true, echoCancellation: true))
    }

    @Test func changesAreObservable() {
        let store = makeStore()
        let changed = Mutex(0)
        withObservationTracking { _ = store.saveAsM4A } onChange: { changed.withLock { $0 += 1 } }
        store.saveAsM4A = false
        #expect(changed.withLock { $0 } == 1)

        withObservationTracking { _ = store.inputDeviceUID } onChange: { changed.withLock { $0 += 1 } }
        store.selectMicrophone(InputDevice(uid: "x", name: "X"))
        #expect(changed.withLock { $0 } == 2)
    }

    // MARK: Destination folder

    @Test func customFolderSurvivesRestart() throws {
        access.addFolder(customFolder)
        let first = makeStore()
        try first.chooseDestinationFolder(customFolder)
        #expect(first.destinationFolder == customFolder)
        #expect(!first.isUsingDefaultFolder)

        let second = makeStore()
        #expect(second.destinationFolder == customFolder)
        #expect(!second.showsFolderUnavailableNotice)
        #expect(access.accessed.contains(customFolder))
    }

    @Test func deletedCustomFolderRevertsToDefaultWithNotice() throws {
        // The folder was chosen, then deleted while the app was not running.
        let first = makeStore()
        try first.chooseDestinationFolder(customFolder)

        let second = makeStore()
        #expect(second.destinationFolder == defaultFolder)
        #expect(second.showsFolderUnavailableNotice)
        // The notice is shown once: the stored bookmark was dropped.
        #expect(!makeStore().showsFolderUnavailableNotice)
        #expect(makeStore().destinationFolder == defaultFolder)
    }

    @Test func unresolvableBookmarkRevertsToDefaultWithNotice() throws {
        let first = makeStore()
        try first.chooseDestinationFolder(customFolder)
        access.addFolder(customFolder)
        access.markUnresolvable(FakeFolderAccess.bookmark(for: customFolder))

        let second = makeStore()
        #expect(second.destinationFolder == defaultFolder)
        #expect(second.showsFolderUnavailableNotice)
    }

    @Test func staleBookmarkIsKeptAndRefreshed() throws {
        access.addFolder(customFolder)
        try makeStore().chooseDestinationFolder(customFolder)
        access.markStale(FakeFolderAccess.bookmark(for: customFolder))

        let second = makeStore()
        #expect(second.destinationFolder == customFolder)
        #expect(!second.showsFolderUnavailableNotice)
    }

    @Test func choosingAnotherFolderReleasesThePreviousOne() throws {
        let other = URL(fileURLWithPath: "/Volumes/Other", isDirectory: true)
        let store = makeStore()
        try store.chooseDestinationFolder(customFolder)
        try store.chooseDestinationFolder(other)
        #expect(access.accessed == [other])
        #expect(store.destinationFolder == other)
    }

    @Test func choosingTheDefaultFolderResetsToDefault() throws {
        let store = makeStore()
        try store.chooseDestinationFolder(customFolder)
        try store.chooseDestinationFolder(defaultFolder)
        #expect(store.isUsingDefaultFolder)
        #expect(access.accessed.isEmpty)
        #expect(makeStore().destinationFolder == defaultFolder)
    }

    @Test func resetReleasesAccessAndForgetsBookmark() throws {
        let store = makeStore()
        try store.chooseDestinationFolder(customFolder)
        store.resetDestinationFolder()
        #expect(store.destinationFolder == defaultFolder)
        #expect(access.accessed.isEmpty)
        #expect(makeStore().destinationFolder == defaultFolder)
    }

    @Test func folderThatCannotBeRememberedIsRejected() {
        access.setMakeBookmarkFails(true)
        let store = makeStore()
        #expect(throws: SettingsError.cannotRememberFolder) { try store.chooseDestinationFolder(customFolder) }
        #expect(store.destinationFolder == defaultFolder)
    }

    @Test func noticeCanBeDismissedAndClearsOnNewChoice() throws {
        try makeStore().chooseDestinationFolder(customFolder)
        let store = makeStore()
        #expect(store.showsFolderUnavailableNotice)
        store.dismissFolderUnavailableNotice()
        #expect(!store.showsFolderUnavailableNotice)

        let again = makeStore()
        try again.chooseDestinationFolder(customFolder)
        #expect(!again.showsFolderUnavailableNotice)
    }
}
