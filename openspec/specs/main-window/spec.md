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

### Requirement: Microphone choice
The main window SHALL provide the app's only microphone picker, listing "System Default" and all available input devices except aggregate devices (see the audio-capture spec). The choice SHALL persist across app restarts. Changing it SHALL be disabled while a recording is active.

#### Scenario: Microphone choice remembered
- **WHEN** the user selects a microphone in the main window and restarts the app
- **THEN** the same microphone is selected

#### Scenario: Picker locked during recording
- **WHEN** a recording is active
- **THEN** the microphone picker cannot be changed

### Requirement: Permission warnings
When a capture permission is missing, the main window SHALL show a warning naming the missing source with a way to open the relevant System Settings pane. When both permissions are missing, or no permitted source is turned on, the record button SHALL be disabled.

#### Scenario: Microphone permission missing
- **WHEN** microphone access is denied
- **THEN** the main window shows a warning that the microphone will not be recorded, with a button that opens System Settings

#### Scenario: Both permissions missing
- **WHEN** both microphone and system audio permissions are denied
- **THEN** the record button is disabled

#### Scenario: No source turned on
- **WHEN** both source checkboxes are off
- **THEN** the record button is disabled

### Requirement: Error display
The main window SHALL display the most recent recording error until the user dismisses it or starts a new recording.

#### Scenario: Error shown
- **WHEN** a recording stops due to an error
- **THEN** the main window shows the error message

### Requirement: Source checkboxes
Each of the two level meters SHALL have a checkbox, labeled with the source name only ("Microphone", "System audio"), that turns its source on or off for the next recording. Both checkboxes SHALL be on on first launch and SHALL keep their state across app restarts. They SHALL be disabled while a recording is active or being saved.

#### Scenario: Turning the microphone off
- **WHEN** the user clears the microphone checkbox and starts a recording
- **THEN** the microphone is not recorded and its level meter stays empty

#### Scenario: Checkbox labels
- **WHEN** the main window is shown in English
- **THEN** the checkboxes read "Microphone" and "System audio" (in Russian "Микрофон" and "Системный звук")

#### Scenario: Checkboxes on by default
- **WHEN** the app is launched for the first time
- **THEN** both checkboxes are on

#### Scenario: Checkbox state remembered
- **WHEN** the user clears the system audio checkbox and restarts the app
- **THEN** the system audio checkbox is still off

#### Scenario: Checkboxes locked during recording
- **WHEN** a recording is active
- **THEN** neither checkbox can be changed

### Requirement: Quick access to recordings and settings
The main window SHALL provide two small icon buttons next to the microphone picker: one that opens the recordings folder in Finder and one that opens the Settings window. Each SHALL show a tooltip describing it. Both SHALL stay available while a recording is active.

#### Scenario: Open recordings folder
- **WHEN** the user clicks the folder button in the main window
- **THEN** the destination folder opens in Finder, created first if it does not exist yet

#### Scenario: Open settings from the main window
- **WHEN** the user clicks the gear button in the main window
- **THEN** the Settings window opens in front

#### Scenario: Available during a recording
- **WHEN** a recording is active
- **THEN** both buttons can still be used
