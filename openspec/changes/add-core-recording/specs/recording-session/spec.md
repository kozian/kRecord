# Spec Delta

## Purpose

Defines the single recording lifecycle (idle, recording, finishing, error) that the main window and the menu bar both control and display, so every UI surface shows the same state.

## ADDED Requirements

### Requirement: Start and stop recording
The system SHALL support exactly two recording actions: start and stop. Pausing is not supported.

#### Scenario: Start then stop
- **WHEN** the user starts a recording and later stops it
- **THEN** a recording file is saved covering the time between start and stop

### Requirement: Single shared recording state
At most one recording SHALL be active at a time, and the recording state SHALL be shared across all UI surfaces so that an action in one surface is reflected in all others immediately.

#### Scenario: Started from menu bar
- **WHEN** the user starts a recording from the menu bar menu
- **THEN** the main window shows the recording as active with a running timer

#### Scenario: Stopped from main window
- **WHEN** the user stops a recording from the main window
- **THEN** the menu bar icon returns to the idle state

### Requirement: Elapsed time
While a recording is active, the system SHALL track elapsed recording time from the moment capture started, displayed as `HH:MM:SS`.

#### Scenario: Timer progresses
- **WHEN** a recording has been active for 1 minute and 5 seconds
- **THEN** the elapsed time reads `00:01:05`

### Requirement: Finishing state
After the user stops a recording, the system SHALL indicate that the file is being finalized until the output file(s) are complete, and SHALL NOT allow a new recording to start until finalization finishes.

#### Scenario: Finalizing a long recording
- **WHEN** the user stops a long recording that requires format conversion
- **THEN** the UI indicates the recording is being saved
- **AND** the record action is unavailable until saving completes

### Requirement: Error reporting
When a recording cannot start or stops because of an error, the system SHALL show the user a localized, human-readable error message and return to the idle state.

#### Scenario: Error during recording
- **WHEN** a recording stops because of a storage failure
- **THEN** the user sees an error message describing the cause
- **AND** the recording state returns to idle

### Requirement: Confirm quit while recording
If the user quits the app while a recording is active, the system SHALL ask for confirmation with the option "Stop Recording and Quit" and an option to cancel. Confirming SHALL stop the recording, save it, and then quit.

#### Scenario: Quit confirmed
- **WHEN** a recording is active and the user chooses Quit
- **AND** the user confirms "Stop Recording and Quit"
- **THEN** the recording is saved and the app quits

#### Scenario: Quit cancelled
- **WHEN** a recording is active and the user chooses Quit
- **AND** the user cancels the confirmation
- **THEN** the app keeps running and the recording continues

#### Scenario: Quit while idle
- **WHEN** no recording is active and the user chooses Quit
- **THEN** the app quits without confirmation
