# Spec Delta

## MODIFIED Requirements

### Requirement: Separate files option
When the separate-files option is enabled, the system SHALL save the microphone and system audio as two separate files instead of a mixed file: a mono microphone file and a stereo system audio file, both starting at the same moment. When only one source is recorded, only that source's file SHALL be created.

#### Scenario: Separate files produced
- **WHEN** a recording is stopped with the separate-files option enabled
- **THEN** two files are created, one with the microphone only and one with system audio only
- **AND** no mixed file is created

#### Scenario: Separate files are aligned
- **WHEN** both separate files are imported into an audio editor at position zero
- **THEN** the microphone and system audio are aligned in time

#### Scenario: Only one source recorded
- **WHEN** the separate-files option is enabled, the microphone source is off, and a recording is stopped
- **THEN** only the system audio file is created
