// Audio device helper for hardware checks (see AGENTS.md, "Verifying audio on real hardware").
//
//     swiftc -O scripts/hw/audioctl.swift -o build/audioctl
//     build/audioctl                        # input devices, * = default input
//     build/audioctl outputs                # output devices, * = default output
//     build/audioctl set-input <name part>  # change the macOS default input
//     build/audioctl hold-aggregate <secs>  # a test input "kRecordTest Input" (aggregate of the first
//                                           # input device) that exists for <secs>, then is destroyed
import CoreAudio
import Foundation

func prop<T>(_ obj: AudioObjectID, _ sel: AudioObjectPropertySelector, _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal, _ def: T) -> T {
    var a = AudioObjectPropertyAddress(mSelector: sel, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    var v = def; var size = UInt32(MemoryLayout<T>.size)
    AudioObjectGetPropertyData(obj, &a, 0, nil, &size, &v); return v
}
func str(_ obj: AudioObjectID, _ sel: AudioObjectPropertySelector) -> String {
    var a = AudioObjectPropertyAddress(mSelector: sel, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    var v: Unmanaged<CFString>?; var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
    guard AudioObjectGetPropertyData(obj, &a, 0, nil, &size, &v) == noErr, let v else { return "" }
    return v.takeRetainedValue() as String
}
func devices() -> [AudioObjectID] {
    var a = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    var size: UInt32 = 0; AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil, &size)
    var ids = [AudioObjectID](repeating: 0, count: Int(size) / 4)
    AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil, &size, &ids); return ids
}
func inputs(_ d: AudioObjectID) -> Int {
    var a = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreams, mScope: kAudioObjectPropertyScopeInput, mElement: kAudioObjectPropertyElementMain)
    var size: UInt32 = 0; AudioObjectGetPropertyDataSize(d, &a, 0, nil, &size); return Int(size) / 4
}
let sys = AudioObjectID(kAudioObjectSystemObject)
let args = CommandLine.arguments
if args.count > 2, args[1] == "set-input" {
    guard var id = devices().first(where: { str($0, kAudioObjectPropertyName).localizedCaseInsensitiveContains(args[2]) && inputs($0) > 0 }) else { print("not found"); exit(1) }
    var a = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultInputDevice, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    let st = AudioObjectSetPropertyData(sys, &a, 0, nil, 4, &id)
    print("set default input -> \(str(id, kAudioObjectPropertyName)) status=\(st)")
} else if args.count == 1 {
    let din: AudioObjectID = prop(sys, kAudioHardwarePropertyDefaultInputDevice, kAudioObjectPropertyScopeGlobal, 0)
    for d in devices() where inputs(d) > 0 {
        let rate: Float64 = prop(d, kAudioDevicePropertyNominalSampleRate, kAudioObjectPropertyScopeGlobal, 0)
        print("\(d == din ? "*" : " ") \(d) '\(str(d, kAudioObjectPropertyName))' uid=\(str(d, kAudioDevicePropertyDeviceUID)) rate=\(Int(rate))")
    }
}
if args.count > 2, args[1] == "hold-aggregate" {
    guard let razer = devices().first(where: { inputs($0) > 0 && !str($0, kAudioDevicePropertyDeviceUID).hasPrefix("kRecordTest") }) else { exit(1) }
    let desc: [String: Any] = [kAudioAggregateDeviceNameKey: "kRecordTest Input", kAudioAggregateDeviceUIDKey: "kRecordTest.input",
        kAudioAggregateDeviceMainSubDeviceKey: str(razer, kAudioDevicePropertyDeviceUID),
        kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: str(razer, kAudioDevicePropertyDeviceUID)]]]
    var agg = AudioObjectID(0)
    print("create aggregate status=\(AudioHardwareCreateAggregateDevice(desc as CFDictionary, &agg)) id=\(agg)"); fflush(stdout)
    Thread.sleep(forTimeInterval: Double(args[2]) ?? 60)
    print("destroy status=\(AudioHardwareDestroyAggregateDevice(agg))")
}
if args.count > 1, args[1] == "outputs" {
    func outs(_ d: AudioObjectID) -> Int {
        var a = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreams, mScope: kAudioObjectPropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0; AudioObjectGetPropertyDataSize(d, &a, 0, nil, &size); return Int(size) / 4
    }
    let dout: AudioObjectID = prop(sys, kAudioHardwarePropertyDefaultOutputDevice, kAudioObjectPropertyScopeGlobal, 0)
    for d in devices() where outs(d) > 0 { print("\(d == dout ? "*" : " ") \(d) '\(str(d, kAudioObjectPropertyName))'") }
}
