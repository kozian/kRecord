import CoreAudio
import Foundation

/// Thin wrappers over the Core Audio HAL property API.
enum CoreAudioHAL {
    static let systemObject = AudioObjectID(kAudioObjectSystemObject)

    static func check(_ status: OSStatus, _ operation: String) throws(CaptureError) {
        if status != noErr { throw .coreAudio(operation: operation, status: status) }
    }

    static func address(_ selector: AudioObjectPropertySelector,
                        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    // MARK: Devices

    static func defaultInputDevice() -> AudioObjectID? {
        deviceProperty(kAudioHardwarePropertyDefaultInputDevice)
    }

    static func defaultOutputDevice() -> AudioObjectID? {
        deviceProperty(kAudioHardwarePropertyDefaultOutputDevice)
    }

    static func device(forUID uid: String) -> AudioObjectID? {
        var address = address(kAudioHardwarePropertyTranslateUIDToDevice)
        var cfUID = uid as CFString
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = withUnsafeMutablePointer(to: &cfUID) { qualifier in
            AudioObjectGetPropertyData(systemObject, &address, UInt32(MemoryLayout<CFString>.size), qualifier,
                                       &size, &device)
        }
        return status == noErr && device != kAudioObjectUnknown ? device : nil
    }

    static func allDevices() -> [AudioObjectID] {
        objectList(systemObject, kAudioHardwarePropertyDevices)
    }

    static func uid(of device: AudioObjectID) -> String? {
        string(device, kAudioDevicePropertyDeviceUID)
    }

    static func name(of device: AudioObjectID) -> String? {
        string(device, kAudioObjectPropertyName)
    }

    static func isAlive(_ device: AudioObjectID) -> Bool {
        var address = address(kAudioDevicePropertyDeviceIsAlive)
        var alive: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(device, &address, 0, nil, &size, &alive) == noErr && alive != 0
    }

    static func nominalSampleRate(of device: AudioObjectID) -> Double? {
        var address = address(kAudioDevicePropertyNominalSampleRate)
        var rate: Float64 = 0
        var size = UInt32(MemoryLayout<Float64>.size)
        return AudioObjectGetPropertyData(device, &address, 0, nil, &size, &rate) == noErr && rate > 0 ? rate : nil
    }

    static func inputStreams(of device: AudioObjectID) -> [AudioStreamID] {
        objectList(device, kAudioDevicePropertyStreams, scope: kAudioObjectPropertyScopeInput)
    }

    static func virtualFormat(of stream: AudioStreamID) -> AudioStreamBasicDescription? {
        var address = address(kAudioStreamPropertyVirtualFormat)
        var format = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        return AudioObjectGetPropertyData(stream, &address, 0, nil, &size, &format) == noErr ? format : nil
    }

    // MARK: Generic

    static func string(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
        var address = address(selector)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr,
              let value else { return nil }
        return value.takeRetainedValue() as String
    }

    static func objectList(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector,
                           scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> [AudioObjectID] {
        var address = address(selector, scope: scope)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(object, &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        var objects = [AudioObjectID](repeating: kAudioObjectUnknown, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &objects) == noErr else { return [] }
        return Array(objects.prefix(Int(size) / MemoryLayout<AudioObjectID>.size))
    }

    private static func deviceProperty(_ selector: AudioObjectPropertySelector) -> AudioObjectID? {
        var address = address(selector)
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(systemObject, &address, 0, nil, &size, &device)
        return status == noErr && device != kAudioObjectUnknown ? device : nil
    }
}
