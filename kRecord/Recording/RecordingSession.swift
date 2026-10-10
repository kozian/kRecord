import Foundation
import Observation

/// A user-facing reason a recording could not start or stopped early (recording-session spec).
enum RecordingError: Error, Equatable, Sendable {
    case noPermission
    case folderNotWritable
    case folderUnavailable
    case diskFull
    case captureFailed
    case writeFailed
    /// Recording finished but the final file could not be produced; the intermediates are kept.
    case saveFailed

    var message: String {
        switch self {
        case .noPermission:
            String(localized: "kRecord has no permission to record the microphone or system audio.")
        case .folderNotWritable:
            String(localized: "The destination folder can't be written to. Choose another folder in Settings.")
        case .folderUnavailable:
            String(localized: "Recording stopped because the destination folder is no longer available.")
        case .diskFull:
            String(localized: "Recording stopped because the disk is almost full.")
        case .captureFailed:
            String(localized: "Recording stopped because an audio device stopped working.")
        case .writeFailed:
            String(localized: "Recording stopped because the audio couldn't be written to disk.")
        case .saveFailed:
            String(localized: "The recording couldn't be saved. The unprocessed audio was kept in the destination folder.")
        }
    }

    init(_ error: StorageError) {
        switch error {
        case .cannotCreateFolder, .folderNotWritable: self = .folderNotWritable
        case .folderUnavailable: self = .folderUnavailable
        case .diskFull: self = .diskFull
        }
    }
}

/// Time source of a session; injected so tests control elapsed time.
struct SessionClock: Sendable {
    /// Wall-clock time, used for file names.
    var date: @Sendable () -> Date
    /// Monotonic seconds, used for the elapsed time.
    var uptime: @Sendable () -> TimeInterval

    static let system = SessionClock(date: { Date() }, uptime: { ProcessInfo.processInfo.systemUptime })
}

/// The single recording lifecycle shared by every UI surface (design D9):
/// `idle → starting → recording → finishing → idle`, with errors reported in `lastError`.
@MainActor
@Observable
final class RecordingSession {
    enum State: Equatable, Sendable {
        case idle
        case starting
        case recording
        case finishing
    }

    struct Dependencies {
        var settings: @MainActor () -> RecordingSettings
        /// Sources the app is currently allowed to record.
        var permittedSources: @MainActor () -> CaptureSources
        /// Creates the capture engine; the argument is the echo-cancellation setting.
        var makeEngine: (Bool) -> any CaptureEngine
        var makeWriter: () -> any RecordingWriter
        var finalizer: any Finalizer
        var storage: any StorageGuard
        var clock: SessionClock = .system
        /// How often elapsed time and levels refresh; `nil` disables automatic refresh (tests).
        var refreshInterval: Duration? = .milliseconds(50)
    }

    private(set) var state: State = .idle
    /// Whole seconds since capture started; 0 when idle.
    private(set) var elapsedSeconds = 0
    private(set) var levels: LevelSnapshot.Levels = .silence
    /// The most recent error; cleared by `dismissError()` or when a new recording starts.
    private(set) var lastError: RecordingError?
    /// The outcome of the most recent successful save.
    private(set) var lastResult: FinalizationResult?

    var isRecording: Bool { state == .recording }
    var canStart: Bool { state == .idle && !dependencies.permittedSources().isEmpty }
    var formattedElapsedTime: String { Self.format(elapsedSeconds: elapsedSeconds) }

    @ObservationIgnored private let dependencies: Dependencies
    @ObservationIgnored private var active: ActiveRecording?

    private struct ActiveRecording {
        let settings: RecordingSettings
        let engine: any CaptureEngine
        let writer: any RecordingWriter
        let streams: CaptureStreams
        let intermediates: IntermediateFiles
        let baseName: String
        let startUptime: TimeInterval
        var tasks: [Task<Void, Never>] = []
    }

    init(dependencies: Dependencies) {
        self.dependencies = dependencies
    }

    static func format(elapsedSeconds: Int) -> String {
        let seconds = max(elapsedSeconds, 0)
        return String(format: "%02d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60)
    }

    func dismissError() {
        lastError = nil
    }

    // MARK: - Start

    /// Starts a recording. Ignored unless idle (e.g. while the previous one is being saved).
    func start() async {
        guard state == .idle else { return }
        let sources = dependencies.permittedSources()
        guard !sources.isEmpty else {
            lastError = .noPermission
            return
        }
        lastError = nil
        lastResult = nil
        state = .starting

        let settings = dependencies.settings()
        do {
            try dependencies.storage.prepare(settings.destinationFolder)
        } catch {
            fail(RecordingError(error))
            return
        }

        let engine = dependencies.makeEngine(settings.echoCancellation)
        let events = engine.events()
        let streams: CaptureStreams
        do {
            streams = try await engine.start(
                CaptureConfiguration(inputDeviceUID: settings.inputDeviceUID, sources: sources))
        } catch {
            fail(error == .noSources || error == .noInputDevice ? .noPermission : .captureFailed)
            return
        }
        let startUptime = dependencies.clock.uptime()
        let baseName = FileNaming.baseName(for: dependencies.clock.date())

        let roles: [FileNaming.Role] = [streams.microphone.map { _ in .recordingMicrophone },
                                        streams.system.map { _ in .recordingSystem }].compactMap { $0 }
        let urls = FileNaming.uniqueURLs(in: settings.destinationFolder, base: baseName, roles: roles,
                                         fileExtension: FileNaming.intermediateExtension)
        let intermediates = IntermediateFiles(
            microphone: roles.firstIndex(of: .recordingMicrophone).map { urls[$0] },
            system: roles.firstIndex(of: .recordingSystem).map { urls[$0] })

        let writer = dependencies.makeWriter()
        let failures = writer.failures()
        do {
            try await writer.start(streams: streams, files: intermediates)
        } catch {
            await engine.stop()
            fail(.writeFailed)
            return
        }

        var recording = ActiveRecording(settings: settings, engine: engine, writer: writer, streams: streams,
                                        intermediates: intermediates, baseName: baseName, startUptime: startUptime)
        recording.tasks = watch(events: events, failures: failures,
                                storage: dependencies.storage.monitor(settings.destinationFolder))
        active = recording
        elapsedSeconds = 0
        state = .recording
    }

    // MARK: - Stop

    /// Stops the recording and returns once the output is saved.
    func stop() async {
        await finish(error: nil)
    }

    /// Recomputes elapsed time and levels; called periodically while recording.
    func refresh() {
        guard state == .recording, let active else { return }
        elapsedSeconds = Int(dependencies.clock.uptime() - active.startUptime)
        levels = active.streams.levels.take()
    }

    private func finish(error: RecordingError?) async {
        guard state == .recording, let recording = active else { return }
        state = .finishing
        recording.tasks.forEach { $0.cancel() }
        if let error { lastError = error }

        await recording.engine.stop()
        do {
            _ = try await recording.writer.finish()
        } catch {
            if lastError == nil { lastError = .writeFailed }
        }

        do {
            lastResult = try await dependencies.finalizer.finalize(FinalizationRequest(
                intermediates: recording.intermediates, baseName: recording.baseName,
                destination: recording.settings.destinationFolder, format: recording.settings.format,
                separateFiles: recording.settings.separateFiles))
        } catch {
            // A storage error already explains why saving failed.
            if lastError == nil { lastError = .saveFailed }
        }

        active = nil
        elapsedSeconds = 0
        levels = .silence
        state = .idle
    }

    private func fail(_ error: RecordingError) {
        lastError = error
        state = .idle
    }

    // MARK: - Monitoring

    private func watch(events: AsyncStream<CaptureEvent>, failures: AsyncStream<RecordingWriterError>,
                       storage: AsyncStream<StorageError>) -> [Task<Void, Never>] {
        var tasks = [
            Task { [weak self] in
                for await event in events {
                    if case .failed = event {
                        await self?.finish(error: .captureFailed)
                        return
                    }
                }
            },
            Task { [weak self] in
                for await _ in failures {
                    await self?.finish(error: .writeFailed)
                    return
                }
            },
            Task { [weak self] in
                for await problem in storage {
                    await self?.finish(error: RecordingError(problem))
                    return
                }
            },
        ]
        if let interval = dependencies.refreshInterval {
            tasks.append(Task { [weak self] in
                while !Task.isCancelled {
                    self?.refresh()
                    try? await Task.sleep(for: interval)
                }
            })
        }
        return tasks
    }
}
