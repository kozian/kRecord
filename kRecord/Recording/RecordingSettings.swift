import Foundation

/// The settings a recording uses, captured when it starts (settings spec: changes apply to the
/// next recording). `SettingsStore` produces this snapshot.
struct RecordingSettings: Equatable, Sendable {
    var destinationFolder: URL
    /// Core Audio UID of the selected microphone, or `nil` for "System Default".
    var inputDeviceUID: String?
    /// Repackage the recorded `.aac` stream into `.m4a` when the recording stops.
    var saveAsM4A: Bool
    var separateFiles: Bool
    var echoCancellation: Bool

    static let defaults = RecordingSettings(
        destinationFolder: HomeDirectory.defaultRecordingsFolder,
        inputDeviceUID: nil,
        saveAsM4A: true,
        separateFiles: false,
        echoCancellation: false)
}
