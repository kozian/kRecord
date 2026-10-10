import AudioToolbox
import Foundation

struct FinalizationRequest: Equatable, Sendable {
    var streams: [RecordedStream]
    var saveAsM4A: Bool
}

enum FinalizerError: Error, Equatable, Sendable {
    case cannotRepackage(URL)
}

/// Turns the `.aac` streams of a stopped recording into the final files (design D5).
protocol Finalizer: Sendable {
    /// Returns the final files. On failure every `.aac` stream is kept.
    func finalize(_ request: FinalizationRequest) async throws(FinalizerError) -> [URL]
}

/// Repackages AAC packets from ADTS into `.m4a` without re-encoding.
struct AudioFinalizer: Finalizer {
    @concurrent
    func finalize(_ request: FinalizationRequest) async throws(FinalizerError) -> [URL] {
        guard request.saveAsM4A else { return request.streams.map(\.url) }

        var created: [URL] = []
        do throws(FinalizerError) {
            for stream in request.streams {
                let destination = stream.url.deletingPathExtension().appendingPathExtension(AACEncoding.containerExtension)
                created.append(destination)
                try Self.repackage(stream.url, to: destination, validFrames: stream.frames)
            }
        } catch {
            // Keep the playable streams; remove partial containers.
            created.forEach { try? FileManager.default.removeItem(at: $0) }
            throw error
        }
        request.streams.forEach { try? FileManager.default.removeItem(at: $0.url) }
        return created
    }

    /// Copies every AAC packet of the ADTS file `source` into a new `.m4a` at `destination`, with the
    /// encoder priming and the exact frame count in its packet table so players trim them.
    static func repackage(_ source: URL, to destination: URL, validFrames: Int) throws(FinalizerError) {
        var input: AudioFileID?
        guard AudioFileOpenURL(source as CFURL, .readPermission, kAudioFileAAC_ADTSType, &input) == noErr,
              let input else { throw .cannotRepackage(source) }
        defer { AudioFileClose(input) }

        var format = AudioStreamBasicDescription()
        var packetCount: UInt64 = 0
        var maxPacketSize: UInt32 = 0
        guard getProperty(input, kAudioFilePropertyDataFormat, &format),
              getProperty(input, kAudioFilePropertyAudioDataPacketCount, &packetCount),
              getProperty(input, kAudioFilePropertyMaximumPacketSize, &maxPacketSize)
        else { throw .cannotRepackage(source) }

        var output: AudioFileID?
        guard AudioFileCreateWithURL(destination as CFURL, kAudioFileM4AType, &format, .eraseFile, &output) == noErr,
              let output else { throw .cannotRepackage(destination) }
        var closed = false
        defer { if !closed { AudioFileClose(output) } }

        var cookieSize: UInt32 = 0
        if AudioFileGetPropertyInfo(input, kAudioFilePropertyMagicCookieData, &cookieSize, nil) == noErr, cookieSize > 0 {
            var cookie = [UInt8](repeating: 0, count: Int(cookieSize))
            guard AudioFileGetProperty(input, kAudioFilePropertyMagicCookieData, &cookieSize, &cookie) == noErr,
                  AudioFileSetProperty(output, kAudioFilePropertyMagicCookieData, cookieSize, cookie) == noErr
            else { throw .cannotRepackage(destination) }
        }

        let batch: UInt32 = 512
        var data = [UInt8](repeating: 0, count: Int(batch * max(maxPacketSize, 1)))
        var descriptions = [AudioStreamPacketDescription](repeating: .init(), count: Int(batch))
        var position: Int64 = 0
        while position < Int64(packetCount) {
            var bytes = UInt32(data.count)
            var packets = batch
            let status = AudioFileReadPacketData(input, false, &bytes, &descriptions, position, &packets, &data)
            if packets == 0 {
                guard status == noErr || status == kAudioFileEndOfFileError else { throw .cannotRepackage(source) }
                break
            }
            guard AudioFileWritePackets(output, false, bytes, &descriptions, position, &packets, data) == noErr else {
                throw .cannotRepackage(destination)
            }
            position += Int64(packets)
        }

        let totalFrames = Int64(position) * Int64(AACEncoding.framesPerPacket)
        let priming = Int64(AACEncoding.primingFrames)
        let valid = min(Int64(validFrames), max(totalFrames - priming, 0))
        var table = AudioFilePacketTableInfo(mNumberValidFrames: valid, mPrimingFrames: Int32(priming),
                                             mRemainderFrames: Int32(max(totalFrames - priming - valid, 0)))
        guard AudioFileSetProperty(output, kAudioFilePropertyPacketTableInfo,
                                   UInt32(MemoryLayout<AudioFilePacketTableInfo>.size), &table) == noErr
        else { throw .cannotRepackage(destination) }

        closed = true
        guard AudioFileClose(output) == noErr else { throw .cannotRepackage(destination) }
    }

    private static func getProperty<T: BitwiseCopyable>(_ file: AudioFileID, _ property: AudioFilePropertyID, _ value: inout T) -> Bool {
        var size = UInt32(MemoryLayout<T>.size)
        return AudioFileGetProperty(file, property, &size, &value) == noErr
    }
}
