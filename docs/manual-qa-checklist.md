# kRecord manual QA checklist

Checks for behavior that unit tests cannot cover: real audio hardware, macOS permissions, UI, and file system failures. Each capability section lists its checks as `- [ ]` items; later development tasks append items to the matching section.

## How to run

1. Build and run a **Development-signed** build from Xcode (⌘R). Ad-hoc builds get new permission prompts after every rebuild, which hides permission bugs.
2. Before a full pass, reset permissions so first-launch behavior is tested:
   `tccutil reset Microphone com.kozian.kRecord` and `tccutil reset AudioCapture com.kozian.kRecord`.
3. Work through the sections in order. Mark each item `- [x]` when it passes; for a failure, leave it unchecked and add a short note below the item.
4. Record the results at the end of this file.

### Test environment

- Apple silicon Mac on macOS 15 or later (record the exact version in the results).
- System language English; switch to Russian and German for the Localization section.

### Required hardware

- A second microphone (USB microphone or headset) in addition to the default input device.
- Headphones (wired or Bluetooth) to test output device changes.
- Built-in or external speakers to test echo cancellation.
- An external drive (USB stick or disk) to test ejecting the destination folder's volume. A small one, or a disk image, also helps with the disk-full test.
- An app that plays audio (Music, a browser video) and, ideally, a second one to play audio at the same time.

## Audio capture

- [ ] **Both sources, clap test.** Play music through the speakers, start a 60 s recording with separate files, clap twice near the microphone at the start and twice at the end. Open both files in an audio editor at position zero: voice and music are present, and the claps (and the music heard through the microphone) line up with the system track equally well at the start and at the end.
- [ ] **Start in silence.** With no app playing audio for at least a minute, start a recording, wait 10 s, then play audio. The file starts at the moment Record was pressed (the first 10 s contain the microphone), not when the audio started.
- [ ] **Long silence.** Record 2 minutes, playing audio only during the first and last 10 s. The file is 2 minutes long without gaps.
- [ ] **Two apps.** Play audio in two apps at once (e.g. Music and a browser video): both are audible in the system track.
- [ ] **Stereo image.** Play a test file panned hard left: in the system track (separate-files mode) it is in the left channel only.
- [ ] **Multichannel interface.** With a multichannel audio interface as the input, the microphone track is mono and contains the interface's first input.
- [ ] **Default input changes.** With the microphone set to "System Default", start recording and switch the input device in System Settings → Sound → Input. The recording continues and the new device is recorded after a gap of well under a second.
- [ ] **Selected microphone unplugged.** Select a USB microphone explicitly, start recording, unplug it, then plug it back in. The recording continues throughout: after unplugging, the default input is recorded (or silence on a Mac without another input); after plugging back in, the USB microphone is recorded again. The selection is still the USB microphone afterwards.
- [ ] **Selected microphone missing at start.** With the selected USB microphone unplugged, start a recording: it starts with the default input.
- [ ] **Output device changes.** During a recording, connect headphones (or switch output in System Settings) and play audio: system audio is still recorded, without a gap longer than a second.
- [ ] **Aggregate device as input.** Create an aggregate device in Audio MIDI Setup, set it as the input, and record: the recording starts (falling back to the default input or to system audio only) instead of failing.
- [ ] **Echo cancellation.** Enable echo cancellation, play speech through the built-in speakers (no headphones), and record 30 s in separate-files mode without speaking. Repeat with echo cancellation off. The microphone track with echo cancellation contains clearly less of the played speech. Note: other audio is played and recorded about 8 dB quieter while echo cancellation is on (expected, design D6).
- [ ] **Echo cancellation alignment.** With echo cancellation on, record separate files while speaking and playing music; in an audio editor the voice in both tracks (direct and via speakers) lines up to within about 10 ms. Repeat with a second microphone model if available.
- [ ] **Echo cancellation keeps your voice.** With echo cancellation on and audio playing through the speakers, speak normally: your voice is clearly present in the microphone track.
- [ ] **Level meters.** While recording, speaking moves only the microphone meter, and playing audio moves only the system audio meter.

## Recording output

- [ ] **Disk full.** Create a small disk image (Disk Utility → New Image, 300 MB), mount it, set it as the destination folder, and fill it with a large file until about 110 MB are free. Record (with a few apps playing audio, it takes a while at about 1 MB per minute; copying more files onto the image speeds it up): within about 10 s after free space drops below 100 MB the recording stops, an error says disk space ran out, and the audio recorded so far is saved as `.m4a` or, if that fails, kept as `.aac`.
- [ ] **External drive ejected.** Set a folder on a USB drive as the destination, start recording, and eject the drive in Finder (force-eject if needed). The recording stops within about 5 s with an error that the folder is unavailable; the app keeps working and the next recording to an available folder succeeds.
- [ ] **Default output.** Record 30 s with default settings: one `kRecord <date> <time>.m4a` file appears, no `.aac` is left, saving takes well under a second, and QuickTime shows the correct duration.
- [ ] **Save as m4a off.** Turn off "Save as m4a" and record: a `.aac` file is saved and plays in QuickTime and Music (players may show an approximate duration for `.aac`).
- [ ] **Separate files.** With separate files on, record with "Save as m4a" on and then off: `(mic)` and `(system)` files appear with the matching extension; the microphone file is mono and the system file stereo; they line up when placed at the same position in an audio editor.
- [ ] **Name collision.** Make two recordings within the same second (start, stop, start again immediately; or rename an existing file to the next recording's name): the new file gets a ` 2` suffix and the existing file is unchanged.
- [ ] **Crash safety.** Start a recording, wait 1 minute, and force-quit kRecord (Activity Monitor → Force Quit). The `kRecord <date> <time>.aac` file in the destination folder plays in QuickTime and contains about the first minute.
- [ ] **Unwritable folder.** Choose a folder, then make it read-only in Finder (Get Info → Sharing & Permissions → Read only). Press Record: no recording starts and an error says the folder cannot be written to.

## Recording session

## Main window

## Menu bar

## Settings

- [ ] **Microphone list, hot-plug.** With the main window or Settings open, plug in a USB microphone: it appears in the microphone picker within about a second. Unplug it: it disappears from the list (a remembered selection stays visible as unavailable, see the main window section).
- [ ] **No aggregate devices.** Create an aggregate device in Audio MIDI Setup: it does not appear in the microphone picker, and neither does "kRecord Capture" during a recording.

## Permissions

## Localization

## Results

| Date | macOS version | Mac model | Tester | Result | Notes |
|------|---------------|-----------|--------|--------|-------|
