#if DEBUG
import AppKit
import AVFoundation
import Foundation

/// Headless end-to-end recording for manual verification over SSH (DEBUG builds only).
///
///     open kRecord.app --args -KRDebugRecord 60 [-KRDebugSources all|mic|system]
///         [-KRDebugSaveAsM4A NO] [-KRDebugSeparate YES] [-KRDebugEchoCancellation YES]
///
/// Records to `~/Music/kRecord/` through `RecordingSession` with the production capture, writer,
/// and finalizer, logs to `~/Music/kRecord/debug-recording.log`, and quits.
enum DebugRecording {
    static func runIfRequested() {
        let defaults = UserDefaults.standard
        let seconds = defaults.integer(forKey: "KRDebugRecord")
        guard seconds > 0 else { return }
        let sources: CaptureSources = switch defaults.string(forKey: "KRDebugSources") {
        case "mic": .microphone
        case "system": .system
        default: .all
        }
        var settings = RecordingSettings.defaults
        settings.saveAsM4A = defaults.object(forKey: "KRDebugSaveAsM4A") == nil || defaults.bool(forKey: "KRDebugSaveAsM4A")
        settings.separateFiles = defaults.bool(forKey: "KRDebugSeparate")
        settings.echoCancellation = defaults.bool(forKey: "KRDebugEchoCancellation")
        let snapshot = settings

        Task { @MainActor in
            let log = DebugLog(url: snapshot.destinationFolder.appending(path: "debug-recording.log"))
            log.write("start: seconds=\(seconds) sources=\(sources.rawValue) saveAsM4A=\(snapshot.saveAsM4A) " +
                      "separate=\(snapshot.separateFiles) echoCancellation=\(snapshot.echoCancellation)")
            if sources.contains(.microphone) {
                log.write("microphone permission: \(await AVCaptureDevice.requestAccess(for: .audio))")
            }
            let session = RecordingSession(dependencies: RecordingSession.Dependencies(
                settings: { snapshot },
                permittedSources: { sources },
                makeEngine: { $0 ? VoiceProcessingCaptureEngine() as any CaptureEngine : AggregateCaptureEngine() },
                makeWriter: { AACRecordingWriter() },
                finalizer: AudioFinalizer(),
                storage: FileSystemStorageGuard()))

            await session.start()
            log.write("state after start: \(session.state) error: \(String(describing: session.lastError))")
            if session.state == .recording {
                var micPeak: Float = 0
                var systemPeak: Float = 0
                for tick in 1...(seconds * 10) {
                    try? await Task.sleep(for: .milliseconds(100))
                    micPeak = max(micPeak, session.levels.microphone.peak)
                    systemPeak = max(systemPeak, session.levels.system.peak)
                    if tick % 50 == 0 || tick == seconds * 10 {
                        log.write(String(format: "t=%@ mic peak %.3f system peak %.3f",
                                         session.formattedElapsedTime, micPeak, systemPeak))
                        micPeak = 0
                        systemPeak = 0
                    }
                }
                let stopping = Date()
                await session.stop()
                let outputs = session.lastResult?.outputs.map(\.lastPathComponent) ?? []
                log.write(String(format: "saved in %.2f s: ", Date().timeIntervalSince(stopping)) +
                          "\(outputs) systemAudioSilent=\(String(describing: session.lastResult?.systemAudioSilent)) " +
                          "error=\(String(describing: session.lastError))")
            }
            NSApplication.shared.terminate(nil)
        }
    }
}

private final class DebugLog: Sendable {
    let url: URL

    init(url: URL) {
        self.url = url
    }

    func write(_ message: String) {
        let data = Data("\(Date().formatted(.iso8601)) \(message)\n".utf8)
        if let handle = try? FileHandle(forWritingTo: url) {
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
            try? handle.close()
        } else {
            try? data.write(to: url)
        }
    }
}
#endif
