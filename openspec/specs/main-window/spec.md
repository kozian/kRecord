# main-window Specification

## Purpose

Provides the primary, minimal app window for controlling a recording and seeing at a glance that both sources are being captured.

## Requirements

### Requirement: Main window shown at launch
The system SHALL show the main window when the app launches and SHALL allow reopening it after it is closed, from the Dock icon and from the app's menu.

#### Scenario: Reopen after closing
- **WHEN** the user closes the main window and clicks the app icon in the Dock
- **THEN** the main window is shown again

### Requirement: Closing the window does not stop recording
Closing the main window SHALL NOT stop an active recording or quit the app.

#### Scenario: Window closed during recording
- **WHEN** a recording is active and the user closes the main window
- **THEN** the recording continues and the menu bar still shows the recording indicator

### Requirement: Record button
The main window SHALL contain a single prominent button that starts a recording when idle and stops it when recording, with a label and appearance reflecting the current state.

#### Scenario: Toggle recording
- **WHEN** the app is idle and the user clicks the button
- **THEN** a recording starts and the button changes to a stop state

#### Scenario: Button unavailable while saving
- **WHEN** a recording is being finalized
- **THEN** the button is disabled and indicates saving is in progress

### Requirement: Elapsed time display
The main window SHALL display the elapsed recording time while recording, and `00:00:00` when idle.

#### Scenario: Idle display
- **WHEN** no recording is active
- **THEN** the main window shows `00:00:00`

### Requirement: Separate level meters
The main window SHALL show two labeled level meters, one for the microphone and one for system audio, reflecting live levels while recording.

#### Scenario: Meters during recording
- **WHEN** a recording is active and system audio is playing
- **THEN** the system audio meter moves in response to the audio

### Requirement: Microphone picker
The main window SHALL provide a microphone picker listing "System Default" and all available input devices except aggregate devices (see the audio-capture spec), bound to the same microphone setting as the Settings window. Changing it SHALL be disabled while a recording is active.

#### Scenario: Picker synced with settings
- **WHEN** the user selects a microphone in the main window
- **THEN** the same microphone is shown as selected in the Settings window

#### Scenario: Picker locked during recording
- **WHEN** a recording is active
- **THEN** the microphone picker cannot be changed

### Requirement: Permission warnings
When a capture permission is missing, the main window SHALL show a warning naming the missing source with a way to open the relevant System Settings pane. When both permissions are missing, the record button SHALL be disabled.

#### Scenario: Microphone permission missing
- **WHEN** microphone access is denied
- **THEN** the main window shows a warning that the microphone will not be recorded, with a button that opens System Settings

#### Scenario: Both permissions missing
- **WHEN** both microphone and system audio permissions are denied
- **THEN** the record button is disabled

### Requirement: Error display
The main window SHALL display the most recent recording error until the user dismisses it or starts a new recording.

#### Scenario: Error shown
- **WHEN** a recording stops due to an error
- **THEN** the main window shows the error message
