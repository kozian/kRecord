# Spec Delta

## MODIFIED Requirements

### Requirement: Available settings
The Settings window SHALL provide exactly these settings: destination folder, microphone, save as m4a, save separate files, echo cancellation, and show recording time in menu bar.

#### Scenario: Settings window contents
- **WHEN** the user opens the Settings window
- **THEN** all six settings are shown with their current values

#### Scenario: Settings shown without scrolling
- **WHEN** the user opens the Settings window, in English or Russian, with or without the notice about an unavailable folder
- **THEN** the window shows all of its content at once, without a scroll bar and without scrolling
