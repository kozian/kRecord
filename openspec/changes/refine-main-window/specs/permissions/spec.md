# Spec Delta

## MODIFIED Requirements

### Requirement: Unknown system audio permission status
When macOS does not expose whether system audio capture is permitted, the system SHALL treat the status as unknown, SHALL allow recording, and SHALL show a non-blocking hint with a link to the System Settings pane if a recording captures only digital silence from system audio for its whole duration. The hint SHALL offer "Don't show again", which turns off the "Warn when a recording has no system audio" setting; while that setting is off, the hint SHALL NOT be shown.

#### Scenario: Status not determinable
- **WHEN** the system audio permission status cannot be determined
- **THEN** the record button remains enabled

#### Scenario: Silent system audio hint
- **WHEN** a recording finishes and the system audio track contained only digital silence
- **THEN** the main window shows a hint that system audio may be blocked by privacy settings, with a button to open System Settings and a "Don't show again" link

#### Scenario: Hint turned off
- **WHEN** the user chooses "Don't show again", or turns the warning off in Settings, and a later recording has only digital silence as system audio
- **THEN** no hint is shown
