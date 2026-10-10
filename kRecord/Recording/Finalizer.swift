import AVFoundation
import Foundation

struct FinalizationRequest: Equatable, Sendable {
    var intermediates: IntermediateFiles
    /// `kRecord YYYY-MM-DD HH-mm-ss` of the recording.
    var baseName: String
    var destination: URL
    var format: OutputFormat
    var separateFiles: Bool
}

struct FinalizationResult: Equatable, Sendable {
    var outputs: [URL]
    /// System audio was captured but is entirely digital zero, which usually means the system audio
    /// recording permission is denied (permissions spec).
    var systemAudioSilent: Bool
}

enum FinalizerError: Error, Equatable, Sendable {
    case cannotReadIntermediate(URL)
    case cannotWriteOutput(URL)
}

/// Turns the intermediate files of a stopped recording into the final output (design D5).
protocol Finalizer: Sendable {
    func finalize(_ request: FinalizationRequest) async throws(FinalizerError) -> FinalizationResult
}

struct AudioFinalizer: Finalizer {
    /// Each source is mixed at -3 dB so that two loud sources rarely clip.
    static let mixGain: Float = 0.707_945_8
    static let chunkFrames: AVAudioFrameCount = 48_000

    @concurrent
    func finalize(_ request: FinalizationRequest) async throws(FinalizerError) -> FinalizationResult {
        let microphone = try request.intermediates.microphone.map { url throws(FinalizerError) in try SourceReader(url: url) }
        let system = try request.intermediates.system.map { url throws(FinalizerError) in try SourceReader(url: url) }

        var created: [URL] = []
        do {
            let outputs: [URL]
            if request.separateFiles {
                outputs = try encodeSeparately(microphone: microphone, system: system, request: request, created: &created)
            } else {
                outputs = try mix(microphone: microphone, system: system, request: request, created: &created)
            }
            for url in request.intermediates.all {
                try? FileManager.default.removeItem(at: url)
            }
            return FinalizationResult(outputs: outputs, systemAudioSilent: system.map { !$0.sawNonZeroSample } ?? false)
        } catch {
            // Keep the intermediates so no audio is lost; remove partial outputs.
            for url in created {
                try? FileManager.default.removeItem(at: url)
            }
            throw error
        }
    }

    // MARK: - Mixed

    private func mix(microphone: SourceReader?, system: SourceReader?, request: FinalizationRequest,
                     created: inout [URL]) throws(FinalizerError) -> [URL] {
        let url = FileNaming.uniqueURLs(in: request.destination, base: request.baseName, roles: [.mixed],
                                        fileExtension: request.format.fileExtension)[0]
        let output = try OutputWriter(url: url, format: request.format, channels: 2)
        created.append(url)

        let micBuffer = try microphone.map { _ throws(FinalizerError) in try Self.makeBuffer(channels: 1, url: url) }
        let systemBuffer = try system.map { _ throws(FinalizerError) in try Self.makeBuffer(channels: 2, url: url) }
        let mixed = try Self.makeBuffer(channels: 2, url: url)
        let gain = Self.mixGain

        while true {
            let micFrames = try micBuffer.map { buffer throws(FinalizerError) in try microphone!.read(into: buffer) } ?? 0
            let systemFrames = try systemBuffer.map { buffer throws(FinalizerError) in try system!.read(into: buffer) } ?? 0
            let frames = max(micFrames, systemFrames)
            guard frames > 0 else { break }

            let left = mixed.floatChannelData![0]
            let right = mixed.floatChannelData![1]
            for frame in 0..<frames {
                let mic = frame < micFrames ? micBuffer!.floatChannelData![0][frame] : 0
                let systemLeft = frame < systemFrames ? systemBuffer!.floatChannelData![0][frame] : 0
                let systemRight = frame < systemFrames ? systemBuffer!.floatChannelData![1][frame] : 0
                left[frame] = min(max(gain * (systemLeft + mic), -1), 1)
                right[frame] = min(max(gain * (systemRight + mic), -1), 1)
            }
            mixed.frameLength = AVAudioFrameCount(frames)
            try output.write(mixed)
        }
        output.close()
        return [url]
    }

    // MARK: - Separate

    private func encodeSeparately(microphone: SourceReader?, system: SourceReader?, request: FinalizationRequest,
                                  created: inout [URL]) throws(FinalizerError) -> [URL] {
        let sources: [(role: FileNaming.Role, reader: SourceReader, channels: Int)] =
            [microphone.map { (.microphone, $0, 1) }, system.map { (.system, $0, 2) }].compactMap { $0 }
        let urls = FileNaming.uniqueURLs(in: request.destination, base: request.baseName, roles: sources.map(\.role),
                                         fileExtension: request.format.fileExtension)
        for (source, url) in zip(sources, urls) {
            let output = try OutputWriter(url: url, format: request.format, channels: source.channels)
            created.append(url)
            let buffer = try Self.makeBuffer(channels: source.channels, url: url)
            while try source.reader.read(into: buffer) > 0 {
                try output.write(buffer)
            }
            output.close()
        }
        return urls
    }

    private static func makeBuffer(channels: Int, url: URL) throws(FinalizerError) -> AVAudioPCMBuffer {
        guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: OutputFormat.sampleRate,
                                         channels: AVAudioChannelCount(channels), interleaved: false),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunkFrames)
        else { throw .cannotWriteOutput(url) }
        return buffer
    }
}

// MARK: - Reading intermediates

/// Reads an intermediate file as 48 kHz float frames, resampling if it was captured at another rate.
private final class SourceReader {
    let url: URL
    private let file: AVAudioFile
    private let converter: AVAudioConverter?
    private let fileBuffer: AVAudioPCMBuffer
    private var endOfFile = false
    private(set) var sawNonZeroSample = false

    init(url: URL) throws(FinalizerError) {
        self.url = url
        guard let file = try? AVAudioFile(forReading: url),
              let fileBuffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                                                frameCapacity: AudioFinalizer.chunkFrames)
        else { throw .cannotReadIntermediate(url) }
        self.file = file
        self.fileBuffer = fileBuffer
        if file.processingFormat.sampleRate == OutputFormat.sampleRate {
            converter = nil
        } else {
            guard let target = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: OutputFormat.sampleRate,
                                             channels: file.processingFormat.channelCount, interleaved: false),
                  let converter = AVAudioConverter(from: file.processingFormat, to: target)
            else { throw .cannotReadIntermediate(url) }
            self.converter = converter
        }
    }

    /// Fills `buffer` (48 kHz float, same channel count as the file) and returns the frame count; 0 at the end.
    func read(into buffer: AVAudioPCMBuffer) throws(FinalizerError) -> Int {
        buffer.frameLength = 0
        if let converter {
            var error: NSError?
            let status = converter.convert(to: buffer, error: &error) { [self] packets, inputStatus in
                guard readFromFile(maxFrames: packets) else {
                    inputStatus.pointee = .endOfStream
                    return nil
                }
                inputStatus.pointee = .haveData
                return fileBuffer
            }
            if status == .error { throw .cannotReadIntermediate(url) }
        } else if readFromFile(maxFrames: buffer.frameCapacity) {
            let channels = Int(fileBuffer.format.channelCount)
            for channel in 0..<channels {
                buffer.floatChannelData![channel].update(from: fileBuffer.floatChannelData![channel],
                                                         count: Int(fileBuffer.frameLength))
            }
            buffer.frameLength = fileBuffer.frameLength
        }
        noteNonZero(buffer)
        return Int(buffer.frameLength)
    }

    /// Reads the next frames of the file into `fileBuffer`; `false` at the end of the file.
    private func readFromFile(maxFrames: AVAudioFrameCount) -> Bool {
        guard !endOfFile, file.framePosition < file.length else {
            endOfFile = true
            return false
        }
        do {
            try file.read(into: fileBuffer, frameCount: min(maxFrames, fileBuffer.frameCapacity))
        } catch {
            endOfFile = true
            return false
        }
        if fileBuffer.frameLength == 0 { endOfFile = true }
        return !endOfFile
    }

    private func noteNonZero(_ buffer: AVAudioPCMBuffer) {
        guard !sawNonZeroSample else { return }
        for channel in 0..<Int(buffer.format.channelCount) {
            let samples = buffer.floatChannelData![channel]
            for frame in 0..<Int(buffer.frameLength) where samples[frame] != 0 {
                sawNonZeroSample = true
                return
            }
        }
    }
}

// MARK: - Writing outputs

private final class OutputWriter {
    let url: URL
    private var file: AVAudioFile?

    init(url: URL, format: OutputFormat, channels: Int) throws(FinalizerError) {
        self.url = url
        do {
            file = try AVAudioFile(forWriting: url, settings: format.settings(channels: channels),
                                   commonFormat: .pcmFormatFloat32, interleaved: false)
        } catch {
            throw .cannotWriteOutput(url)
        }
    }

    func write(_ buffer: AVAudioPCMBuffer) throws(FinalizerError) {
        do {
            try file?.write(from: buffer)
        } catch {
            throw .cannotWriteOutput(url)
        }
    }

    func close() {
        file?.close()
        file = nil
    }
}
