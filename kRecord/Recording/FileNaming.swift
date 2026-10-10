import Foundation

/// File names of recordings (recording-output spec, design D5). Pure functions.
enum FileNaming {
    enum Role: Equatable, Sendable {
        /// The mixed recording: no suffix.
        case mixed
        /// Separate-files mode outputs.
        case microphone
        case system

        var suffix: String {
            switch self {
            case .mixed: ""
            case .microphone: " (mic)"
            case .system: " (system)"
            }
        }
    }

    /// Every extension a recording can end up with; a name is taken if it exists with any of them,
    /// because the `.aac` stream later becomes an `.m4a` of the same name.
    static let recordingExtensions = [AACEncoding.streamExtension, AACEncoding.containerExtension]

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

    /// `base`, or `base 2`, `base 3`, … — the first variant whose files for all `roles` and
    /// `extensions` are free. Files of one recording share the number:
    /// `kRecord 2026-10-10 14-30-05 2 (mic).m4a` and `kRecord 2026-10-10 14-30-05 2 (system).m4a`.
    static func availableBase(_ base: String, roles: [Role], extensions: [String] = recordingExtensions,
                              exists: (String) -> Bool) -> String {
        var number = 1
        while true {
            let candidate = number == 1 ? base : "\(base) \(number)"
            let taken = roles.contains { role in
                extensions.contains { exists(fileName(base: candidate, role: role, fileExtension: $0)) }
            }
            if !taken { return candidate }
            number += 1
        }
    }

    /// `availableBase` checking the file system in `directory`.
    static func availableBase(in directory: URL, base: String, roles: [Role]) -> String {
        availableBase(base, roles: roles) { name in
            FileManager.default.fileExists(atPath: directory.appending(path: name).path)
        }
    }
}
