import Foundation

/// Which sources a recording captures. At least one must be present.
struct CaptureSources: OptionSet, Hashable, Sendable {
    let rawValue: Int

    static let microphone = CaptureSources(rawValue: 1 << 0)
    static let system = CaptureSources(rawValue: 1 << 1)
    static let all: CaptureSources = [.microphone, .system]
}

struct CaptureConfiguration: Equatable, Sendable {
    /// Core Audio UID of the selected input device, or `nil` to follow the system default input.
    var inputDeviceUID: String?
    var sources: CaptureSources
}

/// Live output of a running capture.
///
/// Both ring buffers advance by the same number of frames in every IO cycle, so frame N of the
/// microphone and frame N of system audio were captured at the same moment (design D2). A gap
/// during a device switch (D3) removes the same span from both.
struct CaptureStreams: Sendable {
    static let microphoneChannels = 1
    static let systemChannels = 2

    let sampleRate: Double
    /// Mono microphone frames; `nil` when the microphone is not captured.
    let microphone: RingBuffer?
    /// Interleaved stereo system audio frames; `nil` when system audio is not captured.
    let system: RingBuffer?
    let levels: LevelSnapshot
}

enum CaptureEvent: Equatable, Sendable {
    /// The microphone switched to another device during a recording (default input changed, or the
    /// selected device disappeared and capture fell back to the default).
    case inputDeviceChanged(name: String)
    /// Capture stopped and cannot continue.
    case failed(CaptureError)
}

enum CaptureError: Error, Equatable, Sendable {
    case noSources
    case noInputDevice
    /// A capture stream is not in the interleaved Float32 format the IOProc expects.
    case unsupportedFormat
    /// A new input device cannot run at the sample rate the recording started with.
    case sampleRateMismatch
    /// A Core Audio call failed; `operation` names it for diagnostics.
    case coreAudio(operation: String, status: OSStatus)
}

/// Captures microphone and/or system audio into ring buffers (design D2, D6).
///
/// Implementations: `AggregateCaptureEngine` (default) and `VoiceProcessingCaptureEngine`
/// (echo cancellation). One capture runs at a time; `start` after `stop` begins a new capture.
protocol CaptureEngine: AnyObject, Sendable {
    /// Events of the current capture. Each call returns a new stream that ends when capture stops.
    func events() -> AsyncStream<CaptureEvent>

    /// Starts capturing. The returned buffers stay valid until `stop` returns.
    func start(_ configuration: CaptureConfiguration) async throws(CaptureError) -> CaptureStreams

    /// Stops capturing. Frames already in the ring buffers remain readable.
    func stop() async
}
