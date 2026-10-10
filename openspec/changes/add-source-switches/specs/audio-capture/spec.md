# Spec Delta

## MODIFIED Requirements

### Requirement: Recording with a single available source
If only one source is available because a permission is denied or the other source is turned off, the system SHALL record that source alone.

#### Scenario: Microphone permission denied
- **WHEN** microphone access is denied and system audio capture is permitted
- **AND** the user starts a recording
- **THEN** the recording contains system audio only

#### Scenario: Microphone turned off
- **WHEN** the microphone source is turned off and the user starts a recording
- **THEN** the recording contains system audio only

## ADDED Requirements

### Requirement: Sources can be turned off
Before a recording starts, the user SHALL be able to turn the microphone source and the system audio source on or off. A source that is off SHALL NOT be captured; in particular the microphone SHALL NOT be opened. A recording SHALL require at least one source that is on and permitted.

#### Scenario: Microphone off
- **WHEN** the microphone source is off and a recording is active
- **THEN** no input device is in use by kRecord (macOS shows no microphone-in-use indicator for it)

#### Scenario: System audio off
- **WHEN** the system audio source is off and the user records while another app plays audio
- **THEN** the recording contains the microphone only

#### Scenario: Both sources off
- **WHEN** both sources are off
- **THEN** no recording can be started
