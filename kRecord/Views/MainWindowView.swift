import SwiftUI

/// The primary window: record button, elapsed time, level meters, microphone choice, and the
/// permission and error messages (main-window spec).
struct MainWindowView: View {
    let model: AppModel

    private var session: RecordingSession { model.session }

    var body: some View {
        VStack(spacing: 18) {
            messages

            Text(verbatim: session.formattedElapsedTime)
                .font(.system(size: 46, weight: .light, design: .rounded))
                .monospacedDigit()
                .accessibilityLabel(Text("Elapsed time"))

            recordButton

            VStack(spacing: 10) {
                LabeledLevelMeter(title: "Microphone level", value: session.levels.microphone.meterValue())
                LabeledLevelMeter(title: "System audio level", value: session.levels.system.meterValue())
            }

            LabeledContent("Microphone") {
                MicrophonePicker(settings: model.settings, devices: model.devices,
                                 isLocked: model.recordingSettingsAreLocked)
                    .labelsHidden()
            }
        }
        .padding(20)
        .frame(width: 360)
    }

    // MARK: Record button

    private var recordButton: some View {
        Button {
            Task { await model.toggleRecording() }
        } label: {
            HStack(spacing: 8) {
                switch session.state {
                case .idle:
                    Image(systemName: "record.circle")
                    Text("Record")
                case .starting:
                    ProgressView().controlSize(.small)
                    Text("Starting…")
                case .recording:
                    Image(systemName: "stop.fill")
                    Text("Stop")
                case .finishing:
                    ProgressView().controlSize(.small)
                    Text("Saving…")
                }
            }
            .font(.title3.weight(.semibold))
            .frame(maxWidth: .infinity, minHeight: 32)
        }
        .buttonStyle(.borderedProminent)
        .tint(session.isRecording ? .gray : .red)
        .controlSize(.large)
        .disabled(!model.canToggleRecording)
    }

    // MARK: Messages

    @ViewBuilder
    private var messages: some View {
        if let error = session.lastError {
            Banner(systemImage: "exclamationmark.octagon.fill", tint: .red, message: Text(verbatim: error.message),
                   onDismiss: { session.dismissError() })
        }
        if !model.permissions.canRecord {
            Banner(systemImage: "mic.slash.fill", tint: .red,
                   message: Text("kRecord can't record: microphone and system audio access are both off."),
                   actionTitle: "Open System Settings", action: { model.permissions.openSettings(.microphone) })
        } else if model.permissions.microphoneIsBlocked {
            Banner(systemImage: "mic.slash.fill", tint: .orange,
                   message: Text("Microphone access is off, so your voice won't be recorded."),
                   actionTitle: "Open System Settings", action: { model.permissions.openSettings(.microphone) })
        }
        if session.lastResult?.systemAudioSilent == true {
            Banner(systemImage: "speaker.slash.fill", tint: .yellow,
                   message: Text("No system audio was captured. It may be blocked in Privacy & Security settings."),
                   actionTitle: "Open System Settings", action: { model.permissions.openSettings(.systemAudio) },
                   onDismiss: { session.dismissResult() })
        }
    }
}
