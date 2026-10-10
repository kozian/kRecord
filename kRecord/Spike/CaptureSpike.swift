#if DEBUG
// Throwaway capture spike (tasks 2.1 / 2.2). Not production code: removed once the
// capture engine (group 6) exists.
//
// Run: open kRecord.app --args -KRSpike aggregate|voice [-KRSpikeSeconds 10]
// Output: <real ~/Music>/kRecord/spike-<mode>-{mic,system}.caf and spike.log

import AVFoundation
import CoreAudio
import Foundation

enum CaptureSpike {
    static func runIfRequested() {
        guard let mode = UserDefaults.standard.string(forKey: "KRSpike") else { return }
        let seconds = max(1, UserDefaults.standard.integer(forKey: "KRSpikeSeconds") == 0
            ? 10 : UserDefaults.standard.integer(forKey: "KRSpikeSeconds"))
        Task.detached {
            let log = SpikeLog()
            do {
                log.write("=== spike mode=\(mode) seconds=\(seconds) home=\(NSHomeDirectory())")
                let dir = try spikeDirectory(log: log)
                let micGranted = await AVCaptureDevice.requestAccess(for: .audio)
                log.write("mic permission granted=\(micGranted) status=\(AVCaptureDevice.authorizationStatus(for: .audio).rawValue)")
                switch mode {
                case "voice":
                    try await runVoiceProcessing(seconds: seconds, dir: dir, log: log)
                default:
                    try await runAggregate(seconds: seconds, dir: dir, log: log)
                }
                log.write("=== done")
            } catch {
                log.write("ERROR: \(error)")
            }
            await MainActor.run { exit(0) }
        }
    }

    // MARK: - Paths

    static func realHomeDirectory() -> URL {
        if let pw = getpwuid(getuid()), let dir = pw.pointee.pw_dir {
            return URL(fileURLWithPath: String(cString: dir), isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
    }

    static func spikeDirectory(log: SpikeLog) throws -> URL {
        let dir = realHomeDirectory().appending(path: "Music/kRecord", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let probe = dir.appending(path: ".probe")
        try Data("x".utf8).write(to: probe)
        try FileManager.default.removeItem(at: probe)
        log.write("destination writable: \(dir.path)")
        log.attach(to: dir)
        return dir
    }

    // MARK: - Aggregate (mic + tap) mode, D1/D2

    static func runAggregate(seconds: Int, dir: URL, log: SpikeLog) async throws {
        let inputID = try HAL.defaultDevice(kAudioHardwarePropertyDefaultInputDevice)
        let inputUID = try HAL.string(inputID, kAudioDevicePropertyDeviceUID)
        log.write("default input: id=\(inputID) uid=\(inputUID) name=\(try HAL.string(inputID, kAudioObjectPropertyName)) rate=\(try HAL.sampleRate(inputID))")

        let outputID = try HAL.defaultDevice(kAudioHardwarePropertyDefaultOutputDevice)
        let outputUID = try HAL.string(outputID, kAudioDevicePropertyDeviceUID)
        log.write("default output (clock): uid=\(outputUID) name=\(try HAL.string(outputID, kAudioObjectPropertyName))")

        let defaults = UserDefaults.standard
        let clockIsMic = defaults.string(forKey: "KRSpikeClock") == "mic"
        let tapDrift = defaults.object(forKey: "KRSpikeTapDrift") as? Bool ?? true
        let keepAlive = defaults.bool(forKey: "KRSpikeKeepAlive")
        log.write("options: clock=\(clockIsMic ? "mic" : "output") tapDrift=\(tapDrift) keepAlive=\(keepAlive)")

        var keepAliveEngine: AVAudioEngine?
        if keepAlive {
            let engine = AVAudioEngine()
            let format = engine.outputNode.inputFormat(forBus: 0)
            let source = AVAudioSourceNode { isSilence, _, _, bufferList in
                for buffer in UnsafeMutableAudioBufferListPointer(bufferList) {
                    if let data = buffer.mData { memset(data, 0, Int(buffer.mDataByteSize)) }
                }
                isSilence.pointee = false
                return noErr
            }
            engine.attach(source)
            engine.connect(source, to: engine.mainMixerNode, format: format)
            try engine.start()
            keepAliveEngine = engine
            log.write("keep-alive silent output engine started")
        }
        defer { keepAliveEngine?.stop() }

        let tap = try SpikeTap(log: log)
        defer { tap.destroy() }

        let micSub: [String: Any] = [kAudioSubDeviceUIDKey: inputUID, kAudioSubDeviceDriftCompensationKey: !clockIsMic]
        let outSub: [String: Any] = [kAudioSubDeviceUIDKey: outputUID, kAudioSubDeviceDriftCompensationKey: clockIsMic]

        // Output device is the clock: running the aggregate runs the output device, so the tap
        // delivers IO even when nothing is playing. The mic is drift-compensated against it.
        let description: [String: Any] = [
            kAudioAggregateDeviceNameKey: "kRecord Spike",
            kAudioAggregateDeviceUIDKey: "com.kozian.kRecord.spike.\(UUID().uuidString)",
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceMainSubDeviceKey: clockIsMic ? inputUID : outputUID,
            kAudioAggregateDeviceSubDeviceListKey: clockIsMic ? [micSub] : [outSub, micSub],
            kAudioAggregateDeviceTapListKey: [[
                kAudioSubTapUIDKey: tap.uuid.uuidString,
                kAudioSubTapDriftCompensationKey: tapDrift,
            ]],
            kAudioAggregateDeviceTapAutoStartKey: true,
        ]
        // Aggregate input buffers: sub-devices' input streams in list order, then the tap.
        let outputInputs = clockIsMic ? 0 : HAL.inputStreamCount(outputID)
        let micInputs = HAL.inputStreamCount(inputID)
        let recorder = SpikeRecorder(capacityFrames: (seconds + 2) * 48_000,
                                     micIndex: outputInputs, tapIndex: outputInputs + micInputs)
        log.write("buffer indices: mic=\(outputInputs) tap=\(outputInputs + micInputs)")
        try await runAggregateIO(description: description, seconds: seconds, recorder: recorder, log: log)
        try recorder.writeFiles(dir: dir, prefix: "spike-aggregate", log: log)
    }

    // MARK: - Voice processing mode, D6

    static func runVoiceProcessing(seconds: Int, dir: URL, log: SpikeLog) async throws {
        let outputID = try HAL.defaultDevice(kAudioHardwarePropertyDefaultOutputDevice)
        let outputUID = try HAL.string(outputID, kAudioDevicePropertyDeviceUID)
        log.write("default output: uid=\(outputUID) name=\(try HAL.string(outputID, kAudioObjectPropertyName))")

        let engine = AVAudioEngine()
        let input = engine.inputNode
        try input.setVoiceProcessingEnabled(true)
        input.voiceProcessingOtherAudioDuckingConfiguration =
            AVAudioVoiceProcessingOtherAudioDuckingConfiguration(enableAdvancedDucking: false, duckingLevel: .min)
        let vpFormat = input.outputFormat(forBus: 0)
        log.write("voice processing input format: \(vpFormat)")

        let micRecorder = SpikeMonoCollector(capacityFrames: (seconds + 2) * Int(vpFormat.sampleRate))
        input.installTap(onBus: 0, bufferSize: 1024, format: vpFormat) { buffer, _ in
            micRecorder.append(buffer)
        }

        let tap = try SpikeTap(log: log)
        defer { tap.destroy() }
        let description: [String: Any] = [
            kAudioAggregateDeviceNameKey: "kRecord Spike VP",
            kAudioAggregateDeviceUIDKey: "com.kozian.kRecord.spike.vp.\(UUID().uuidString)",
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outputUID]],
            kAudioAggregateDeviceTapListKey: [[
                kAudioSubTapUIDKey: tap.uuid.uuidString,
                kAudioSubTapDriftCompensationKey: true,
            ]],
            kAudioAggregateDeviceTapAutoStartKey: true,
        ]
        let outputInputs = HAL.inputStreamCount(outputID)
        try engine.start()
        let recorder = SpikeRecorder(capacityFrames: (seconds + 2) * 48_000, micIndex: nil,
                                     tapIndex: HAL.inputStreamCount(outputID))
        log.write("output input streams before/after VP start: \(outputInputs)/\(HAL.inputStreamCount(outputID))")
        log.write("AVAudioEngine started with voice processing")
        try await runAggregateIO(description: description, seconds: seconds, recorder: recorder, log: log)
        engine.stop()
        input.removeTap(onBus: 0)
        try recorder.writeFiles(dir: dir, prefix: "spike-voice-tap", log: log)
        try micRecorder.write(to: dir.appending(path: "spike-voice-mic.caf"), sampleRate: vpFormat.sampleRate, log: log)
    }

    // MARK: - Shared IOProc runner

    static func runAggregateIO(description: [String: Any], seconds: Int,
                               recorder: SpikeRecorder, log: SpikeLog) async throws {
        var aggregateID = AudioObjectID(kAudioObjectUnknown)
        try HAL.check(AudioHardwareCreateAggregateDevice(description as CFDictionary, &aggregateID),
                      "AudioHardwareCreateAggregateDevice")
        defer { AudioHardwareDestroyAggregateDevice(aggregateID) }
        log.write("aggregate id=\(aggregateID) rate=\((try? HAL.sampleRate(aggregateID)) ?? -1)")
        log.write("aggregate input streams: \(HAL.streamConfiguration(aggregateID))")

        var procID: AudioDeviceIOProcID?
        let queue = DispatchQueue(label: "kRecord.spike.io", qos: .userInteractive)
        try HAL.check(AudioDeviceCreateIOProcIDWithBlock(&procID, aggregateID, queue) { _, input, inputTime, _, _ in
            recorder.ioProc(input, time: inputTime)
        }, "AudioDeviceCreateIOProcIDWithBlock")
        guard let procID else { throw SpikeError.message("no IOProc") }
        defer { AudioDeviceDestroyIOProcID(aggregateID, procID) }

        try HAL.check(AudioDeviceStart(aggregateID, procID), "AudioDeviceStart")
        log.write("IO started; recording \(seconds) s")
        try await Task.sleep(for: .seconds(seconds))
        try HAL.check(AudioDeviceStop(aggregateID, procID), "AudioDeviceStop")
        try await Task.sleep(for: .milliseconds(200))
        log.write("IO stopped: callbacks=\(recorder.callbacks) layout=\(recorder.firstLayout) " +
                  "micFrames=\(recorder.micFrames) systemFrames=\(recorder.systemFrames) " +
                  "firstSampleTime=\(recorder.firstSampleTime) lastSampleTime=\(recorder.lastSampleTime) overflow=\(recorder.overflow)")
    }
}

// MARK: - Tap

final class SpikeTap {
    let id: AudioObjectID
    let uuid: UUID

    init(log: SpikeLog) throws {
        let description = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
        description.uuid = UUID()
        description.name = "kRecord Spike Tap"
        description.isPrivate = true
        description.muteBehavior = .unmuted
        var tapID = AudioObjectID(kAudioObjectUnknown)
        try HAL.check(AudioHardwareCreateProcessTap(description, &tapID), "AudioHardwareCreateProcessTap")
        id = tapID
        uuid = description.uuid
        var format = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        var address = AudioObjectPropertyAddress(mSelector: kAudioTapPropertyFormat,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        let status = AudioObjectGetPropertyData(tapID, &address, 0, nil, &size, &format)
        log.write("tap id=\(tapID) uuid=\(uuid) formatStatus=\(status) rate=\(format.mSampleRate) " +
                  "channels=\(format.mChannelsPerFrame) bits=\(format.mBitsPerChannel) flags=\(format.mFormatFlags)")
    }

    func destroy() {
        AudioHardwareDestroyProcessTap(id)
    }
}

// MARK: - Recorder (preallocated; IOProc writes, main reads after stop)

final class SpikeRecorder: @unchecked Sendable {
    private let capacity: Int
    private let mic: UnsafeMutablePointer<Float>
    private let system: UnsafeMutablePointer<Float> // interleaved stereo
    private(set) var micFrames = 0
    private(set) var systemFrames = 0
    private(set) var callbacks = 0
    private(set) var overflow = false
    private(set) var firstSampleTime: Double = -1
    private(set) var lastSampleTime: Double = -1
    private(set) var firstLayout = ""
    private let micIndex: Int?
    private let tapIndex: Int

    init(capacityFrames: Int, micIndex: Int?, tapIndex: Int) {
        capacity = capacityFrames
        self.micIndex = micIndex
        self.tapIndex = tapIndex
        mic = .allocate(capacity: capacityFrames)
        mic.initialize(repeating: 0, count: capacityFrames)
        system = .allocate(capacity: capacityFrames * 2)
        system.initialize(repeating: 0, count: capacityFrames * 2)
    }

    deinit {
        mic.deallocate()
        system.deallocate()
    }

    func ioProc(_ input: UnsafePointer<AudioBufferList>, time: UnsafePointer<AudioTimeStamp>) {
        let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
        if callbacks == 0 {
            firstSampleTime = time.pointee.mSampleTime
            // String building on the IO thread is acceptable only in this spike.
            firstLayout = buffers.map { "\($0.mNumberChannels)ch/\($0.mDataByteSize)B" }.joined(separator: ",")
        }
        callbacks += 1
        lastSampleTime = time.pointee.mSampleTime
        guard tapIndex < buffers.count else { return }
        let tapBuffer = buffers[tapIndex]
        guard tapBuffer.mNumberChannels == 2,
              let tapData = tapBuffer.mData?.assumingMemoryBound(to: Float.self) else { return }
        let frames = Int(tapBuffer.mDataByteSize) / (MemoryLayout<Float>.size * 2)
        if systemFrames + frames <= capacity {
            (system + systemFrames * 2).update(from: tapData, count: frames * 2)
            systemFrames += frames
        } else {
            overflow = true
        }
        if let micIndex, micIndex < buffers.count,
           let micData = buffers[micIndex].mData?.assumingMemoryBound(to: Float.self) {
            let channels = Int(max(1, buffers[micIndex].mNumberChannels))
            let micCount = Int(buffers[micIndex].mDataByteSize) / (MemoryLayout<Float>.size * channels)
            if micFrames + micCount <= capacity {
                for i in 0..<micCount { mic[micFrames + i] = micData[i * channels] }
                micFrames += micCount
            }
        }
    }

    func writeFiles(dir: URL, prefix: String, log: SpikeLog) throws {
        if micFrames > 0 {
            try SpikeIO.writeCAF(url: dir.appending(path: "\(prefix)-mic.caf"), channels: [mic],
                                 interleavedStride: 1, frames: micFrames, sampleRate: 48_000, log: log)
        }
        try SpikeIO.writeCAF(url: dir.appending(path: "\(prefix)-system.caf"), channels: [system, system + 1],
                             interleavedStride: 2, frames: systemFrames, sampleRate: 48_000, log: log)
    }
}

final class SpikeMonoCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var channels: [[Float]] = []

    init(capacityFrames: Int) {}

    func append(_ buffer: AVAudioPCMBuffer) {
        guard let data = buffer.floatChannelData else { return }
        let count = Int(buffer.frameLength)
        lock.withLock {
            if channels.isEmpty { channels = Array(repeating: [], count: Int(buffer.format.channelCount)) }
            for c in channels.indices {
                channels[c].append(contentsOf: UnsafeBufferPointer(start: data[c], count: count))
            }
        }
    }

    /// Writes every voice-processing output channel to its own mono CAF (`<name>-chN.caf`).
    func write(to url: URL, sampleRate: Double, log: SpikeLog) throws {
        try lock.withLock {
            for c in channels.indices {
                let channelURL = url.deletingLastPathComponent()
                    .appending(path: url.deletingPathExtension().lastPathComponent + "-ch\(c).caf")
                try channels[c].withUnsafeMutableBufferPointer { buf in
                    try SpikeIO.writeCAF(url: channelURL, channels: [buf.baseAddress!], interleavedStride: 1,
                                         frames: buf.count, sampleRate: sampleRate, log: log)
                }
            }
        }
    }
}

enum SpikeIO {
    static func writeCAF(url: URL, channels: [UnsafeMutablePointer<Float>], interleavedStride: Int,
                         frames: Int, sampleRate: Double, log: SpikeLog) throws {
        try? FileManager.default.removeItem(at: url)
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: channels.count,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
        ]
        let file = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: AVAudioChannelCount(channels.count)),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(max(frames, 1))),
              let out = buffer.floatChannelData else { throw SpikeError.message("buffer alloc") }
        var peaks: [Float] = []
        for (c, src) in channels.enumerated() {
            var peak: Float = 0
            for i in 0..<frames {
                let s = src[i * interleavedStride]
                out[c][i] = s
                peak = max(peak, abs(s))
            }
            peaks.append(peak)
        }
        buffer.frameLength = AVAudioFrameCount(frames)
        try file.write(from: buffer)
        log.write("wrote \(url.lastPathComponent): frames=\(frames) (\(Double(frames) / sampleRate) s) peaks=\(peaks)")
    }
}

// MARK: - HAL helpers

enum SpikeError: Error { case message(String), status(String, OSStatus) }

enum HAL {
    static func check(_ status: OSStatus, _ what: String) throws {
        if status != noErr { throw SpikeError.status(what, status) }
    }

    static func address(_ selector: AudioObjectPropertySelector,
                        _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    static func defaultDevice(_ selector: AudioObjectPropertySelector) throws -> AudioObjectID {
        var addr = address(selector)
        var id = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        try check(AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &id), "default device")
        return id
    }

    static func string(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) throws -> String {
        var addr = address(selector)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        try check(AudioObjectGetPropertyData(object, &addr, 0, nil, &size, &value), "string property")
        return value?.takeRetainedValue() as String? ?? ""
    }

    static func sampleRate(_ object: AudioObjectID) throws -> Double {
        var addr = address(kAudioDevicePropertyNominalSampleRate)
        var rate: Float64 = 0
        var size = UInt32(MemoryLayout<Float64>.size)
        try check(AudioObjectGetPropertyData(object, &addr, 0, nil, &size, &rate), "sample rate")
        return rate
    }

    static func inputStreamCount(_ device: AudioObjectID) -> Int {
        var addr = address(kAudioDevicePropertyStreams, kAudioObjectPropertyScopeInput)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(device, &addr, 0, nil, &size) == noErr else { return 0 }
        return Int(size) / MemoryLayout<AudioStreamID>.size
    }

    static func streamConfiguration(_ device: AudioObjectID) -> String {
        var addr = address(kAudioDevicePropertyStreamConfiguration, kAudioObjectPropertyScopeInput)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(device, &addr, 0, nil, &size) == noErr, size > 0 else { return "?" }
        let raw = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: 16)
        defer { raw.deallocate() }
        guard AudioObjectGetPropertyData(device, &addr, 0, nil, &size, raw) == noErr else { return "?" }
        let list = UnsafeMutableAudioBufferListPointer(raw.assumingMemoryBound(to: AudioBufferList.self))
        return list.map { "\($0.mNumberChannels)ch" }.joined(separator: ",")
    }
}

// MARK: - Log

final class SpikeLog: @unchecked Sendable {
    private let lock = NSLock()
    private var url: URL?
    private var pending: [String] = []

    func attach(to dir: URL) {
        lock.withLock {
            url = dir.appending(path: "spike.log")
            for line in pending { append(line) }
            pending.removeAll()
        }
    }

    func write(_ message: String) {
        let line = "\(Date().formatted(.iso8601)) \(message)"
        NSLog("[spike] %@", message)
        lock.withLock {
            if url == nil { pending.append(line) } else { append(line) }
        }
    }

    private func append(_ line: String) {
        guard let url else { return }
        let data = Data((line + "\n").utf8)
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        } else {
            try? data.write(to: url)
        }
    }
}
#endif
