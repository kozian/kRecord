# Spec Delta

## ADDED Requirements

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
