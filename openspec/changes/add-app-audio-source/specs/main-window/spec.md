# Spec Delta

## ADDED Requirements

### Requirement: System audio source picker
The main window SHALL provide a picker for the system audio source that lists "All Audio" as its first option, followed by the running applications. A selected application that is not running SHALL be listed as "<name> (not running)". The picker SHALL be bound to the same setting as the Settings window and SHALL be disabled while a recording is active or being saved.

#### Scenario: All Audio first and selected by default
- **WHEN** the app is launched for the first time and the user opens the system audio source picker
- **THEN** "All Audio" is the first option and is selected

#### Scenario: Selected application not running
- **WHEN** the selected application is not running
- **THEN** the picker shows it as "<name> (not running)" and keeps it selected
