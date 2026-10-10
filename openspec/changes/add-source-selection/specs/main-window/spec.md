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
Each of the two level meters SHALL have a checkbox that turns its source (microphone or system audio) on or off for the next recording. The checkboxes SHALL be disabled while a recording is active or being saved.

#### Scenario: Turning the microphone off
- **WHEN** the user clears the microphone checkbox and starts a recording
- **THEN** the microphone is not recorded and its level meter stays empty

#### Scenario: Checkboxes locked during recording
- **WHEN** a recording is active
- **THEN** neither checkbox can be changed

### Requirement: System audio source picker
The main window SHALL provide a picker for the system audio source that lists "All Audio" as its first option, followed by the running applications. A selected application that is not running SHALL be listed as "<name> (not running)". The picker SHALL be bound to the same setting as the Settings window and SHALL be disabled while a recording is active or being saved.

#### Scenario: All Audio first and selected by default
- **WHEN** the app is launched for the first time and the user opens the system audio source picker
- **THEN** "All Audio" is the first option and is selected

#### Scenario: Selected application not running
- **WHEN** the selected application is not running
- **THEN** the picker shows it as "<name> (not running)" and keeps it selected
