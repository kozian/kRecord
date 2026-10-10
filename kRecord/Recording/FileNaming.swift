import Foundation

/// File names of recordings (recording-output spec, design D5). Pure functions.
enum FileNaming {
    enum Role: Equatable, Sendable {
        /// The mixed recording: no suffix.
        case mixed
        /// Separate-files mode outputs.
        case microphone
        case system
        /// Crash-safe intermediates while recording.
        case recordingMicrophone
        case recordingSystem

        var suffix: String {
            switch self {
            case .mixed: ""
            case .microphone: " (mic)"
            case .system: " (system)"
            case .recordingMicrophone: " (recording mic)"
            case .recordingSystem: " (recording system)"
            }
        }
    }

    static let intermediateExtension = "caf"

    /// `kRecord YYYY-MM-DD HH-mm-ss` for the local start time of the recording.
    static func baseName(for date: Date, timeZone: TimeZone = .current) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        return String(format: "kRecord %04d-%02d-%02d %02d-%02d-%02d",
                      c.year ?? 0, c.month ?? 0, c.day ?? 0, c.hour ?? 0, c.minute ?? 0, c.second ?? 0)
    }

    static func fileName(base: String, role: Role, fileExtension: String) -> String {
        "\(base)\(role.suffix).\(fileExtension)"
    }

    /// Names for `roles` that do not collide with existing files. All names share one numeric
    /// suffix (` 2`, ` 3`, …) so files of the same recording stay recognizable as a set:
    /// `kRecord 2026-10-10 14-30-05 2 (mic).m4a` and `kRecord 2026-10-10 14-30-05 2 (system).m4a`.
    static func uniqueFileNames(base: String, roles: [Role], fileExtension: String,
                                exists: (String) -> Bool) -> [String] {
        var number = 1
        while true {
            let numbered = number == 1 ? base : "\(base) \(number)"
            let names = roles.map { fileName(base: numbered, role: $0, fileExtension: fileExtension) }
            if !names.contains(where: exists) { return names }
            number += 1
        }
    }

    /// `uniqueFileNames` checking the file system in `directory`.
    static func uniqueURLs(in directory: URL, base: String, roles: [Role], fileExtension: String) -> [URL] {
        uniqueFileNames(base: base, roles: roles, fileExtension: fileExtension) { name in
            FileManager.default.fileExists(atPath: directory.appending(path: name).path)
        }
        .map { directory.appending(path: $0) }
    }
}
