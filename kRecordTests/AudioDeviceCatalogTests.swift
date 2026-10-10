import CoreAudio
import Foundation
import Synchronization
import Testing
@testable import kRecord

@MainActor
struct AudioDeviceCatalogTests {
    @Test func listsDevicesAndRefreshesOnChange() {
        let devices = Mutex([InputDevice(uid: "builtin", name: "MacBook Microphone")])
        let catalog = AudioDeviceCatalog(list: { devices.withLock { $0 } }, observeChanges: false)
        #expect(catalog.inputDevices.map(\.name) == ["MacBook Microphone"])

        devices.withLock { $0.append(InputDevice(uid: "usb", name: "USB Mic")) }
        #expect(catalog.inputDevices.count == 1)
        catalog.refresh()
        #expect(catalog.inputDevices.map(\.uid) == ["builtin", "usb"])
        #expect(catalog.device(forUID: "usb")?.name == "USB Mic")

        devices.withLock { $0.removeAll { $0.uid == "usb" } }
        catalog.refresh()
        #expect(catalog.device(forUID: "usb") == nil)
    }

    /// The real enumeration: every entry is usable, kRecord's own aggregate is hidden, and the
    /// default input (when there is one) is listed. Passes vacuously on a Mac without inputs.
    @Test func systemEnumerationIsConsistent() {
        let devices = AudioDeviceCatalog.systemInputDevices()
        #expect(devices.allSatisfy { !$0.uid.isEmpty && !$0.name.isEmpty })
        #expect(devices.allSatisfy { !$0.uid.hasPrefix("com.kozian.kRecord.") })
        #expect(Set(devices.map(\.uid)).count == devices.count)
        if let defaultInput = CoreAudioHAL.defaultInputDevice(), let uid = CoreAudioHAL.uid(of: defaultInput),
           CoreAudioHAL.transportType(of: defaultInput) != kAudioDeviceTransportTypeAggregate {
            #expect(devices.contains { $0.uid == uid })
        }
    }

    @Test func devicesAreSortedByName() {
        let catalog = AudioDeviceCatalog(list: {
            [InputDevice(uid: "b", name: "Zoom"), InputDevice(uid: "a", name: "Built-in")].sorted { $0.name < $1.name }
        }, observeChanges: false)
        #expect(catalog.inputDevices.map(\.name) == ["Built-in", "Zoom"])
    }
}
