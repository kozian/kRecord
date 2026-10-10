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

            VStack(spacing: 6) {
                recordButton
                if session.state == .idle, model.settings.enabledSources.isEmpty {
                    Text("Turn on the microphone or system audio to record.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            VStack(spacing: 10) {
                SourceLevelMeter(title: "Record microphone", isOn: sourceBinding(\.recordsMicrophone),
                                 isLocked: model.recordingSettingsAreLocked,
                                 value: session.levels.microphone.meterValue())
                SourceLevelMeter(title: "Record system audio", isOn: sourceBinding(\.recordsSystemAudio),
                                 isLocked: model.recordingSettingsAreLocked,
                                 value: session.levels.system.meterValue())
            }

            LabeledContent("Microphone") {
                MicrophonePicker(settings: model.settings, devices: model.devices,
                                 isLocked: model.recordingSettingsAreLocked)
                    .labelsHidden()
            }

            silentSystemAudioNote
        }
        .padding(20)
        .frame(width: 360)
    }

    private func sourceBinding(_ keyPath: ReferenceWritableKeyPath<SettingsStore, Bool>) -> Binding<Bool> {
        Binding(get: { model.settings[keyPath: keyPath] }, set: { model.settings[keyPath: keyPath] = $0 })
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
    }

    /// A quiet note, not a banner: an all-silent system track also happens when nothing played,
    /// so this only points at the permission as one possible cause (permissions spec).
    @ViewBuilder
    private var silentSystemAudioNote: some View {
        if session.lastResult?.systemAudioSilent == true {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: "speaker.slash")
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("The last recording has no system audio. It may be blocked in privacy settings.")
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Open System Settings") { model.permissions.openSettings(.systemAudio) }
                        .buttonStyle(.link)
                        .foregroundStyle(Color.accentColor)
                }
                Spacer(minLength: 0)
                Button {
                    session.dismissResult()
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Dismiss"))
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }
}
