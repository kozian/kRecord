import Foundation
import Observation

enum SettingsError: Error, Equatable, Sendable {
    /// The chosen folder cannot be remembered across launches (no security-scoped bookmark).
    case cannotRememberFolder
}

/// The user's preferences (settings spec), persisted in `UserDefaults`.
///
/// Values are read from and written straight to `UserDefaults`; the observation hooks are called by
/// hand so SwiftUI sees changes. The destination folder is resolved at launch from a
/// security-scoped bookmark (design D10) and reverts to the default when that fails.
@MainActor
@Observable
final class SettingsStore {
    enum Key {
        static let destinationBookmark = "destinationFolderBookmark"
        static let inputDeviceUID = "inputDeviceUID"
        static let inputDeviceName = "inputDeviceName"
        static let saveAsM4A = "saveAsM4A"
        static let separateFiles = "separateFiles"
        static let echoCancellation = "echoCancellation"
        static let showTimeInMenuBar = "showTimeInMenuBar"
        static let requestedPermissions = "requestedPermissions"
    }

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let folderAccess: FolderAccess
    @ObservationIgnored private let defaultFolder: URL
    /// The custom folder with started security-scoped access, if any.
    @ObservationIgnored private var accessedFolder: URL?

    /// Where recordings are saved.
    private(set) var destinationFolder: URL
    /// The previously chosen folder could not be restored at launch and the default is used instead.
    private(set) var showsFolderUnavailableNotice = false

    var isUsingDefaultFolder: Bool { accessedFolder == nil }

    init(defaults: UserDefaults = .standard, folderAccess: FolderAccess = .system,
         defaultFolder: URL = HomeDirectory.defaultRecordingsFolder) {
        self.defaults = defaults
        self.folderAccess = folderAccess
        self.defaultFolder = defaultFolder
        destinationFolder = defaultFolder

        switch FolderRestoration.restore(bookmark: defaults.data(forKey: Key.destinationBookmark), access: folderAccess) {
        case .noCustomFolder:
            break
        case let .restored(url, refreshedBookmark):
            destinationFolder = url
            accessedFolder = url
            if let refreshedBookmark { defaults.set(refreshedBookmark, forKey: Key.destinationBookmark) }
        case .unavailable:
            defaults.removeObject(forKey: Key.destinationBookmark)
            showsFolderUnavailableNotice = true
        }
    }

    // MARK: Destination folder

    /// Uses `url`, a folder the user picked in the open panel, for all later recordings.
    func chooseDestinationFolder(_ url: URL) throws(SettingsError) {
        if url.standardizedFileURL == defaultFolder.standardizedFileURL {
            resetDestinationFolder()
            return
        }
        // Make the bookmark while the panel's implicit access is active.
        guard let bookmark = try? folderAccess.makeBookmark(url) else { throw .cannotRememberFolder }
        releaseFolderAccess()
        if folderAccess.startAccessing(url) { accessedFolder = url }
        defaults.set(bookmark, forKey: Key.destinationBookmark)
        destinationFolder = url
        showsFolderUnavailableNotice = false
    }

    func resetDestinationFolder() {
        releaseFolderAccess()
        defaults.removeObject(forKey: Key.destinationBookmark)
        destinationFolder = defaultFolder
        showsFolderUnavailableNotice = false
    }

    func dismissFolderUnavailableNotice() {
        showsFolderUnavailableNotice = false
    }

    private func releaseFolderAccess() {
        if let accessedFolder { folderAccess.stopAccessing(accessedFolder) }
        accessedFolder = nil
    }

    // MARK: Microphone

    /// Core Audio UID of the selected microphone, or `nil` for "System Default".
    var inputDeviceUID: String? {
        access(keyPath: \.inputDeviceUID)
        return defaults.string(forKey: Key.inputDeviceUID)
    }

    /// Name of the selected microphone, remembered so it can be shown while it is unplugged.
    var inputDeviceName: String? {
        access(keyPath: \.inputDeviceName)
        return defaults.string(forKey: Key.inputDeviceName)
    }

    func selectMicrophone(_ device: InputDevice?) {
        withMutation(keyPath: \.inputDeviceUID) {
            withMutation(keyPath: \.inputDeviceName) {
                if let device {
                    defaults.set(device.uid, forKey: Key.inputDeviceUID)
                    defaults.set(device.name, forKey: Key.inputDeviceName)
                } else {
                    defaults.removeObject(forKey: Key.inputDeviceUID)
                    defaults.removeObject(forKey: Key.inputDeviceName)
                }
            }
        }
    }

    // MARK: Toggles

    /// Repackage the recording into `.m4a` when it stops; otherwise keep the `.aac` stream. Default on.
    var saveAsM4A: Bool {
        get {
            access(keyPath: \.saveAsM4A)
            return defaults.object(forKey: Key.saveAsM4A) as? Bool ?? true
        }
        set { withMutation(keyPath: \.saveAsM4A) { defaults.set(newValue, forKey: Key.saveAsM4A) } }
    }

    var separateFiles: Bool {
        get {
            access(keyPath: \.separateFiles)
            return defaults.bool(forKey: Key.separateFiles)
        }
        set { withMutation(keyPath: \.separateFiles) { defaults.set(newValue, forKey: Key.separateFiles) } }
    }

    var echoCancellation: Bool {
        get {
            access(keyPath: \.echoCancellation)
            return defaults.bool(forKey: Key.echoCancellation)
        }
        set { withMutation(keyPath: \.echoCancellation) { defaults.set(newValue, forKey: Key.echoCancellation) } }
    }

    var showTimeInMenuBar: Bool {
        get {
            access(keyPath: \.showTimeInMenuBar)
            return defaults.bool(forKey: Key.showTimeInMenuBar)
        }
        set { withMutation(keyPath: \.showTimeInMenuBar) { defaults.set(newValue, forKey: Key.showTimeInMenuBar) } }
    }

    // MARK: First launch

    /// Whether the permission prompts were already requested (permissions spec: first launch only).
    var hasRequestedPermissions: Bool {
        get {
            access(keyPath: \.hasRequestedPermissions)
            return defaults.bool(forKey: Key.requestedPermissions)
        }
        set { withMutation(keyPath: \.hasRequestedPermissions) { defaults.set(newValue, forKey: Key.requestedPermissions) } }
    }

    // MARK: Recording

    /// What the next recording uses (settings spec: changes apply to the next recording).
    var recordingSettings: RecordingSettings {
        RecordingSettings(destinationFolder: destinationFolder, inputDeviceUID: inputDeviceUID,
                          saveAsM4A: saveAsM4A, separateFiles: separateFiles, echoCancellation: echoCancellation)
    }
}
