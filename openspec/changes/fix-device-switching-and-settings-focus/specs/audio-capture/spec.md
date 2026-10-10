# Spec Delta

## MODIFIED Requirements

### Requirement: Default input device is followed
When no specific microphone is selected, the system SHALL use the current macOS default input device and SHALL switch to the new default device if it changes during a recording, without stopping the recording. This applies with echo cancellation on as well as off.

#### Scenario: Default input changes mid-recording
- **WHEN** a recording is active using the default input device
- **AND** the user changes the macOS default input device
- **THEN** the recording continues and subsequent microphone audio comes from the new default device

#### Scenario: Default input changes with echo cancellation
- **WHEN** echo cancellation is on and a recording is active using the default input device
- **AND** the user changes the macOS default input device
- **THEN** the recording continues, subsequent microphone audio comes from the new default device with echo cancellation applied, and the microphone track stays aligned with the system audio track

### Requirement: Fallback when selected microphone disappears
If the explicitly selected microphone becomes unavailable, the system SHALL fall back to the macOS default input device and continue recording. The user's selection SHALL be remembered and used again when the device reappears before the next recording. This applies with echo cancellation on as well as off.

#### Scenario: Selected microphone unplugged during recording
- **WHEN** a recording is active using an explicitly selected USB microphone
- **AND** that microphone is disconnected
- **THEN** the recording continues using the macOS default input device

#### Scenario: Selected microphone unavailable at start
- **WHEN** the selected microphone is not connected and the user starts a recording
- **THEN** the recording starts using the macOS default input device

#### Scenario: Selected microphone unplugged with echo cancellation
- **WHEN** echo cancellation is on and a recording is active using an explicitly selected USB microphone
- **AND** that microphone is disconnected
- **THEN** the recording continues using the macOS default input device (or with a silent microphone track if no input device is left), and the system audio track continues without interruption longer than a second

#### Scenario: Selected microphone reconnected with echo cancellation
- **WHEN** echo cancellation is on, a recording fell back from an unplugged selected microphone, and that microphone is connected again
- **THEN** subsequent microphone audio comes from the selected microphone, aligned with the system audio track
