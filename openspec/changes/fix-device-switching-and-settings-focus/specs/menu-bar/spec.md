# Spec Delta

## MODIFIED Requirements

### Requirement: Settings from menu
Choosing "Settings…" SHALL open the Settings window and bring it to the front.

#### Scenario: Open settings
- **WHEN** the user chooses "Settings…" from the menu bar menu
- **THEN** the Settings window opens in front of other windows

#### Scenario: Open settings while another app is active
- **WHEN** another app is the active app and the user chooses "Settings…" from the kRecord menu bar menu
- **THEN** kRecord becomes the active app and the Settings window is in front of the other app's windows
