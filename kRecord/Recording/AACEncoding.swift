import AudioToolbox
import Foundation

/// The one recording encoding (recording-output spec, design D5): AAC at 48 kHz and a constant
/// 128 kbps, written live as an ADTS `.aac` stream and optionally repackaged into `.m4a`.
enum AACEncoding {
    static let sampleRate: Double = 48_000
    /// The spec requires at least 128 kbps; used for mono and stereo.
    static let bitRate: UInt32 = 128_000
    /// Frames per AAC packet.
    static let framesPerPacket = 1_024
    /// Encoder delay of Apple's AAC-LC encoder. ADTS cannot store it; the `.m4a` packet table trims it.
    static let primingFrames = 2_112

    static let streamExtension = "aac"
    static let containerExtension = "m4a"
}

/// Encodes float audio into an ADTS `.aac` file through `ExtAudioFile`, which also converts the
/// capture sample rate to 48 kHz when they differ.
final class AACStreamFile {
    let url: URL
    let channels: Int
    let inputSampleRate: Double
    /// Input frames encoded so far, at `inputSampleRate`.
    private(set) var inputFramesWritten = 0
    private var file: ExtAudioFileRef?
    private let bufferList: UnsafeMutableAudioBufferListPointer
    private let capacity: Int

    /// Non-interleaved input buffers, one per channel, each `capacity` frames long.
    let channelData: [UnsafeMutablePointer<Float>]

    /// Frames in the encoded stream at 48 kHz (excluding encoder priming).
    var encodedFrames: Int {
        Int((Double(inputFramesWritten) * AACEncoding.sampleRate / inputSampleRate).rounded())
    }

    init(url: URL, channels: Int, inputSampleRate: Double, capacity: Int) throws(RecordingWriterError) {
        self.url = url
        self.channels = channels
        self.inputSampleRate = inputSampleRate
        self.capacity = capacity

        var fileFormat = AudioStreamBasicDescription(
            mSampleRate: AACEncoding.sampleRate, mFormatID: kAudioFormatMPEG4AAC, mFormatFlags: 0,
            mBytesPerPacket: 0, mFramesPerPacket: UInt32(AACEncoding.framesPerPacket), mBytesPerFrame: 0,
            mChannelsPerFrame: UInt32(channels), mBitsPerChannel: 0, mReserved: 0)
        var file: ExtAudioFileRef?
        guard ExtAudioFileCreateWithURL(url as CFURL, kAudioFileAAC_ADTSType, &fileFormat, nil,
                                        AudioFileFlags.eraseFile.rawValue, &file) == noErr, let file else {
            throw .cannotCreateFile(url)
        }
        self.file = file

        var clientFormat = AudioStreamBasicDescription(
            mSampleRate: inputSampleRate, mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked | kAudioFormatFlagIsNonInterleaved,
            mBytesPerPacket: 4, mFramesPerPacket: 1, mBytesPerFrame: 4, mChannelsPerFrame: UInt32(channels),
            mBitsPerChannel: 32, mReserved: 0)
        channelData = (0..<channels).map { _ in
            let samples = UnsafeMutablePointer<Float>.allocate(capacity: capacity)
            samples.initialize(repeating: 0, count: capacity)
            return samples
        }
        bufferList = AudioBufferList.allocate(maximumBuffers: channels)
        guard ExtAudioFileSetProperty(file, kExtAudioFileProperty_ClientDataFormat,
                                      UInt32(MemoryLayout<AudioStreamBasicDescription>.size), &clientFormat) == noErr,
              Self.configureConstantBitRate(file)
        else {
            close()
            throw .cannotCreateFile(url)
        }
    }

    deinit {
        close()
        channelData.forEach { $0.deallocate() }
        bufferList.unsafeMutablePointer.deallocate()
    }

    /// Encodes the first `frames` frames of `channelData`.
    func write(frames: Int) throws(RecordingWriterError) {
        guard let file else { throw .writeFailed(url) }
        precondition(frames <= capacity)
        for channel in 0..<channels {
            bufferList[channel] = AudioBuffer(mNumberChannels: 1, mDataByteSize: UInt32(frames * 4),
                                              mData: channelData[channel])
        }
        guard ExtAudioFileWrite(file, UInt32(frames), bufferList.unsafePointer) == noErr else {
            throw .writeFailed(url)
        }
        inputFramesWritten += frames
    }

    func close() {
        if let file { ExtAudioFileDispose(file) }
        file = nil
    }

    private static func configureConstantBitRate(_ file: ExtAudioFileRef) -> Bool {
        var converter: AudioConverterRef?
        var size = UInt32(MemoryLayout<AudioConverterRef?>.size)
        guard ExtAudioFileGetProperty(file, kExtAudioFileProperty_AudioConverter, &size, &converter) == noErr,
              let converter else { return false }
        var mode = UInt32(kAudioCodecBitRateControlMode_Constant)
        var bitRate = AACEncoding.bitRate
        guard AudioConverterSetProperty(converter, kAudioCodecPropertyBitRateControlMode,
                                        UInt32(MemoryLayout<UInt32>.size), &mode) == noErr,
              AudioConverterSetProperty(converter, kAudioConverterEncodeBitRate,
                                        UInt32(MemoryLayout<UInt32>.size), &bitRate) == noErr
        else { return false }
        // Apply the converter changes to the file.
        // Setting a null configuration makes the file pick up the converter's new settings.
        var config: UnsafeRawPointer?
        return ExtAudioFileSetProperty(file, kExtAudioFileProperty_ConverterConfig,
                                       UInt32(MemoryLayout<UnsafeRawPointer?>.size), &config) == noErr
    }
}
