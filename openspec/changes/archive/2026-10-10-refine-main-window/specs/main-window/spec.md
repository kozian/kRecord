# Spec Delta

## MODIFIED Requirements

### Requirement: Source checkboxes
Each source SHALL be shown as one row: a checkbox labeled with the short source name ("Microphone", "System"), followed by its level meter; both meters SHALL start at the same horizontal position. The checkbox turns its source on or off for the next recording. Both checkboxes SHALL be on on first launch and SHALL keep their state across app restarts. They SHALL be disabled while a recording is active or being saved.

#### Scenario: Turning the microphone off
- **WHEN** the user clears the microphone checkbox and starts a recording
- **THEN** the microphone is not recorded and its level meter stays empty

#### Scenario: Checkbox labels
- **WHEN** the main window is shown in English
- **THEN** the rows read "Microphone" and "System" (in Russian "Микрофон" and "Система"), each followed by its level meter

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

### Requirement: Window without title bar
The main window SHALL have no title bar and no visible title, SHALL keep the standard window buttons, and SHALL be movable by dragging its background.

#### Scenario: Window buttons without a title
- **WHEN** the main window is shown
- **THEN** the close, minimize, and zoom buttons are shown at the top left and no title bar or title text is shown

#### Scenario: Dragging by the background
- **WHEN** the user drags an empty area of the main window, for example next to the timer
- **THEN** the window moves
