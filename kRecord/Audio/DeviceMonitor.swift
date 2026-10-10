import CoreAudio
import Foundation

/// Watches the Core Audio device configuration and reports relevant changes (design D3):
/// devices appearing or disappearing, default input or output changes, and the watched input
/// device dying. Bursts of notifications are coalesced into one callback.
///
/// All mutable state is confined to `queue`, which is also where Core Audio delivers the listener
/// callbacks; that confinement is what makes the type safe to share.
final class DeviceMonitor: @unchecked Sendable {
    private struct Listener {
        let object: AudioObjectID
        let address: AudioObjectPropertyAddress
        let block: AudioObjectPropertyListenerBlock
    }

    private let queue = DispatchQueue(label: "com.kozian.kRecord.device-monitor")
    private let coalescingDelay: DispatchTimeInterval
    private let onChange: @Sendable () -> Void

    // Confined to `queue`.
    private var listeners: [Listener] = []
    private var watchedInput: Listener?
    private var pending: DispatchWorkItem?

    init(coalescingDelay: DispatchTimeInterval = .milliseconds(150), onChange: @escaping @Sendable () -> Void) {
        self.coalescingDelay = coalescingDelay
        self.onChange = onChange
    }

    func start() {
        queue.sync {
            for selector in [kAudioHardwarePropertyDevices, kAudioHardwarePropertyDefaultInputDevice,
                             kAudioHardwarePropertyDefaultOutputDevice] {
                if let listener = addListener(CoreAudioHAL.systemObject, selector) { listeners.append(listener) }
            }
        }
    }

    /// Also reports when `device` stops being alive (e.g. a USB microphone is unplugged).
    func watchInput(_ device: AudioObjectID?) {
        queue.sync {
            if let watchedInput { remove(watchedInput) }
            watchedInput = device.flatMap { addListener($0, kAudioDevicePropertyDeviceIsAlive) }
        }
    }

    func stop() {
        queue.sync {
            (listeners + [watchedInput].compactMap { $0 }).forEach(remove)
            listeners = []
            watchedInput = nil
            pending?.cancel()
            pending = nil
        }
    }

    // MARK: - Private (on `queue`)

    private func addListener(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> Listener? {
        var address = CoreAudioHAL.address(selector)
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in self?.scheduleChange() }
        guard AudioObjectAddPropertyListenerBlock(object, &address, queue, block) == noErr else { return nil }
        return Listener(object: object, address: address, block: block)
    }

    private func remove(_ listener: Listener) {
        var address = listener.address
        AudioObjectRemovePropertyListenerBlock(listener.object, &address, queue, listener.block)
    }

    private func scheduleChange() {
        pending?.cancel()
        let work = DispatchWorkItem { [onChange] in onChange() }
        pending = work
        queue.asyncAfter(deadline: .now() + coalescingDelay, execute: work)
    }
}
