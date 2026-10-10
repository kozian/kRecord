import AVFoundation
import Foundation
import Testing
@testable import kRecord

struct FinalizerTests {
    private let directory: URL
    private let base = "kRecord 2026-10-10 14-30-05"
    private let tolerance: Float = 2.0 / 32_768

    init() throws {
        directory = FileManager.default.temporaryDirectory
            .appending(path: "FinalizerTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    // MARK: Helpers

    /// Writes a 16-bit CAF intermediate like `CAFRecordingWriter` does. `channels[c][n]` is sample n of channel c.
    @discardableResult
    private func intermediate(_ role: FileNaming.Role, _ channels: [[Float]], sampleRate: Double = 48_000) throws -> URL {
        let url = directory.appending(path: FileNaming.fileName(base: base, role: role, fileExtension: "caf"))
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: sampleRate, AVNumberOfChannelsKey: channels.count,
            AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false,
        ]
        let file = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                                                   frameCapacity: AVAudioFrameCount(max(channels[0].count, 1))))
        for (c, samples) in channels.enumerated() {
            buffer.floatChannelData![c].update(from: samples, count: samples.count)
        }
        buffer.frameLength = AVAudioFrameCount(channels[0].count)
        try file.write(from: buffer)
        return url
    }

    private func read(_ url: URL) throws -> (file: AVAudioFile, channels: [[Float]]) {
        let file = try AVAudioFile(forReading: url)
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                                                   frameCapacity: AVAudioFrameCount(max(file.length, 1))))
        try file.read(into: buffer)
        let channels = (0..<Int(file.processingFormat.channelCount)).map {
            Array(UnsafeBufferPointer(start: buffer.floatChannelData![$0], count: Int(buffer.frameLength)))
        }
        return (file, channels)
    }

    private func request(_ files: IntermediateFiles, format: OutputFormat = .wav, separate: Bool = false) -> FinalizationRequest {
        FinalizationRequest(intermediates: files, baseName: base, destination: directory, format: format, separateFiles: separate)
    }

    private func directoryContents() throws -> Set<String> {
        Set(try FileManager.default.contentsOfDirectory(atPath: directory.path))
    }

    private func sine(_ frames: Int, amplitude: Float = 0.5) -> [Float] {
        (0..<frames).map { amplitude * sin(2 * .pi * 440 * Float($0) / 48_000) }
    }

    // MARK: Mixed

    @Test func mixesAtMinusThreeDecibelsWithMicCentered() async throws {
        let frames = 4_800
        let files = IntermediateFiles(
            microphone: try intermediate(.recordingMicrophone, [Array(repeating: 0.5, count: frames)]),
            system: try intermediate(.recordingSystem, [Array(repeating: 0.2, count: frames), Array(repeating: -0.2, count: frames)]))

        let result = try await AudioFinalizer().finalize(request(files))
        #expect(result.outputs.map(\.lastPathComponent) == ["\(base).wav"])
        #expect(!result.systemAudioSilent)

        let (file, channels) = try read(result.outputs[0])
        #expect(file.fileFormat.channelCount == 2)
        #expect(file.length == AVAudioFramePosition(frames))
        let g = AudioFinalizer.mixGain
        #expect(abs(channels[0][100] - g * (0.2 + 0.5)) < tolerance)
        #expect(abs(channels[1][100] - g * (-0.2 + 0.5)) < tolerance)
    }

    @Test func microphoneAloneIsEquallyLoudInBothChannels() async throws {
        let mic = sine(9_600)
        let files = IntermediateFiles(
            microphone: try intermediate(.recordingMicrophone, [mic]),
            system: try intermediate(.recordingSystem, [Array(repeating: 0, count: mic.count), Array(repeating: 0, count: mic.count)]))

        let result = try await AudioFinalizer().finalize(request(files))
        let channels = try read(result.outputs[0]).channels
        #expect(channels[0] == channels[1])
        #expect(abs(channels[0][110] - AudioFinalizer.mixGain * mic[110]) < tolerance)
        #expect(result.systemAudioSilent)
    }

    @Test func clampsLoudMix() async throws {
        let files = IntermediateFiles(
            microphone: try intermediate(.recordingMicrophone, [Array(repeating: 0.99, count: 480)]),
            system: try intermediate(.recordingSystem, [Array(repeating: 0.99, count: 480), Array(repeating: -0.99, count: 480)]))
        let channels = try read(try await AudioFinalizer().finalize(request(files)).outputs[0]).channels
        #expect(channels[0].allSatisfy { $0 <= 1 && $0 > 0.99 })
        #expect(channels[1].allSatisfy { abs($0) < tolerance })
    }

    @Test func mixedWithDifferentLengthsPadsWithSilence() async throws {
        let files = IntermediateFiles(
            microphone: try intermediate(.recordingMicrophone, [Array(repeating: 0.5, count: 1_000)]),
            system: try intermediate(.recordingSystem, [Array(repeating: 0, count: 1_200), Array(repeating: 0, count: 1_200)]))
        let (file, channels) = try read(try await AudioFinalizer().finalize(request(files)).outputs[0])
        #expect(file.length == 1_200)
        #expect(channels[0][1_100] == 0)
    }

    @Test func microphoneOnlyRecordingIsMixedToStereo() async throws {
        let files = IntermediateFiles(microphone: try intermediate(.recordingMicrophone, [sine(4_800)]), system: nil)
        let result = try await AudioFinalizer().finalize(request(files))
        #expect(!result.systemAudioSilent)
        #expect(try read(result.outputs[0]).file.fileFormat.channelCount == 2)
    }

    // MARK: Separate

    @Test func separateFilesKeepSourcesApart() async throws {
        let files = IntermediateFiles(
            microphone: try intermediate(.recordingMicrophone, [sine(4_800)]),
            system: try intermediate(.recordingSystem, [sine(4_800, amplitude: 0.3), sine(4_800, amplitude: 0.1)]))

        let result = try await AudioFinalizer().finalize(request(files, separate: true))
        #expect(result.outputs.map(\.lastPathComponent) == ["\(base) (mic).wav", "\(base) (system).wav"])

        let mic = try read(result.outputs[0])
        let system = try read(result.outputs[1])
        #expect(mic.file.fileFormat.channelCount == 1)
        #expect(system.file.fileFormat.channelCount == 2)
        #expect(mic.file.length == system.file.length)
        #expect(abs(mic.channels[0][120] - sine(4_800)[120]) < tolerance)
        #expect(abs(system.channels[1][120] - sine(4_800, amplitude: 0.1)[120]) < tolerance)
        #expect(try directoryContents() == ["\(base) (mic).wav", "\(base) (system).wav"])
    }

    // MARK: Formats

    @Test(arguments: [OutputFormat.aac, .alac])
    func encodesCompressedFormats(format: OutputFormat) async throws {
        let files = IntermediateFiles(
            microphone: try intermediate(.recordingMicrophone, [sine(48_000)]),
            system: try intermediate(.recordingSystem, [sine(48_000), sine(48_000)]))
        let result = try await AudioFinalizer().finalize(request(files, format: format))
        #expect(result.outputs.map(\.lastPathComponent) == ["\(base).m4a"])

        let file = try AVAudioFile(forReading: result.outputs[0])
        let formatID = file.fileFormat.streamDescription.pointee.mFormatID
        #expect(formatID == (format == .aac ? kAudioFormatMPEG4AAC : kAudioFormatAppleLossless))
        #expect(file.fileFormat.sampleRate == 48_000)
        #expect(abs(file.length - 48_000) <= 2_048)
    }

    @Test func resamplesTo48kHz() async throws {
        let files = IntermediateFiles(microphone: nil,
                                      system: try intermediate(.recordingSystem, [sine(44_100), sine(44_100)], sampleRate: 44_100))
        let (file, _) = try read(try await AudioFinalizer().finalize(request(files)).outputs[0])
        #expect(file.fileFormat.sampleRate == 48_000)
        #expect(abs(file.length - 48_000) <= 64)
    }

    // MARK: Files

    @Test func removesIntermediatesAfterSuccess() async throws {
        let files = IntermediateFiles(
            microphone: try intermediate(.recordingMicrophone, [sine(480)]),
            system: try intermediate(.recordingSystem, [sine(480), sine(480)]))
        _ = try await AudioFinalizer().finalize(request(files, format: .aac))
        #expect(try directoryContents() == ["\(base).m4a"])
    }

    @Test func doesNotOverwriteExistingFile() async throws {
        try Data("existing".utf8).write(to: directory.appending(path: "\(base).wav"))
        let files = IntermediateFiles(microphone: try intermediate(.recordingMicrophone, [sine(480)]), system: nil)
        let result = try await AudioFinalizer().finalize(request(files))
        #expect(result.outputs.map(\.lastPathComponent) == ["\(base) 2.wav"])
        #expect(try Data(contentsOf: directory.appending(path: "\(base).wav")) == Data("existing".utf8))
    }

    @Test func keepsIntermediatesWhenOutputCannotBeWritten() async throws {
        let mic = try intermediate(.recordingMicrophone, [sine(480)])
        var request = request(IntermediateFiles(microphone: mic, system: nil))
        request.destination = directory.appending(path: "missing")
        await #expect(throws: FinalizerError.self) {
            _ = try await AudioFinalizer().finalize(request)
        }
        #expect(FileManager.default.fileExists(atPath: mic.path))
    }

    @Test func missingIntermediateFails() async throws {
        let missing = directory.appending(path: "nope.caf")
        await #expect(throws: FinalizerError.cannotReadIntermediate(missing)) {
            _ = try await AudioFinalizer().finalize(request(IntermediateFiles(microphone: missing, system: nil)))
        }
    }
}
