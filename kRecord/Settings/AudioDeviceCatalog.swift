import CoreAudio
import Foundation
import Observation

/// A microphone the user can select.
struct InputDevice: Identifiable, Hashable, Sendable {
    /// Core Audio UID; stable across reconnects, unlike the numeric object ID.
    let uid: String
    let name: String

    var id: String { uid }
}

/// The input devices currently connected, kept up to date while devices come and go.
@MainActor
@Observable
final class AudioDeviceCatalog {
    private(set) var inputDevices: [InputDevice]

    @ObservationIgnored private let list: @Sendable () -> [InputDevice]
    @ObservationIgnored private var monitor: DeviceMonitor?

    /// - Parameters:
    ///   - list: enumerates the input devices; replaced in tests.
    ///   - observeChanges: refresh automatically when Core Audio reports device changes.
    init(list: @escaping @Sendable () -> [InputDevice] = AudioDeviceCatalog.systemInputDevices,
         observeChanges: Bool = true) {
        self.list = list
        inputDevices = list()
        guard observeChanges else { return }
        let monitor = DeviceMonitor { [weak self] in
            Task { @MainActor in self?.refresh() }
        }
        monitor.start()
        self.monitor = monitor
    }

    func refresh() {
        let devices = list()
        if devices != inputDevices { inputDevices = devices }
    }

    func device(forUID uid: String) -> InputDevice? {
        inputDevices.first { $0.uid == uid }
    }

    /// Input-capable devices, sorted by name. Aggregate devices are left out: capture builds its own
    /// aggregate, which cannot contain another one (and this hides kRecord's private aggregate).
    nonisolated static func systemInputDevices() -> [InputDevice] {
        CoreAudioHAL.allDevices()
            .filter { !CoreAudioHAL.inputStreams(of: $0).isEmpty }
            .filter { CoreAudioHAL.transportType(of: $0) != kAudioDeviceTransportTypeAggregate }
            .compactMap { device in
                guard let uid = CoreAudioHAL.uid(of: device), let name = CoreAudioHAL.name(of: device) else { return nil }
                return InputDevice(uid: uid, name: name)
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}
