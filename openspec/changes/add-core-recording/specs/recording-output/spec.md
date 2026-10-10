# Spec Delta

## Purpose

Turns captured audio into files on disk: encodes it as AAC while recording, chooses the layout (mixed or separate) and container (m4a or aac), names and places files, keeps in-progress recordings safe, and handles storage failures.

## ADDED Requirements

### Requirement: Mixed recording by default
By default the system SHALL save each recording as one stereo file mixing both sources at equal level: system audio keeps its stereo image and the microphone is placed in the center of the stereo field.

#### Scenario: Default output
- **WHEN** a recording is stopped with default settings
- **THEN** exactly one stereo audio file is created containing both microphone and system audio

#### Scenario: Microphone centered
- **WHEN** the user speaks with system audio silent
- **THEN** the user's voice is equally loud in the left and right channels of the mixed file

### Requirement: Separate files option
When the separate-files option is enabled, the system SHALL save the microphone and system audio as two separate files instead of a mixed file: a mono microphone file and a stereo system audio file, both starting at the same moment.

#### Scenario: Separate files produced
- **WHEN** a recording is stopped with the separate-files option enabled
- **THEN** two files are created, one with the microphone only and one with system audio only
- **AND** no mixed file is created

#### Scenario: Separate files are aligned
- **WHEN** both separate files are imported into an audio editor at position zero
- **THEN** the microphone and system audio are aligned in time

### Requirement: Recording format
Recordings SHALL be AAC audio at a 48 kHz sample rate and 128 kbps or higher, encoded while recording. When the "Save as m4a" setting is on (default), the system SHALL save each recording in an `.m4a` container by repackaging the recorded AAC audio without re-encoding it. When the setting is off, the system SHALL keep the recording as a raw AAC stream file with the `.aac` extension.

#### Scenario: Default format
- **WHEN** a recording is stopped with default settings
- **THEN** the file is AAC audio with the `.m4a` extension

#### Scenario: Save as m4a off
- **WHEN** "Save as m4a" is off and a recording is stopped
- **THEN** the file is AAC audio with the `.aac` extension

#### Scenario: Saving as m4a does not re-encode
- **WHEN** a recording is saved as `.m4a`
- **THEN** its audio is identical to the AAC audio recorded during the session and has exactly the recorded duration

### Requirement: Automatic saving to destination folder
The system SHALL save recordings automatically to the configured destination folder without prompting the user for a file name or location.

#### Scenario: No save dialog
- **WHEN** the user stops a recording
- **THEN** the file appears in the destination folder without any save dialog

### Requirement: Timestamp-based file names
Files SHALL be named `kRecord YYYY-MM-DD HH-mm-ss.<ext>` using the local start time of the recording, where `<ext>` is `m4a` or `aac`. In separate-files mode, names SHALL use the suffixes ` (mic)` and ` (system)` before the extension. If a file with the same name exists with either extension, the system SHALL append a numeric suffix and SHALL NOT overwrite existing files.

#### Scenario: Mixed file name
- **WHEN** a recording started at 2026-10-10 14:30:05 local time is saved as AAC
- **THEN** the file is named `kRecord 2026-10-10 14-30-05.m4a`

#### Scenario: Separate file names
- **WHEN** the same recording is saved in separate-files mode
- **THEN** the files are named `kRecord 2026-10-10 14-30-05 (mic).m4a` and `kRecord 2026-10-10 14-30-05 (system).m4a`

#### Scenario: Raw AAC file name
- **WHEN** the same recording is saved with "Save as m4a" off
- **THEN** the file is named `kRecord 2026-10-10 14-30-05.aac`

#### Scenario: Name collision
- **WHEN** a file with the target name already exists in the destination folder
- **THEN** the new file is saved as `kRecord 2026-10-10 14-30-05 2.m4a` and the existing file is unchanged

### Requirement: Crash-safe recording
While a recording is active, the encoded AAC stream SHALL be written to disk incrementally in the destination folder, under the recording's final name with the `.aac` extension, so that, if the app terminates unexpectedly, the audio recorded up to that point remains in a playable file.

#### Scenario: App killed during recording
- **WHEN** the app is force-quit 5 minutes into a recording
- **THEN** a playable `.aac` file containing approximately the first 5 minutes remains in the destination folder

#### Scenario: Normal stop leaves only final files
- **WHEN** a recording is stopped normally
- **THEN** only the final output file(s) remain in the destination folder; when saved as `.m4a`, the `.aac` stream is removed

### Requirement: Stop with error on storage failure
If the destination volume runs out of space or the destination folder becomes unavailable during a recording, the system SHALL stop the recording, keep all audio written so far, and report an error to the user.

#### Scenario: Disk full
- **WHEN** the destination volume runs out of free space during a recording
- **THEN** the recording stops
- **AND** the user sees an error explaining that disk space ran out

#### Scenario: Destination folder removed
- **WHEN** the destination folder is on an external drive that is ejected during a recording
- **THEN** the recording stops and the user sees an error explaining that the folder is unavailable

### Requirement: Start blocked when destination unavailable
The system SHALL NOT start a recording if the destination folder cannot be created or written to, and SHALL report an error instead.

#### Scenario: Unwritable folder
- **WHEN** the destination folder is not writable and the user presses Record
- **THEN** no recording starts and the user sees an error explaining the folder cannot be written to

### Requirement: Default destination folder created on demand
If the destination folder does not exist when a recording starts, the system SHALL create it.

#### Scenario: First recording
- **WHEN** `~/Music/kRecord/` does not exist and the user starts the first recording with default settings
- **THEN** the folder is created and the recording is saved there
