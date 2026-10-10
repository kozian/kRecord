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

    // MARK: Helpers

    private func streams(microphone: Bool = true, system: Bool = true, capacity: Int = 480_000) -> CaptureStreams {
        CaptureStreams(sampleRate: 48_000,
                       microphone: microphone ? RingBuffer(channels: 1, capacityFrames: capacity) : nil,
                       system: system ? RingBuffer(channels: 2, capacityFrames: capacity) : nil,
                       levels: LevelSnapshot())
    }

    private func sine(_ frame: Int, amplitude: Float) -> Float {
        amplitude * sin(2 * .pi * 440 * Float(frame) / 48_000)
    }

    /// Writes `frames` frames: a 440 Hz sine of `micAmplitude` to the microphone and of
    /// `left`/`right` amplitudes to system audio.
    private func produce(_ streams: CaptureStreams, from start: Int = 0, frames: Int,
                         micAmplitude: Float = 0, left: Float = 0, right: Float = 0) {
        let mic = (0..<frames).map { sine(start + $0, amplitude: micAmplitude) }
        var system = [Float](repeating: 0, count: frames * 2)
        for i in 0..<frames {
            system[i * 2] = sine(start + i, amplitude: left)
            system[i * 2 + 1] = sine(start + i, amplitude: right)
        }
        streams.microphone?.write(mic, frameCount: frames, sourceChannels: 1)
        streams.system?.write(system, frameCount: frames, sourceChannels: 2)
    }

    /// RMS per channel of a decoded file, skipping the first 0.1 s (encoder priming and ramp-up).
    private func decodedRMS(_ url: URL) throws -> (channels: Int, rms: [Float]) {
        let file = try AVAudioFile(forReading: url)
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                                                   frameCapacity: AVAudioFrameCount(file.length)))
        try file.read(into: buffer)
        let channels = Int(file.processingFormat.channelCount)
        let start = 4_800
        let count = Int(buffer.frameLength) - start - 4_800
        let rms = (0..<channels).map { channel in
            let samples = buffer.floatChannelData![channel] + start
            return ((0..<count).reduce(Float(0)) { $0 + samples[$1] * samples[$1] } / Float(count)).squareRoot()
        }
        return (channels, rms)
    }

    private func url(_ name: String) -> URL {
        directory.appending(path: name)
    }

    private let sineRMS: Float = 0.5 / Float(2).squareRoot()

    // MARK: Mixed

    @Test func mixedMicrophoneIsCenteredAtMinusThreeDecibels() async throws {
        let streams = streams()
        let writer = AACRecordingWriter(chunkFrames: 4_800)
        try await writer.start(streams: streams, plan: .mixed(url("mixed.aac")))
        produce(streams, frames: 48_000, micAmplitude: 0.5)
        let result = try await writer.finish()

        #expect(result.streams == [RecordedStream(url: url("mixed.aac"), frames: 48_000)])
        #expect(result.systemAudioSilent)
        let (channels, rms) = try decodedRMS(url("mixed.aac"))
        #expect(channels == 2)
        let expected = AudioMix.gain * sineRMS
        #expect(abs(rms[0] - expected) < expected * 0.05)
        #expect(abs(rms[1] - expected) < expected * 0.05)
    }

    @Test func mixedKeepsSystemStereoImage() async throws {
        let streams = streams()
        let writer = AACRecordingWriter(chunkFrames: 4_800)
        try await writer.start(streams: streams, plan: .mixed(url("mixed.aac")))
        produce(streams, frames: 48_000, left: 0.5)
        let result = try await writer.finish()

        #expect(!result.systemAudioSilent)
        let rms = try decodedRMS(url("mixed.aac")).rms
        #expect(abs(rms[0] - AudioMix.gain * sineRMS) < AudioMix.gain * sineRMS * 0.05)
        #expect(rms[1] < 0.01)
    }

    @Test func mixValuesAreClamped() {
        let mic: [Float] = [0.9, 0.5]
        let system: [Float] = [0.9, -0.9, 0, 0]
        var left = [Float](repeating: 0, count: 2)
        var right = [Float](repeating: 0, count: 2)
        AudioMix.mix(microphone: mic, system: system, frames: 2, left: &left, right: &right)
        #expect(left[0] == 1)
        #expect(abs(right[0]) < 0.0001)
        #expect(abs(left[1] - AudioMix.gain * 0.5) < 0.0001)
        #expect(left[1] == right[1])
    }

    @Test func mixedWithOnlyOneSource() async throws {
        let streams = streams(microphone: false)
        let writer = AACRecordingWriter(chunkFrames: 4_800)
        try await writer.start(streams: streams, plan: .mixed(url("system-only.aac")))
        produce(streams, frames: 24_000, left: 0.5, right: 0.5)
        let result = try await writer.finish()
        #expect(result.streams.first?.frames == 24_000)
        #expect(try decodedRMS(url("system-only.aac")).channels == 2)
    }

    // MARK: Separate

    @Test func separateFilesKeepSourcesApart() async throws {
        let streams = streams()
        let writer = AACRecordingWriter(chunkFrames: 4_800)
        try await writer.start(streams: streams, plan: .separate(microphone: url("mic.aac"), system: url("system.aac")))
        produce(streams, frames: 48_000, micAmplitude: 0.5, right: 0.5)
        let result = try await writer.finish()

        #expect(result.streams == [RecordedStream(url: url("mic.aac"), frames: 48_000),
                                   RecordedStream(url: url("system.aac"), frames: 48_000)])
        let mic = try decodedRMS(url("mic.aac"))
        let system = try decodedRMS(url("system.aac"))
        #expect(mic.channels == 1)
        #expect(abs(mic.rms[0] - sineRMS) < sineRMS * 0.05)
        #expect(system.channels == 2)
        #expect(system.rms[0] < 0.01)
        #expect(abs(system.rms[1] - sineRMS) < sineRMS * 0.05)
    }

    @Test func silentSystemTrackIsReported() async throws {
        let streams = streams()
        let writer = AACRecordingWriter()
        try await writer.start(streams: streams, plan: .separate(microphone: url("mic.aac"), system: url("system.aac")))
        produce(streams, frames: 4_800, micAmplitude: 0.5)
        #expect(try await writer.finish().systemAudioSilent)
    }

    @Test func noSystemAudioIsNotReportedAsSilent() async throws {
        let streams = streams(system: false)
        let writer = AACRecordingWriter()
        try await writer.start(streams: streams, plan: .separate(microphone: url("mic.aac"), system: url("system.aac")))
        produce(streams, frames: 4_800, micAmplitude: 0.5)
        let result = try await writer.finish()
        #expect(!result.systemAudioSilent)
        #expect(result.streams.map(\.url) == [url("mic.aac")])
        #expect(!FileManager.default.fileExists(atPath: url("system.aac").path))
    }

    // MARK: Draining and crash safety

    @Test func drainsPeriodicallyWhileRecording() async throws {
        let streams = streams()
        let writer = AACRecordingWriter()
        try await writer.start(streams: streams, plan: .mixed(url("mixed.aac")))
        produce(streams, frames: 4_800, micAmplitude: 0.5)
        try await Task.sleep(for: .milliseconds(300))
        #expect(streams.microphone?.availableFrames == 0)
        #expect(streams.system?.availableFrames == 0)
        _ = try await writer.finish()
    }

    /// A stream that was never closed (app killed) is still playable up to about the last write.
    @Test func unclosedStreamIsPlayable() async throws {
        let streams = streams()
        let writer = AACRecordingWriter()
        try await writer.start(streams: streams, plan: .mixed(url("mixed.aac")))
        produce(streams, frames: 96_000, micAmplitude: 0.5)
        await writer.drainAvailable()

        let crashed = url("crashed.aac")
        try FileManager.default.copyItem(at: url("mixed.aac"), to: crashed)
        let file = try AVAudioFile(forReading: crashed)
        // Decoded length includes encoder priming; at most about 0.1 s of the end may be missing.
        #expect(file.length >= 96_000 - 4_800)
        _ = try await writer.finish()
    }

    @Test func droppedFramesBecomeSilenceAndKeepCount() async throws {
        let streams = streams(capacity: 10_000)
        let writer = AACRecordingWriter(chunkFrames: 4_800)
        try await writer.start(streams: streams, plan: .separate(microphone: url("mic.aac"), system: url("system.aac")))
        produce(streams, frames: 6_000, micAmplitude: 0.5, left: 0.5)
        await writer.drainAvailable()
        // Does not fit into the 10 000-frame rings: dropped by both sources.
        produce(streams, from: 6_000, frames: 12_000, micAmplitude: 0.5, left: 0.5)
        produce(streams, from: 18_000, frames: 2_000, micAmplitude: 0.5, left: 0.5)
        let result = try await writer.finish()
        #expect(result.streams.map(\.frames) == [20_000, 20_000])
    }

    @Test func unwritableDestinationFailsToStart() async {
        let missing = directory.appending(path: "missing/folder/mixed.aac")
        let writer = AACRecordingWriter()
        await #expect(throws: RecordingWriterError.cannotCreateFile(missing)) {
            try await writer.start(streams: streams(), plan: .mixed(missing))
        }
    }
}
