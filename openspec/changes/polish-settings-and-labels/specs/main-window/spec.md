# Spec Delta

## MODIFIED Requirements

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

## ADDED Requirements

### Requirement: Microphone choice
The main window SHALL provide the app's only microphone picker, listing "System Default" and all available input devices except aggregate devices (see the audio-capture spec). The choice SHALL persist across app restarts. Changing it SHALL be disabled while a recording is active.

#### Scenario: Microphone choice remembered
- **WHEN** the user selects a microphone in the main window and restarts the app
- **THEN** the same microphone is selected

#### Scenario: Picker locked during recording
- **WHEN** a recording is active
- **THEN** the microphone picker cannot be changed

## REMOVED Requirements

### Requirement: Microphone picker
**Reason**: It required the picker to stay in sync with a second picker in the Settings window, which is removed; replaced by "Microphone choice".
**Migration**: The microphone is chosen in the main window only; the stored setting is unchanged.
