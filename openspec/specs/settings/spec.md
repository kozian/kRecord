# settings Specification

## Purpose

Holds the user's recording preferences, their defaults and persistence, and the Settings window where they are edited.

## Requirements

### Requirement: Available settings
The Settings window SHALL provide exactly these settings: destination folder, save as m4a, save separate files, echo cancellation, show in menu bar, and show recording time in menu bar. "Save as m4a" SHALL be explained as saving recordings as `.aac` when it is off. The microphone SHALL NOT be offered in the Settings window; it is chosen in the main window.

#### Scenario: Settings window contents
- **WHEN** the user opens the Settings window
- **THEN** all six settings are shown with their current values, and no microphone picker is shown

#### Scenario: Save format explained
- **WHEN** the user opens the Settings window
- **THEN** a note at "Save as m4a" says that recordings are otherwise saved as `.aac`

#### Scenario: Settings shown without scrolling
- **WHEN** the user opens the Settings window, in English or Russian, with or without the notice about an unavailable folder
- **THEN** the window shows all of its content at once, without a scroll bar and without scrolling

### Requirement: Default values
On first launch the settings SHALL have these values: destination folder `~/Music/kRecord/`, microphone "System Default", save as m4a on, save separate files off, echo cancellation off, show in menu bar on, show recording time in menu bar off.

#### Scenario: First launch defaults
- **WHEN** the app is launched for the first time
- **THEN** every setting has its default value

### Requirement: Settings persistence
Settings SHALL persist across app restarts, including access to a user-chosen destination folder outside the default location.

#### Scenario: Restart keeps settings
- **WHEN** the user turns off "Save as m4a" and restarts the app
- **THEN** "Save as m4a" is still off

#### Scenario: Custom folder remains writable after restart
- **WHEN** the user chooses a custom destination folder, restarts the app, and records
- **THEN** the recording is saved to the custom folder without asking for the folder again

### Requirement: Destination folder selection
The user SHALL choose the destination folder with the standard macOS folder picker, and the Settings window SHALL show the selected folder path with a way to reveal it in Finder.

#### Scenario: Change folder
- **WHEN** the user picks a different folder in the folder picker
- **THEN** subsequent recordings are saved to that folder

#### Scenario: Reveal folder
- **WHEN** the user clicks the reveal control next to the folder path
- **THEN** the folder opens in Finder

### Requirement: Fallback when saved folder is inaccessible
If access to a previously chosen custom folder can no longer be restored at launch, the system SHALL revert the destination folder to the default and inform the user in the Settings window.

#### Scenario: Custom folder deleted
- **WHEN** the custom destination folder was deleted while the app was not running and the app launches
- **THEN** the destination folder setting shows the default `~/Music/kRecord/` with a notice that the previous folder is unavailable

### Requirement: Settings apply to next recording
Changes to save as m4a, separate files, and echo cancellation SHALL take effect from the next recording. These controls SHALL be disabled while a recording is active. The menu bar settings (show in menu bar, show recording time) SHALL take effect immediately, also during a recording.

#### Scenario: Save as m4a locked during recording
- **WHEN** a recording is active
- **THEN** the "Save as m4a" control cannot be changed

#### Scenario: Menu bar time toggled during recording
- **WHEN** a recording is active and the user enables showing the time in the menu bar
- **THEN** the elapsed time appears next to the menu bar icon immediately

#### Scenario: Menu bar item hidden
- **WHEN** the user turns off "Show in menu bar"
- **THEN** the menu bar item disappears immediately and "Show recording time in menu bar" cannot be changed until the item is shown again

### Requirement: Localized interface
All user-facing text in the app SHALL be available in English and Russian, following the macOS system language, with English as the fallback.

#### Scenario: Russian system language
- **WHEN** the macOS preferred language is Russian
- **THEN** the main window, menu bar menu, Settings window, alerts, and error messages are shown in Russian

#### Scenario: Unsupported system language
- **WHEN** the macOS preferred language is German
- **THEN** the app is shown in English
