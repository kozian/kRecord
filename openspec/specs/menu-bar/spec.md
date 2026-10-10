# menu-bar Specification

## Purpose

Gives always-visible recording status and quick start/stop control from the macOS menu bar, independent of the main window.

## Requirements

### Requirement: Menu bar item always present
The system SHALL show a menu bar item for as long as the app is running and the "Show in menu bar" setting is on (the default). Turning the setting off SHALL remove the item immediately; the app then stays reachable through its Dock icon, which reopens the main window.

#### Scenario: Item visible after closing window
- **WHEN** "Show in menu bar" is on and the user closes the main window
- **THEN** the menu bar item remains visible

#### Scenario: Item hidden by the setting
- **WHEN** the user turns off "Show in menu bar"
- **THEN** the menu bar item disappears, also during a recording, and a recording continues

#### Scenario: Reopening without the menu bar item
- **WHEN** "Show in menu bar" is off and the main window is closed
- **THEN** clicking the Dock icon shows the main window again

### Requirement: Recording indicator icon
The menu bar icon SHALL be grey (monochrome template style) when no recording is active and red while a recording is active.

#### Scenario: Icon turns red
- **WHEN** a recording starts
- **THEN** the menu bar icon turns red

#### Scenario: Icon returns to grey
- **WHEN** a recording stops
- **THEN** the menu bar icon returns to grey

### Requirement: Optional elapsed time in menu bar
When the "show recording time in menu bar" setting is enabled, the system SHALL display the elapsed recording time next to the icon while recording. When idle, or when the setting is disabled, only the icon SHALL be shown.

#### Scenario: Time shown
- **WHEN** the setting is enabled and a recording has run for 12 minutes 34 seconds
- **THEN** the menu bar shows the red icon followed by `00:12:34`

#### Scenario: Time hidden by default
- **WHEN** the app is launched for the first time and a recording starts
- **THEN** only the red icon is shown in the menu bar

### Requirement: Menu contents
The menu bar item's menu SHALL contain exactly these actions: "Start Recording" (or "Stop Recording" while recording), "Settings…", and "Quit".

#### Scenario: Menu while idle
- **WHEN** no recording is active and the user opens the menu
- **THEN** the menu shows "Start Recording", "Settings…", and "Quit"

#### Scenario: Menu while recording
- **WHEN** a recording is active and the user opens the menu
- **THEN** the first item reads "Stop Recording"

#### Scenario: Start unavailable while saving
- **WHEN** a recording is being finalized
- **THEN** the start/stop item is disabled

### Requirement: Settings from menu
Choosing "Settings…" SHALL open the Settings window and bring it to the front.

#### Scenario: Open settings
- **WHEN** the user chooses "Settings…" from the menu bar menu
- **THEN** the Settings window opens in front of other windows

#### Scenario: Open settings while another app is active
- **WHEN** another app is the active app and the user chooses "Settings…" from the kRecord menu bar menu
- **THEN** kRecord becomes the active app and the Settings window is in front of the other app's windows

### Requirement: Quit from menu
Choosing "Quit" SHALL quit the app, subject to the quit-while-recording confirmation.

#### Scenario: Quit while idle
- **WHEN** no recording is active and the user chooses "Quit"
- **THEN** the app quits
