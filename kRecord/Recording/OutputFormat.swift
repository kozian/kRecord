import AVFoundation

/// Final recording formats (recording-output spec, design D5).
enum OutputFormat: String, CaseIterable, Codable, Sendable {
    case aac
    case alac
    case wav

    static let sampleRate: Double = 48_000
    /// The spec requires at least 128 kbps; used for mono and stereo.
    static let aacBitRate = 128_000

    var fileExtension: String {
        switch self {
        case .aac, .alac: "m4a"
        case .wav: "wav"
        }
    }

    /// `AVAudioFile` settings for writing `channels` channels at 48 kHz.
    func settings(channels: Int) -> [String: Any] {
        var settings: [String: Any] = [
            AVSampleRateKey: Self.sampleRate,
            AVNumberOfChannelsKey: channels,
        ]
        switch self {
        case .aac:
            settings[AVFormatIDKey] = kAudioFormatMPEG4AAC
            settings[AVEncoderBitRateKey] = Self.aacBitRate
            // Constant bit rate: the default variable strategy drops far below 128 kbps on quiet audio.
            settings[AVEncoderBitRateStrategyKey] = AVAudioBitRateStrategy_Constant
        case .alac:
            settings[AVFormatIDKey] = kAudioFormatAppleLossless
            settings[AVEncoderBitDepthHintKey] = 16
        case .wav:
            settings[AVFormatIDKey] = kAudioFormatLinearPCM
            settings[AVLinearPCMBitDepthKey] = 16
            settings[AVLinearPCMIsFloatKey] = false
            settings[AVLinearPCMIsBigEndianKey] = false
            settings[AVLinearPCMIsNonInterleaved] = false
        }
        return settings
    }
}
