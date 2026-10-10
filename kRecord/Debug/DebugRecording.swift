#if DEBUG
import AppKit
import AVFoundation
import Foundation

/// Headless end-to-end recording for manual verification over SSH (DEBUG builds only).
///
///     open kRecord.app --args -KRDebugRecord 60 [-KRDebugSources all|mic|system]
///         [-KRDebugFormat aac|alac|wav] [-KRDebugSeparate YES] [-KRDebugEchoCancellation YES]
///
/// Records to `~/Music/kRecord/` through the production capture, writer, and finalizer, logs to
/// `~/Music/kRecord/debug-recording.log`, and quits.
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
        let format = defaults.string(forKey: "KRDebugFormat").flatMap(OutputFormat.init(rawValue:)) ?? .aac
        let separate = defaults.bool(forKey: "KRDebugSeparate")
        let echoCancellation = defaults.bool(forKey: "KRDebugEchoCancellation")

        Task.detached {
            let folder = HomeDirectory.defaultRecordingsFolder
            let log = DebugLog(url: folder.appending(path: "debug-recording.log"))
            do {
                try FileSystemStorageGuard().prepare(folder)
                log.write("start: seconds=\(seconds) sources=\(sources.rawValue) format=\(format) separate=\(separate) echoCancellation=\(echoCancellation)")
                if sources.contains(.microphone) {
                    log.write("microphone permission: \(await AVCaptureDevice.requestAccess(for: .audio))")
                }

                let engine: any CaptureEngine = echoCancellation
                    ? VoiceProcessingCaptureEngine() : AggregateCaptureEngine()
                let events = engine.events()
                Task { for await event in events { log.write("event: \(event)") } }
                let started = Date()
                let streams = try await engine.start(CaptureConfiguration(inputDeviceUID: nil, sources: sources))
                log.write("capture started: rate=\(streams.sampleRate) mic=\(streams.microphone != nil) system=\(streams.system != nil)")

                let base = FileNaming.baseName(for: started)
                let files = IntermediateFiles(
                    microphone: streams.microphone.map { _ in
                        folder.appending(path: FileNaming.fileName(base: base, role: .recordingMicrophone, fileExtension: "caf"))
                    },
                    system: streams.system.map { _ in
                        folder.appending(path: FileNaming.fileName(base: base, role: .recordingSystem, fileExtension: "caf"))
                    })
                let writer = CAFRecordingWriter()
                try await writer.start(streams: streams, files: files)

                for second in 1...seconds {
                    try await Task.sleep(for: .seconds(1))
                    if second % 5 == 0 || second == seconds {
                        let levels = streams.levels.take()
                        log.write(String(format: "t=%ds mic peak %.3f system peak %.3f", second,
                                         levels.microphone.peak, levels.system.peak))
                    }
                }

                await engine.stop()
                let frames = try await writer.finish()
                log.write("captured frames: mic=\(frames.microphone) system=\(frames.system) " +
                          "(\(Double(max(frames.microphone, frames.system)) / streams.sampleRate) s)")
                let result = try await AudioFinalizer().finalize(FinalizationRequest(
                    intermediates: files, baseName: base, destination: folder, format: format, separateFiles: separate))
                log.write("saved: \(result.outputs.map(\.lastPathComponent)) systemAudioSilent=\(result.systemAudioSilent)")
            } catch {
                log.write("ERROR: \(error)")
            }
            await MainActor.run { NSApplication.shared.terminate(nil) }
        }
    }
}

private final class DebugLog: Sendable {
    let url: URL

    init(url: URL) {
        self.url = url
    }

    func write(_ message: String) {
        NSLog("[debug-recording] %@", message)
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
