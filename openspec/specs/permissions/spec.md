# permissions Specification

## Purpose

Obtains the macOS privacy permissions needed to record the microphone and system audio, and keeps the app usable and honest about what it can record when permissions are missing.

## Requirements

### Requirement: Request permissions on first launch
On first launch the system SHALL request microphone access and system audio capture access through the standard macOS permission prompts, without a separate onboarding flow.

#### Scenario: First launch prompts
- **WHEN** the app is launched for the first time
- **THEN** macOS prompts the user for microphone access and for system audio recording access

### Requirement: Usage descriptions
Each permission prompt SHALL include a localized explanation stating that the access is used to record meetings to local files.

#### Scenario: Microphone prompt text
- **WHEN** macOS shows the microphone permission prompt
- **THEN** the prompt explains that the microphone is recorded into local audio files

### Requirement: Permission status tracking
The system SHALL determine the current status of each permission at launch and when the app becomes active, so that permission changes made in System Settings are reflected without restarting the app where macOS allows it.

#### Scenario: Permission granted later
- **WHEN** microphone access was denied, the user grants it in System Settings, and returns to the app
- **THEN** the microphone permission warning disappears

### Requirement: Unknown system audio permission status
When macOS does not expose whether system audio capture is permitted, the system SHALL treat the status as unknown, SHALL allow recording, and SHALL show a non-blocking hint with a link to the System Settings pane if a recording captures only digital silence from system audio for its whole duration.

#### Scenario: Status not determinable
- **WHEN** the system audio permission status cannot be determined
- **THEN** the record button remains enabled

#### Scenario: Silent system audio hint
- **WHEN** a recording finishes and the system audio track contained only digital silence
- **THEN** the main window shows a hint that system audio may be blocked by privacy settings, with a button to open System Settings

### Requirement: Recording with partial permissions
The system SHALL allow recording when at least one of the two permissions is granted, capturing only permitted sources, and SHALL block recording when neither is granted.

#### Scenario: Only system audio permitted
- **WHEN** only system audio capture is permitted and the user starts a recording
- **THEN** the recording starts and captures system audio only

#### Scenario: No permissions
- **WHEN** neither permission is granted
- **THEN** the user cannot start a recording

### Requirement: Open System Settings
For each missing permission the system SHALL offer a control that opens the corresponding Privacy & Security pane in System Settings.

#### Scenario: Open microphone privacy pane
- **WHEN** the user clicks the control next to the microphone permission warning
- **THEN** System Settings opens at the Microphone privacy pane

### Requirement: Local-only data
The system SHALL keep all captured audio on the local machine and SHALL NOT transmit audio or recordings over the network.

#### Scenario: No network use
- **WHEN** a recording is made and saved
- **THEN** the app makes no network connections
