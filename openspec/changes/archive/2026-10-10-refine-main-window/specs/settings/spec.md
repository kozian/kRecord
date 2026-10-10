# Spec Delta

## MODIFIED Requirements

### Requirement: Available settings
The Settings window SHALL provide exactly these settings: destination folder, save as m4a, save separate files, echo cancellation, warn when a recording has no system audio, show in menu bar, and show recording time in menu bar. "Save as m4a" SHALL be explained as saving recordings as `.aac` when it is off. The microphone SHALL NOT be offered in the Settings window; it is chosen in the main window.

#### Scenario: Settings window contents
- **WHEN** the user opens the Settings window
- **THEN** all seven settings are shown with their current values, and no microphone picker is shown

#### Scenario: Save format explained
- **WHEN** the user opens the Settings window
- **THEN** a note at "Save as m4a" says that recordings are otherwise saved as `.aac`

#### Scenario: Settings shown without scrolling
- **WHEN** the user opens the Settings window, in English or Russian, with or without the notice about an unavailable folder
- **THEN** the window shows all of its content at once, without a scroll bar and without scrolling

### Requirement: Default values
On first launch the settings SHALL have these values: destination folder `~/Music/kRecord/`, microphone "System Default", save as m4a on, save separate files off, echo cancellation off, warn when a recording has no system audio on, show in menu bar on, show recording time in menu bar off.

#### Scenario: First launch defaults
- **WHEN** the app is launched for the first time
- **THEN** every setting has its default value

### Requirement: Settings apply to next recording
Changes to save as m4a, separate files, and echo cancellation SHALL take effect from the next recording. These controls SHALL be disabled while a recording is active. The menu bar settings (show in menu bar, show recording time) and the warning about silent system audio SHALL take effect immediately, also during a recording.

#### Scenario: Save as m4a locked during recording
- **WHEN** a recording is active
- **THEN** the "Save as m4a" control cannot be changed

#### Scenario: Menu bar time toggled during recording
- **WHEN** a recording is active and the user enables showing the time in the menu bar
- **THEN** the elapsed time appears next to the menu bar icon immediately

#### Scenario: Menu bar item hidden
- **WHEN** the user turns off "Show in menu bar"
- **THEN** the menu bar item disappears immediately and "Show recording time in menu bar" cannot be changed until the item is shown again
