import AVFoundation
import Foundation
import Testing
@testable import kRecord

struct RecordingWriterTests {
    private let directory: URL

    init() throws {
        directory = FileManager.default.temporaryDirectory
            .appending(path: "RecordingWriterTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private var files: IntermediateFiles {
        IntermediateFiles(microphone: directory.appending(path: "mic.caf"),
                          system: directory.appending(path: "system.caf"))
    }

    private func read(_ url: URL) throws -> (format: AVAudioFormat, fileType: String, samples: [[Float]]) {
        let file = try AVAudioFile(forReading: url)
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                                                   frameCapacity: AVAudioFrameCount(max(file.length, 1))))
        try file.read(into: buffer)
        let channels = (0..<Int(file.processingFormat.channelCount)).map { channel in
            Array(UnsafeBufferPointer(start: buffer.floatChannelData![channel], count: Int(buffer.frameLength)))
        }
        return (file.fileFormat, url.pathExtension, channels)
    }

    private let quantization: Float = 1.0 / 32_768 + 1e-6

    @Test func writesFramesFromBothSourcesToCAF() async throws {
        let engine = FakeCaptureEngine()
        let streams = try await engine.start(CaptureConfiguration(inputDeviceUID: nil, sources: .all))
        let writer = CAFRecordingWriter(chunkFrames: 1_000)
        try await writer.start(streams: streams, files: files)

        engine.pump(frames: 2_500)
        await writer.drainAvailable()
        engine.pump(frames: 1_700)
        await engine.stop()
        let written = try await writer.finish()
        #expect(written == WrittenFrames(microphone: 4_200, system: 4_200))

        let mic = try read(try #require(files.microphone))
        #expect(mic.format.channelCount == 1)
        #expect(mic.format.sampleRate == 48_000)
        #expect(mic.format.streamDescription.pointee.mBitsPerChannel == 16)
        #expect(mic.samples[0].count == 4_200)
        for n in [0, 999, 1_000, 2_500, 4_199] {
            #expect(abs(mic.samples[0][n] - FakeCaptureEngine.micSample(n)) <= quantization)
        }

        let system = try read(try #require(files.system))
        #expect(system.format.channelCount == 2)
        #expect(system.samples[0].count == 4_200)
        for n in [0, 1_234, 4_199] {
            #expect(abs(system.samples[0][n] - FakeCaptureEngine.systemSample(n, channel: 0)) <= quantization)
            #expect(abs(system.samples[1][n] - FakeCaptureEngine.systemSample(n, channel: 1)) <= quantization)
        }
    }

    @Test func drainsPeriodicallyWhileRecording() async throws {
        let engine = FakeCaptureEngine()
        let streams = try await engine.start(CaptureConfiguration(inputDeviceUID: nil, sources: .all))
        let writer = CAFRecordingWriter()
        try await writer.start(streams: streams, files: files)

        engine.pump(frames: 4_800)
        try await Task.sleep(for: .milliseconds(300))
        #expect(streams.microphone?.availableFrames == 0)
        #expect(streams.system?.availableFrames == 0)
        await engine.stop()
        _ = try await writer.finish()
    }

    /// An intermediate file that was never closed (app killed) is still readable up to about the last write.
    @Test func unclosedFileIsReadable() async throws {
        let engine = FakeCaptureEngine()
        let streams = try await engine.start(CaptureConfiguration(inputDeviceUID: nil, sources: .all))
        let writer = CAFRecordingWriter()
        try await writer.start(streams: streams, files: files)

        engine.pump(frames: 48_000)
        await writer.drainAvailable()

        // Copy the files while the writer still has them open, as if the process had died here.
        let crashedMic = directory.appending(path: "crashed-mic.caf")
        let crashedSystem = directory.appending(path: "crashed-system.caf")
        try FileManager.default.copyItem(at: try #require(files.microphone), to: crashedMic)
        try FileManager.default.copyItem(at: try #require(files.system), to: crashedSystem)

        // The file layer may still hold a few milliseconds in memory; at most 100 ms may be lost.
        let micFrames = try read(crashedMic).samples[0].count
        let systemFrames = try read(crashedSystem).samples[1].count
        #expect((43_200...48_000).contains(micFrames))
        #expect((43_200...48_000).contains(systemFrames))

        await engine.stop()
        _ = try await writer.finish()
    }

    @Test func singleSourceWritesOneFile() async throws {
        let engine = FakeCaptureEngine()
        let streams = try await engine.start(CaptureConfiguration(inputDeviceUID: nil, sources: .system))
        let writer = CAFRecordingWriter()
        try await writer.start(streams: streams, files: IntermediateFiles(microphone: nil, system: files.system))
        engine.pump(frames: 480)
        await engine.stop()
        #expect(try await writer.finish() == WrittenFrames(microphone: 0, system: 480))
        #expect(!FileManager.default.fileExists(atPath: try #require(files.microphone).path))
    }

    @Test func droppedFramesBecomeSilenceToKeepAlignment() async throws {
        // Ring of 1000 frames: pumping 1500 at once drops the whole 1500-frame write.
        let engine = FakeCaptureEngine(capacityFrames: 1_000)
        let streams = try await engine.start(CaptureConfiguration(inputDeviceUID: nil, sources: .all))
        let writer = CAFRecordingWriter(chunkFrames: 1_000)
        try await writer.start(streams: streams, files: files)

        engine.pump(frames: 600)
        await writer.drainAvailable()
        engine.pump(frames: 1_500)
        engine.pump(frames: 400)
        await engine.stop()
        #expect(try await writer.finish() == WrittenFrames(microphone: 2_500, system: 2_500))

        let mic = try read(try #require(files.microphone)).samples[0]
        #expect(mic[600..<2_100].allSatisfy { $0 == 0 })
        // Frame 2_100 holds the sample produced as frame 2_100: the timeline is preserved.
        #expect(abs(mic[2_101] - FakeCaptureEngine.micSample(2_101)) <= quantization)
    }

    @Test func unwritableDestinationFailsToStart() async throws {
        let engine = FakeCaptureEngine()
        let streams = try await engine.start(CaptureConfiguration(inputDeviceUID: nil, sources: .all))
        let writer = CAFRecordingWriter()
        let missing = directory.appending(path: "missing/folder/mic.caf")
        await #expect(throws: RecordingWriterError.cannotCreateFile(missing)) {
            try await writer.start(streams: streams, files: IntermediateFiles(microphone: missing, system: nil))
        }
    }
}
