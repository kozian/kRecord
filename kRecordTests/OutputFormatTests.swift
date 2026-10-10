import AVFoundation
import Foundation
import Testing
@testable import kRecord

struct OutputFormatTests {
    @Test func fileExtensions() {
        #expect(OutputFormat.aac.fileExtension == "m4a")
        #expect(OutputFormat.alac.fileExtension == "m4a")
        #expect(OutputFormat.wav.fileExtension == "wav")
    }

    @Test(arguments: [1, 2])
    func aacSettings(channels: Int) {
        let settings = OutputFormat.aac.settings(channels: channels)
        #expect(settings[AVFormatIDKey] as? AudioFormatID == kAudioFormatMPEG4AAC)
        #expect(settings[AVSampleRateKey] as? Double == 48_000)
        #expect(settings[AVNumberOfChannelsKey] as? Int == channels)
        #expect((settings[AVEncoderBitRateKey] as? Int ?? 0) >= 128_000)
    }

    @Test func alacSettings() {
        let settings = OutputFormat.alac.settings(channels: 2)
        #expect(settings[AVFormatIDKey] as? AudioFormatID == kAudioFormatAppleLossless)
        #expect(settings[AVSampleRateKey] as? Double == 48_000)
        #expect(settings[AVEncoderBitDepthHintKey] as? Int == 16)
    }

    @Test func wavSettings() {
        let settings = OutputFormat.wav.settings(channels: 2)
        #expect(settings[AVFormatIDKey] as? AudioFormatID == kAudioFormatLinearPCM)
        #expect(settings[AVSampleRateKey] as? Double == 48_000)
        #expect(settings[AVLinearPCMBitDepthKey] as? Int == 16)
        #expect(settings[AVLinearPCMIsFloatKey] as? Bool == false)
    }

    /// The generated settings are accepted by AVAudioFile and produce the expected file format.
    @Test(arguments: OutputFormat.allCases)
    func settingsCreateWritableFiles(format: OutputFormat) throws {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "OutputFormatTests-\(UUID().uuidString).\(format.fileExtension)")
        defer { try? FileManager.default.removeItem(at: url) }
        do {
            let file = try AVAudioFile(forWriting: url, settings: format.settings(channels: 2))
            let buffer = try #require(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 4_800))
            buffer.frameLength = 4_800
            try file.write(from: buffer)
        }
        let file = try AVAudioFile(forReading: url)
        let description = file.fileFormat.streamDescription.pointee
        #expect(file.fileFormat.sampleRate == 48_000)
        #expect(file.fileFormat.channelCount == 2)
        switch format {
        case .aac: #expect(description.mFormatID == kAudioFormatMPEG4AAC)
        case .alac: #expect(description.mFormatID == kAudioFormatAppleLossless)
        case .wav:
            #expect(description.mFormatID == kAudioFormatLinearPCM)
            #expect(description.mBitsPerChannel == 16)
        }
    }
}
