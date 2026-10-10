# Spec Delta

## Purpose

Captures the user's microphone and the Mac's system audio output at the same time, on a shared timeline, so meetings can be recorded with both sides of the conversation.

## ADDED Requirements

### Requirement: Simultaneous microphone and system audio capture
While a recording is active, the system SHALL capture audio from the selected microphone and all system audio output at the same time.

#### Scenario: Both sources recorded
- **WHEN** the user starts a recording with both permissions granted
- **AND** the user speaks while another app plays audio
- **THEN** the resulting recording contains both the user's voice and the other app's audio

### Requirement: All system audio is captured
The system SHALL capture the combined audio output of all processes, without per-application selection or filtering.

#### Scenario: Audio from multiple apps
- **WHEN** two different apps play audio during a recording
- **THEN** audio from both apps is present in the system audio track

### Requirement: Microphone captured as mono
The system SHALL capture the microphone as a single mono channel. If the input device has multiple channels, the system SHALL use the device's first input channel.

#### Scenario: Multichannel audio interface
- **WHEN** the selected input device is a multichannel audio interface
- **THEN** the microphone track is recorded as mono from the device's first input channel

### Requirement: System audio captured as stereo
The system SHALL capture system audio as two-channel stereo, preserving the left/right image of the output.

#### Scenario: Stereo content
- **WHEN** an app plays audio panned fully left during a recording
- **THEN** the system audio track contains that audio in the left channel only

### Requirement: Synchronized timeline
Microphone and system audio SHALL be captured on a shared timeline so that they stay aligned for the entire duration of a recording, with no audible drift between them.

#### Scenario: Long recording stays in sync
- **WHEN** a recording runs for 60 minutes with both sources active
- **THEN** at the end of the recording the offset between microphone and system audio is not audibly different from the offset at the start

### Requirement: Default input device is followed
When no specific microphone is selected, the system SHALL use the current macOS default input device and SHALL switch to the new default device if it changes during a recording, without stopping the recording.

#### Scenario: Default input changes mid-recording
- **WHEN** a recording is active using the default input device
- **AND** the user changes the macOS default input device
- **THEN** the recording continues and subsequent microphone audio comes from the new default device

### Requirement: Explicit microphone selection
The system SHALL allow the user to select a specific input device from the list of currently available input devices, or to choose "System Default". Aggregate devices SHALL NOT be offered, because capture combines the microphone and system audio in an aggregate device of its own, which cannot contain another aggregate device.

#### Scenario: Specific microphone selected
- **WHEN** the user selects a specific connected microphone and starts a recording
- **THEN** microphone audio is captured from that device regardless of the macOS default input device

#### Scenario: Aggregate devices are not offered
- **WHEN** an aggregate device created in Audio MIDI Setup is available as an input
- **THEN** it does not appear in the list of selectable input devices

#### Scenario: Device list reflects hardware changes
- **WHEN** an input device is connected or disconnected
- **THEN** the list of selectable input devices updates to reflect the change

### Requirement: Fallback when selected microphone disappears
If the explicitly selected microphone becomes unavailable, the system SHALL fall back to the macOS default input device and continue recording. The user's selection SHALL be remembered and used again when the device reappears before the next recording.

#### Scenario: Selected microphone unplugged during recording
- **WHEN** a recording is active using an explicitly selected USB microphone
- **AND** that microphone is disconnected
- **THEN** the recording continues using the macOS default input device

#### Scenario: Selected microphone unavailable at start
- **WHEN** the selected microphone is not connected and the user starts a recording
- **THEN** the recording starts using the macOS default input device

### Requirement: System audio continues across output device changes
The system SHALL continue capturing system audio when the macOS output device changes during a recording.

#### Scenario: Headphones connected mid-recording
- **WHEN** a recording is active
- **AND** the user connects headphones and macOS switches output to them
- **THEN** the recording continues and system audio played to the headphones is captured

### Requirement: Optional echo cancellation
The system SHALL provide an echo cancellation option, disabled by default. When enabled, the microphone signal SHALL be processed by the macOS voice processing so that system audio played through speakers is suppressed in the microphone track.

#### Scenario: Echo cancellation enabled with speakers
- **WHEN** echo cancellation is enabled
- **AND** a recording is made while system audio plays through built-in speakers
- **THEN** the microphone track contains substantially less of the system audio than with echo cancellation disabled

#### Scenario: Echo cancellation disabled by default
- **WHEN** the app is launched for the first time
- **THEN** echo cancellation is disabled

### Requirement: Live level metering
The system SHALL provide live audio levels for the microphone and for system audio separately, updated continuously while a recording is active.

#### Scenario: Levels reflect activity
- **WHEN** a recording is active and the user speaks while system audio is silent
- **THEN** the microphone level shows activity and the system audio level shows silence

### Requirement: Recording with a single available source
If only one source is available because a permission is denied, the system SHALL record that source alone.

#### Scenario: Microphone permission denied
- **WHEN** microphone access is denied and system audio capture is permitted
- **AND** the user starts a recording
- **THEN** the recording contains system audio only
