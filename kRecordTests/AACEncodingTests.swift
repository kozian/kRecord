import AVFoundation
import Foundation
import Testing
@testable import kRecord

struct AACEncodingTests {
    private func temporaryURL() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "AACEncodingTests-\(UUID().uuidString).aac")
    }

    private func properties(of url: URL) throws -> (type: AudioFileTypeID, bitRate: UInt32, format: AudioStreamBasicDescription) {
        var fileID: AudioFileID?
        try #require(AudioFileOpenURL(url as CFURL, .readPermission, 0, &fileID) == noErr)
        defer { AudioFileClose(fileID!) }
        var type: AudioFileTypeID = 0
        var bitRate: UInt32 = 0
        var format = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<UInt32>.size)
        AudioFileGetProperty(fileID!, kAudioFilePropertyFileFormat, &size, &type)
        size = UInt32(MemoryLayout<UInt32>.size)
        AudioFileGetProperty(fileID!, kAudioFilePropertyBitRate, &size, &bitRate)
        size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        AudioFileGetProperty(fileID!, kAudioFilePropertyDataFormat, &size, &format)
        return (type, bitRate, format)
    }

    /// Silence still encodes at 128 kbps into an ADTS stream at 48 kHz.
    @Test(arguments: [1, 2])
    func writesConstantBitRateADTS(channels: Int) throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let file = try AACStreamFile(url: url, channels: channels, inputSampleRate: 48_000, capacity: 48_000)
        try file.write(frames: 48_000)
        try file.write(frames: 48_000)
        file.close()
        #expect(file.encodedFrames == 96_000)

        let properties = try properties(of: url)
        #expect(properties.type == kAudioFileAAC_ADTSType)
        #expect(properties.format.mFormatID == kAudioFormatMPEG4AAC)
        #expect(properties.format.mSampleRate == 48_000)
        #expect(properties.format.mChannelsPerFrame == UInt32(channels))
        #expect(properties.bitRate >= 120_000)
    }

    /// A 44.1 kHz capture is converted to a 48 kHz stream of the same duration.
    @Test func convertsSampleRate() throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let file = try AACStreamFile(url: url, channels: 2, inputSampleRate: 44_100, capacity: 44_100)
        for channel in 0..<2 {
            for frame in 0..<44_100 { file.channelData[channel][frame] = 0.3 * sin(Float(frame) * 0.05) }
        }
        try file.write(frames: 44_100)
        file.close()
        #expect(file.encodedFrames == 48_000)

        let decoded = try AVAudioFile(forReading: url)
        #expect(decoded.fileFormat.sampleRate == 48_000)
        // One second of audio plus encoder priming and padding.
        #expect(abs(decoded.length - 48_000) < 4_096)
    }

    @Test func unwritableLocationFails() {
        let url = URL(fileURLWithPath: "/nonexistent-folder/x.aac")
        #expect(throws: RecordingWriterError.cannotCreateFile(url)) {
            _ = try AACStreamFile(url: url, channels: 1, inputSampleRate: 48_000, capacity: 1_024)
        }
    }
}
