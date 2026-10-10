# Spec Delta

## MODIFIED Requirements

### Requirement: Available settings
The Settings window SHALL provide exactly these settings: destination folder, microphone, system audio source, save as m4a, save separate files, echo cancellation, and show recording time in menu bar.

#### Scenario: Settings window contents
- **WHEN** the user opens the Settings window
- **THEN** all seven settings are shown with their current values

### Requirement: Default values
On first launch the settings SHALL have these values: destination folder `~/Music/kRecord/`, microphone "System Default", system audio source "All Audio", microphone source on, system audio source on, save as m4a on, save separate files off, echo cancellation off, show recording time in menu bar off.

#### Scenario: First launch defaults
- **WHEN** the app is launched for the first time
- **THEN** every setting has its default value

### Requirement: Settings apply to next recording
Changes to microphone, system audio source, the source checkboxes, save as m4a, separate files, and echo cancellation SHALL take effect from the next recording. These controls SHALL be disabled while a recording is active. The menu bar time setting SHALL take effect immediately.

#### Scenario: Save as m4a locked during recording
- **WHEN** a recording is active
- **THEN** the "Save as m4a" control cannot be changed

#### Scenario: System audio source locked during recording
- **WHEN** a recording is active
- **THEN** the system audio source cannot be changed in the Settings window or the main window

#### Scenario: Menu bar time toggled during recording
- **WHEN** a recording is active and the user enables showing the time in the menu bar
- **THEN** the elapsed time appears next to the menu bar icon immediately
