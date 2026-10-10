# Spec Delta

## RENAMED Requirements

- FROM: `### Requirement: All system audio is captured`
- TO: `### Requirement: System audio source`

## MODIFIED Requirements

### Requirement: Simultaneous microphone and system audio capture
While a recording is active, the system SHALL capture audio from the selected microphone and from the selected system audio source at the same time.

#### Scenario: Both sources recorded
- **WHEN** the user starts a recording with both permissions granted
- **AND** the user speaks while another app plays audio
- **THEN** the resulting recording contains both the user's voice and the other app's audio

### Requirement: System audio source
The system SHALL capture as system audio either the combined audio output of all processes ("All Audio", the default) or the audio output of one application selected by the user, including the audio played by that application's helper processes.

#### Scenario: Audio from multiple apps
- **WHEN** "All Audio" is selected and two different apps play audio during a recording
- **THEN** audio from both apps is present in the system audio track

#### Scenario: One application selected
- **WHEN** a single application is selected as the system audio source and it and another app play audio during a recording
- **THEN** the system audio track contains the selected application's audio and not the other app's audio

#### Scenario: Audio played by a helper process
- **WHEN** a web browser is selected and a tab in it plays audio
- **THEN** the tab's audio is present in the system audio track

## ADDED Requirements

### Requirement: Selected application not running
When the selected application is not running at the start of a recording, or quits during it, the system SHALL continue the recording with silence on the system audio track and SHALL capture the application's audio as soon as it runs again, without stopping the recording.

#### Scenario: Application not running at start
- **WHEN** the selected application is not running and the user starts a recording
- **THEN** the recording starts, and the system audio track is silent until the application starts and plays audio

#### Scenario: Application restarted during a recording
- **WHEN** the selected application quits during a recording and is started again
- **THEN** the recording continues throughout, and the application's audio after the restart is present in the system audio track, aligned with the microphone track
