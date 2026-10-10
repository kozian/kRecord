# Spec Delta

## MODIFIED Requirements

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
