import AVFoundation
import Foundation
import Testing
@testable import kRecord

struct FinalizerTests {
    private let directory: URL

    init() throws {
        directory = FileManager.default.temporaryDirectory
            .appending(path: "FinalizerTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    /// Encodes `frames` frames of a sine into an ADTS stream like the writer does.
    private func stream(_ name: String, frames: Int, channels: Int = 2) throws -> RecordedStream {
        let url = directory.appending(path: name)
        let file = try AACStreamFile(url: url, channels: channels, inputSampleRate: 48_000, capacity: 4_800)
        var written = 0
        while written < frames {
            let chunk = min(4_800, frames - written)
            for channel in 0..<channels {
                for i in 0..<chunk { file.channelData[channel][i] = 0.4 * sin(Float(written + i) * 0.06) }
            }
            try file.write(frames: chunk)
            written += chunk
        }
        file.close()
        return RecordedStream(url: url, frames: file.encodedFrames)
    }

    /// The concatenated payloads of all AAC packets of a file, in order.
    private func packetData(_ url: URL) throws -> Data {
        var fileID: AudioFileID?
        try #require(AudioFileOpenURL(url as CFURL, .readPermission, 0, &fileID) == noErr)
        defer { AudioFileClose(fileID!) }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 1 << 20)
        var descriptions = [AudioStreamPacketDescription](repeating: .init(), count: 1_000)
        var position: Int64 = 0
        while true {
            var bytes = UInt32(buffer.count)
            var packets: UInt32 = 1_000
            AudioFileReadPacketData(fileID!, false, &bytes, &descriptions, position, &packets, &buffer)
            if packets == 0 { break }
            // Packets sit at their descriptions' offsets; ADTS data has gaps between them.
            for description in descriptions.prefix(Int(packets)) {
                let start = Int(description.mStartOffset)
                data.append(contentsOf: buffer[start..<start + Int(description.mDataByteSize)])
            }
            position += Int64(packets)
        }
        return data
    }

    private func contents() throws -> Set<String> {
        Set(try FileManager.default.contentsOfDirectory(atPath: directory.path))
    }

    @Test func repackagesWithoutReencoding() throws {
        let source = try stream("a.aac", frames: 100_000)
        let destination = directory.appending(path: "a.m4a")
        try AudioFinalizer.repackage(source.url, to: destination, validFrames: source.frames)

        #expect(try packetData(destination) == packetData(source.url))
        let file = try AVAudioFile(forReading: destination)
        #expect(file.fileFormat.streamDescription.pointee.mFormatID == kAudioFormatMPEG4AAC)
        #expect(file.fileFormat.sampleRate == 48_000)
        // The packet table trims encoder priming: the duration is exactly what was recorded.
        #expect(file.length == 100_000)
    }

    @Test func saveAsM4AReplacesStreams() async throws {
        let streams = [try stream("rec (mic).aac", frames: 48_000, channels: 1),
                       try stream("rec (system).aac", frames: 48_000)]
        let outputs = try await AudioFinalizer().finalize(FinalizationRequest(streams: streams, saveAsM4A: true))
        #expect(outputs.map(\.lastPathComponent) == ["rec (mic).m4a", "rec (system).m4a"])
        #expect(try contents() == ["rec (mic).m4a", "rec (system).m4a"])
        #expect(try AVAudioFile(forReading: outputs[0]).fileFormat.channelCount == 1)
    }

    @Test func withoutM4AStreamsAreFinal() async throws {
        let streams = [try stream("rec.aac", frames: 4_800)]
        let outputs = try await AudioFinalizer().finalize(FinalizationRequest(streams: streams, saveAsM4A: false))
        #expect(outputs == [streams[0].url])
        #expect(try contents() == ["rec.aac"])
    }

    @Test func failureKeepsStreams() async throws {
        let good = try stream("good.aac", frames: 4_800)
        let missing = RecordedStream(url: directory.appending(path: "missing.aac"), frames: 4_800)
        await #expect(throws: FinalizerError.cannotRepackage(missing.url)) {
            _ = try await AudioFinalizer().finalize(FinalizationRequest(streams: [good, missing], saveAsM4A: true))
        }
        // The stream that converted is not removed, and no partial container is left.
        #expect(try contents() == ["good.aac"])
    }

    @Test func unwritableFolderKeepsStream() async throws {
        let stream = try stream("rec.aac", frames: 4_800)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: directory.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: directory.path) }
        await #expect(throws: FinalizerError.self) {
            _ = try await AudioFinalizer().finalize(FinalizationRequest(streams: [stream], saveAsM4A: true))
        }
        #expect(FileManager.default.fileExists(atPath: stream.url.path))
    }
}
