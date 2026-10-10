# Spec Delta

## MODIFIED Requirements

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

## ADDED Requirements

### Requirement: Source checkboxes
Each of the two level meters SHALL have a checkbox that turns its source (microphone or system audio) on or off for the next recording. Both checkboxes SHALL be on on first launch and SHALL keep their state across app restarts. They SHALL be disabled while a recording is active or being saved.

#### Scenario: Turning the microphone off
- **WHEN** the user clears the microphone checkbox and starts a recording
- **THEN** the microphone is not recorded and its level meter stays empty

#### Scenario: Checkboxes on by default
- **WHEN** the app is launched for the first time
- **THEN** both checkboxes are on

#### Scenario: Checkbox state remembered
- **WHEN** the user clears the system audio checkbox and restarts the app
- **THEN** the system audio checkbox is still off

#### Scenario: Checkboxes locked during recording
- **WHEN** a recording is active
- **THEN** neither checkbox can be changed
