import Foundation

enum HomeDirectory {
    /// The user's real home folder. Under the App Sandbox `NSHomeDirectory()` points into the
    /// app container instead (design D10).
    static var real: URL {
        if let entry = getpwuid(getuid()), let path = entry.pointee.pw_dir {
            return URL(fileURLWithPath: String(cString: path), isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
    }

    /// `~/Music/kRecord/`, the default destination folder.
    static var defaultRecordingsFolder: URL {
        real.appending(path: "Music/kRecord", directoryHint: .isDirectory)
    }
}
