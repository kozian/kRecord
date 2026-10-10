import SwiftUI

/// The primary window: record button, elapsed time, level meters, microphone choice, and the
/// permission and error messages (main-window spec).
struct MainWindowView: View {
    let model: AppModel
    @Environment(\.openSettings) private var openSettings

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

            // Checkbox, label, and meter in one row per source; the labels share a column so
            // both meters start at the same x.
            Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 8) {
                GridRow {
                    Toggle("Microphone", isOn: sourceBinding(\.recordsMicrophone))
                    LevelMeter(value: session.levels.microphone.meterValue())
                        .opacity(model.settings.recordsMicrophone ? 1 : 0.4)
                }
                GridRow {
                    Toggle("System", isOn: sourceBinding(\.recordsSystemAudio))
                    LevelMeter(value: session.levels.system.meterValue())
                        .opacity(model.settings.recordsSystemAudio ? 1 : 0.4)
                }
            }
            .toggleStyle(.checkbox)
            .font(.caption)
            .disabled(model.recordingSettingsAreLocked)

            // A microphone symbol instead of a text label leaves the picker room for full device
            // names in the narrow window; the picker keeps "Microphone" as its accessibility label.
            HStack(spacing: 4) {
                HStack(spacing: 0) {
                    Image(systemName: "mic")
                    Text(verbatim: ":")
                }
                .foregroundStyle(.secondary)
                .help(Text("Microphone"))
                .accessibilityHidden(true)
                // A menu picker is never wider than its longest item, so it is kept next to the
                // symbol and the free space goes between it and the buttons.
                MicrophonePicker(settings: model.settings, devices: model.devices,
                                 isLocked: model.recordingSettingsAreLocked)
                    .labelsHidden()
                    .frame(maxWidth: .infinity, alignment: .leading)
                IconButton(systemImage: "folder", help: "Show Recordings in Finder") {
                    model.revealRecordingsFolder()
                }
                IconButton(systemImage: "gearshape", help: "Settings") {
                    openSettings()
                }
            }

            silentSystemAudioNote
        }
        // With the title bar hidden, the content starts below the strip of the window buttons
        // (top safe area); 7.5 pt more makes the gap from the window buttons to the digits equal to
        // the gap from the digits to the record button (27.5 pt, measured).
        .padding([.horizontal, .bottom], 16)
        .padding(.top, 7.5)
        .frame(width: 310)
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
    private var silentNoteActions: some View {
        Button("Open System Settings") { model.permissions.openSettings(.systemAudio) }
            .fixedSize()
        // Turns the warning off; it can be turned on again in Settings.
        Button("Don't show again") { model.settings.warnsAboutSilentSystemAudio = false }
            .fixedSize()
    }

    @ViewBuilder
    private var silentSystemAudioNote: some View {
        if session.lastResult?.systemAudioSilent == true, model.settings.warnsAboutSilentSystemAudio {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: "speaker.slash")
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("The last recording has no system audio. It may be blocked in privacy settings.")
                        .fixedSize(horizontal: false, vertical: true)
                    // Side by side when they fit (English), otherwise one below the other (Russian).
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 12) { silentNoteActions }
                        VStack(alignment: .leading, spacing: 2) { silentNoteActions }
                    }
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
