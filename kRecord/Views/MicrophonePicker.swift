import SwiftUI

/// The microphone choice shared by the main window and the Settings window: both edit the same
/// setting (main-window spec). A remembered microphone that is unplugged stays listed, marked
/// unavailable, so the selection is kept for when it returns (audio-capture spec).
struct MicrophonePicker: View {
    let settings: SettingsStore
    let devices: AudioDeviceCatalog
    let isLocked: Bool

    var body: some View {
        Picker("Microphone", selection: selection) {
            Text("System Default").tag(String?.none)
            ForEach(devices.inputDevices) { device in
                Text(verbatim: device.name).tag(Optional(device.uid))
            }
            if let missing = unavailableSelection {
                Text(verbatim: String(localized: "\(missing.name) (unavailable)")).tag(Optional(missing.uid))
            }
        }
        .disabled(isLocked)
    }

    private var selection: Binding<String?> {
        Binding(
            get: { settings.inputDeviceUID },
            set: { uid in
                settings.selectMicrophone(uid.flatMap { devices.device(forUID: $0) })
            })
    }

    /// The selected microphone when it is not connected.
    private var unavailableSelection: (uid: String, name: String)? {
        guard let uid = settings.inputDeviceUID, devices.device(forUID: uid) == nil else { return nil }
        return (uid, settings.inputDeviceName ?? uid)
    }
}
