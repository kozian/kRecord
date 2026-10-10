# Spec Delta

## Purpose

Turns captured audio into files on disk: chooses format and layout (mixed or separate), names and places files, keeps in-progress recordings safe, and handles storage failures.

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

### Requirement: Output formats
The system SHALL support these output formats: AAC in an `.m4a` container (default), Apple Lossless (ALAC) in an `.m4a` container, and uncompressed WAV (`.wav`). Recordings SHALL use a 48 kHz sample rate. AAC SHALL be encoded at 128 kbps or higher.

#### Scenario: Default format
- **WHEN** a recording is stopped with default settings
- **THEN** the file is AAC audio with the `.m4a` extension

#### Scenario: WAV selected
- **WHEN** the WAV format is selected and a recording is stopped
- **THEN** the file is uncompressed PCM audio with the `.wav` extension

#### Scenario: ALAC selected
- **WHEN** the ALAC format is selected and a recording is stopped
- **THEN** the file is Apple Lossless audio with the `.m4a` extension

### Requirement: Automatic saving to destination folder
The system SHALL save recordings automatically to the configured destination folder without prompting the user for a file name or location.

#### Scenario: No save dialog
- **WHEN** the user stops a recording
- **THEN** the file appears in the destination folder without any save dialog

### Requirement: Timestamp-based file names
Files SHALL be named `kRecord YYYY-MM-DD HH-mm-ss.<ext>` using the local start time of the recording. In separate-files mode, names SHALL use the suffixes ` (mic)` and ` (system)` before the extension. If a file with the same name exists, the system SHALL append a numeric suffix and SHALL NOT overwrite existing files.

#### Scenario: Mixed file name
- **WHEN** a recording started at 2026-10-10 14:30:05 local time is saved as AAC
- **THEN** the file is named `kRecord 2026-10-10 14-30-05.m4a`

#### Scenario: Separate file names
- **WHEN** the same recording is saved in separate-files mode
- **THEN** the files are named `kRecord 2026-10-10 14-30-05 (mic).m4a` and `kRecord 2026-10-10 14-30-05 (system).m4a`

#### Scenario: Name collision
- **WHEN** a file with the target name already exists in the destination folder
- **THEN** the new file is saved as `kRecord 2026-10-10 14-30-05 2.m4a` and the existing file is unchanged

### Requirement: Crash-safe recording
While a recording is active, audio SHALL be written to disk incrementally in the destination folder so that, if the app terminates unexpectedly, the audio recorded up to that point remains in a playable file.

#### Scenario: App killed during recording
- **WHEN** the app is force-quit 5 minutes into a recording
- **THEN** a playable audio file containing approximately the first 5 minutes remains in the destination folder

#### Scenario: Normal stop leaves only final files
- **WHEN** a recording is stopped normally
- **THEN** only the final output file(s) remain in the destination folder and no temporary files are left behind

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
