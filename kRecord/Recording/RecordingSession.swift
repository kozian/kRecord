import Foundation
import Observation

/// A user-facing reason a recording could not start or stopped early (recording-session spec).
enum RecordingError: Error, Equatable, Sendable {
    case noPermission
    /// Both sources are turned off.
    case noSourceEnabled
    /// Only the microphone is to be recorded, but no input device is connected.
    case noMicrophone
    case folderNotWritable
    case folderUnavailable
    case diskFull
    case captureFailed
    case writeFailed
    /// The recording could not be repackaged as `.m4a`; the `.aac` file is kept.
    case saveFailed

    var message: String {
        switch self {
        case .noPermission:
            String(localized: "kRecord has no permission to record the microphone or system audio.")
        case .noSourceEnabled:
            String(localized: "Turn on the microphone or system audio to record.")
        case .noMicrophone:
            String(localized: "No microphone is connected. Connect one, or turn on system audio to record.")
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
            String(localized: "The recording couldn't be saved as m4a. It was kept as an .aac file in the destination folder.")
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

/// The outcome of a saved recording.
struct FinalizationResult: Equatable, Sendable {
    var outputs: [URL]
    /// System audio was captured but is entirely digital zero (permissions spec hint).
    var systemAudioSilent: Bool
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
    var canStart: Bool { state == .idle && !sourcesToRecord.isEmpty }

    /// What the next recording captures: the sources that are both turned on and permitted.
    var sourcesToRecord: CaptureSources {
        dependencies.permittedSources().intersection(dependencies.settings().enabledSources)
    }
    var formattedElapsedTime: String { Self.format(elapsedSeconds: elapsedSeconds) }

    @ObservationIgnored private let dependencies: Dependencies
    @ObservationIgnored private var active: ActiveRecording?
    @ObservationIgnored private var idleWaiters: [CheckedContinuation<Void, Never>] = []

    private struct ActiveRecording {
        let settings: RecordingSettings
        let engine: any CaptureEngine
        let writer: any RecordingWriter
        let streams: CaptureStreams
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

    /// Forgets the outcome of the last save (e.g. after the user dismissed a hint about it).
    func dismissResult() {
        lastResult = nil
    }

    /// Returns once the session is idle, e.g. after a recording that is being saved finished.
    func waitUntilIdle() async {
        guard state != .idle else { return }
        await withCheckedContinuation { idleWaiters.append($0) }
    }

    private func becomeIdle() {
        state = .idle
        let waiters = idleWaiters
        idleWaiters = []
        waiters.forEach { $0.resume() }
    }

    // MARK: - Start

    /// Starts a recording. Ignored unless idle (e.g. while the previous one is being saved).
    func start() async {
        guard state == .idle else { return }
        let settingsAtStart = dependencies.settings()
        guard !settingsAtStart.enabledSources.isEmpty else {
            lastError = .noSourceEnabled
            return
        }
        let sources = dependencies.permittedSources().intersection(settingsAtStart.enabledSources)
        guard !sources.isEmpty else {
            lastError = .noPermission
            return
        }
        lastError = nil
        lastResult = nil
        state = .starting

        let settings = settingsAtStart
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
            switch error {
            case .noSources: fail(.noPermission)
            case .noInputDevice: fail(.noMicrophone)
            default: fail(.captureFailed)
            }
            return
        }
        let startUptime = dependencies.clock.uptime()
        let plan = Self.writerPlan(for: streams, settings: settings, date: dependencies.clock.date())

        let writer = dependencies.makeWriter()
        let failures = writer.failures()
        do {
            try await writer.start(streams: streams, plan: plan)
        } catch {
            await engine.stop()
            fail(.writeFailed)
            return
        }

        var recording = ActiveRecording(settings: settings, engine: engine, writer: writer, streams: streams,
                                        startUptime: startUptime)
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
            let written = try await recording.writer.finish()
            let outputs: [URL]
            do {
                outputs = try await dependencies.finalizer.finalize(
                    FinalizationRequest(streams: written.streams, saveAsM4A: recording.settings.saveAsM4A))
            } catch {
                // The `.aac` streams are kept; a storage error already explains why saving failed.
                if lastError == nil { lastError = .saveFailed }
                outputs = written.streams.map(\.url)
            }
            lastResult = FinalizationResult(outputs: outputs, systemAudioSilent: written.systemAudioSilent)
        } catch {
            // Whatever was written stays in the `.aac` file(s).
            if lastError == nil { lastError = .writeFailed }
        }

        active = nil
        elapsedSeconds = 0
        levels = .silence
        becomeIdle()
    }

    /// Final names for this recording's `.aac` streams; free with both `.aac` and `.m4a` extensions.
    static func writerPlan(for streams: CaptureStreams, settings: RecordingSettings, date: Date) -> WriterPlan {
        let folder = settings.destinationFolder
        let roles: [FileNaming.Role] = settings.separateFiles
            ? [streams.microphone.map { _ in .microphone }, streams.system.map { _ in .system }].compactMap { $0 }
            : [.mixed]
        let base = FileNaming.availableBase(in: folder, base: FileNaming.baseName(for: date), roles: roles)
        func url(_ role: FileNaming.Role) -> URL {
            folder.appending(path: FileNaming.fileName(base: base, role: role, fileExtension: AACEncoding.streamExtension))
        }
        guard settings.separateFiles else { return .mixed(url(.mixed)) }
        return .separate(microphone: streams.microphone.map { _ in url(.microphone) },
                         system: streams.system.map { _ in url(.system) })
    }

    private func fail(_ error: RecordingError) {
        lastError = error
        becomeIdle()
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
