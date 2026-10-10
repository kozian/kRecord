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

- [x] **Both sources, clap test.** Play music through the speakers, start a 60 s recording with separate files, clap twice near the microphone at the start and twice at the end. Open both files in an audio editor at position zero: voice and music are present, and the claps (and the music heard through the microphone) line up with the system track equally well at the start and at the end.
- [x] **Specific microphone.** With two input devices connected, select the one that is not the macOS default in the microphone picker and record: the microphone track comes from the selected device (speak into it and not into the default one), even after changing the default input.
- [ ] **60-minute sync.** Record 60 minutes with both sources in separate-files mode with a clap (or a click track played through the speakers) at the start and at the end; in an audio editor the offset between the tracks is the same at the start and the end. (Run as part of the long meeting recording of the final pass.)
- [x] **Start in silence.** With no app playing audio for at least a minute, start a recording, wait 10 s, then play audio. The file starts at the moment Record was pressed (the first 10 s contain the microphone), not when the audio started.
- [x] **Long silence.** Record 2 minutes, playing audio only during the first and last 10 s. The file is 2 minutes long without gaps.
- [x] **Two apps.** Play audio in two apps at once (e.g. Music and a browser video): both are audible in the system track.
- [x] **Stereo image.** Play a test file panned hard left: in the system track (separate-files mode) it is in the left channel only.
- [x] **Multichannel interface.** With a multichannel audio interface as the input, the microphone track is mono and contains the interface's first input.
- [ ] **Default input changes.** With the microphone set to "System Default", start recording and switch the input device in System Settings → Sound → Input. The recording continues and the new device is recorded after a gap of well under a second.
- [x] **Selected microphone unplugged.** Select a USB microphone explicitly, start recording, unplug it, then plug it back in. The recording continues throughout: after unplugging, the default input is recorded (or silence on a Mac without another input); after plugging back in, the USB microphone is recorded again. The selection is still the USB microphone afterwards.
- [x] **Selected microphone missing at start.** With the selected USB microphone unplugged, start a recording: it starts with the default input.
- [x] **Output device changes.** During a recording, connect headphones (or switch output in System Settings) and play audio: system audio is still recorded, without a gap longer than a second.
- [x] **Aggregate device as input.** Create an aggregate device in Audio MIDI Setup, set it as the input, and record: the recording starts (falling back to the default input or to system audio only) instead of failing.
- [x] **Echo cancellation.** Enable echo cancellation, play speech through the built-in speakers (no headphones), and record 30 s in separate-files mode without speaking. Repeat with echo cancellation off. The microphone track with echo cancellation contains clearly less of the played speech. Note: other audio is played and recorded about 8 dB quieter while echo cancellation is on (expected, design D6).
- [x] **Echo cancellation alignment.** With echo cancellation on, record separate files while speaking and playing music; in an audio editor the voice in both tracks (direct and via speakers) lines up to within about 10 ms. Repeat with a second microphone model if available.
- [x] **Echo cancellation keeps your voice.** With echo cancellation on and audio playing through the speakers, speak normally: your voice is clearly present in the microphone track.
- [x] **Level meters.** While recording, speaking moves only the microphone meter, and playing audio moves only the system audio meter.

## Recording output

- [ ] **Disk full.** Create a small disk image (Disk Utility → New Image, 300 MB), mount it, set it as the destination folder, and fill it with a large file until about 110 MB are free. Record (with a few apps playing audio, it takes a while at about 1 MB per minute; copying more files onto the image speeds it up): within about 10 s after free space drops below 100 MB the recording stops, an error says disk space ran out, and the audio recorded so far is saved as `.m4a` or, if that fails, kept as `.aac`.
- [ ] **External drive ejected.** Set a folder on a USB drive as the destination, start recording, and eject the drive in Finder (force-eject if needed). The recording stops within about 5 s with an error that the folder is unavailable; the app keeps working and the next recording to an available folder succeeds.
- [ ] **Default output.** Record 30 s with default settings: one `kRecord <date> <time>.m4a` file appears in the destination folder without any save dialog, no `.aac` is left, saving takes well under a second, and QuickTime shows the correct duration.
- [ ] **Save as m4a off.** Turn off "Save as m4a" and record: a `.aac` file is saved and plays in QuickTime and Music (players may show an approximate duration for `.aac`).
- [ ] **Separate files.** With separate files on, record with "Save as m4a" on and then off: `(mic)` and `(system)` files appear with the matching extension; the microphone file is mono and the system file stereo; they line up when placed at the same position in an audio editor.
- [ ] **Name collision.** Make two recordings within the same second (start, stop, start again immediately; or rename an existing file to the next recording's name): the new file gets a ` 2` suffix and the existing file is unchanged.
- [ ] **Folder created on demand.** Move `~/Music/kRecord` to the Trash (or rename it), record 10 s with default settings: the folder is created again and contains the recording.
- [ ] **Crash safety.** Start a recording, wait 1 minute, and force-quit kRecord (Activity Monitor → Force Quit). The `kRecord <date> <time>.aac` file in the destination folder plays in QuickTime and contains about the first minute.
- [ ] **Unwritable folder.** Choose a folder, then make it read-only in Finder (Get Info → Sharing & Permissions → Read only). Press Record: no recording starts and an error says the folder cannot be written to.

## Recording session
- [ ] **Quit while idle.** Press ⌘Q (and, separately, choose Quit from the menu bar menu): the app quits at once, without a confirmation.
- [ ] **Quit during a recording.** Record, then press ⌘Q: an alert "Stop recording and quit?" appears with "Stop Recording and Quit" and "Cancel". Cancel keeps the app open and the recording running (the timer keeps counting). Repeat and choose "Stop Recording and Quit": the recording is saved as a complete file and the app quits.
- [ ] **Quit while saving.** Stop a long recording and quit while "Saving…" is shown: the app quits only after the file is saved, without asking.
- [ ] **Microphone off.** Clear "Record microphone" in the main window and record while speaking and playing audio: macOS shows no microphone-in-use indicator for kRecord, the microphone meter stays empty, and the recording contains only system audio (in separate-files mode only the `(system)` file is created).
- [ ] **System audio off.** Clear "Record system audio" and record while playing audio: only the microphone is recorded (in separate-files mode only the `(mic)` file is created).
- [ ] **Both off.** Clear both checkboxes: the record button is disabled with the note "Turn on the microphone or system audio to record.", and "Start Recording" in the menu bar menu is disabled.
- [ ] **Switches remembered and locked.** Clear one checkbox, quit, and relaunch: it is still cleared. During a recording both checkboxes are disabled.
- [ ] **Microphone only, nothing connected.** On a Mac without any input device, turn system audio off and press Record: an error says no microphone is connected.
- [ ] **Shared state.** Start a recording from the menu bar menu: the main window shows it as recording with a running timer. Stop it from the main window: the menu bar icon returns to grey.
- [ ] **Start blocked while saving.** While a recording is being saved, neither the main window button nor the menu item starts a new one.

## Main window
- [ ] **Launch and reopen.** The main window is shown at launch. Close it, then click the Dock icon: it comes back. Close it again and choose Window → kRecord: it comes back.
- [ ] **Closing keeps recording.** Close the window during a recording: the recording continues, the menu bar icon stays red, and reopening the window shows the correct running time.
- [ ] **Record button.** The button shows "Record" (red) when idle, "Stop" while recording, and a disabled "Saving…" with a spinner while the file is saved; the time reads 00:00:00 when idle.
- [ ] **Level meters.** Speaking moves only the "Microphone level" meter and playing audio only the "System audio level" meter; both fall back to empty when quiet.
- [ ] **Microphone picker.** It lists "System Default" and the connected input devices, is disabled during a recording, and shows the same selection as the Settings window (change it in one, check the other). An unplugged selected microphone is shown as "<name> (unavailable)" and is used again after replugging.
- [ ] **Microphone permission warning.** Turn the microphone permission off in System Settings: the window shows a warning with "Open System Settings", which opens Privacy & Security → Microphone. Recording still works (system audio only).
- [ ] **Error display.** Provoke an error (for example eject the destination drive during a recording): the error message appears in the window and stays until dismissed with ✕ or until a new recording starts.
- [ ] **System audio hint.** With the system audio permission off (or simply nothing playing), record 10 s and stop: the hint "No system audio was captured…" appears with "Open System Settings", which opens the pane where the app can be allowed to record system audio; ✕ dismisses it.
- [ ] **Recordings folder button.** Click the folder icon to the right of the microphone picker: the destination folder opens in Finder (also when it does not exist yet, and with a custom folder chosen in Settings). Hovering shows the tooltip "Show Recordings in Finder".
- [ ] **Settings button.** Click the gear icon: the Settings window opens in front. Hovering shows "Settings".
- [ ] **Buttons during a recording.** While recording, both icon buttons work; the microphone picker is disabled.
- [ ] **Narrow window.** In English and Russian the main window shows all texts in full, including "Системный по умолчанию" and an unplugged microphone as "<name> (недоступен)"; hovering the microphone symbol shows "Microphone".

## Menu bar
- [ ] **Icon states.** The menu bar item is present while the app runs, also after closing the main window. It is a grey template icon when idle (check in light and dark appearance, and with a coloured wallpaper) and red while recording.
- [ ] **Time next to the icon.** With "Show recording time in menu bar" on, the elapsed time appears next to the red icon during a recording and updates every second; with it off, only the icon is shown. Toggling it during a recording applies immediately.
- [ ] **Menu contents.** The menu shows exactly "Start Recording" (or "Stop Recording" while recording), "Settings…", and "Quit". The first item is disabled while a recording is being saved.
- [ ] **Settings from the menu.** Make Finder the active app, then choose "Settings…" from the menu bar menu: kRecord becomes active and the Settings window opens in front of other windows (also when it was already open behind them).
- [ ] **Quit from the menu.** "Quit" behaves like ⌘Q, including the confirmation during a recording.

## Settings

- [ ] **Microphone list, hot-plug.** With the main window or Settings open, plug in a USB microphone: it appears in the microphone picker within about a second. Unplug it: it disappears from the list (a remembered selection stays visible as unavailable, see the main window section).
- [ ] **No aggregate devices.** Create an aggregate device in Audio MIDI Setup: it does not appear in the microphone picker, and neither does "kRecord Capture" during a recording.
- [ ] **Window contents.** The Settings window shows the destination folder (with the home folder written as ~), Choose…, Show in Finder, Microphone, Save as m4a, separate files, Echo cancellation, and Show recording time in menu bar.
- [ ] **No scroll bar.** Open Settings (also in Russian and with the "folder unavailable" notice showing): the window fits all settings, shows no scroll bar, and the form does not scroll.
- [ ] **First-launch defaults.** On a clean profile (quit the app, delete `~/Library/Containers/com.kozian.kRecord/Data/Library/Preferences/com.kozian.kRecord.plist`) the folder is `~/Music/kRecord`, microphone is System Default, Save as m4a is on, and the other three switches are off.
- [ ] **Persistence.** Change several settings and a custom folder, quit, relaunch: everything is as left. Record: the file lands in the custom folder without any folder prompt.
- [ ] **Folder deleted while the app is not running.** Choose a custom folder, quit, move the folder to the Trash, relaunch: the Settings window shows `~/Music/kRecord` and a notice that the previous folder is unavailable; ✕ dismisses it, and after another relaunch the notice does not return.
- [ ] **Show in Finder.** The button opens the destination folder in Finder (also the default folder when it does not exist yet).
- [ ] **Locked during recording.** While recording (and while saving) Choose…, Microphone, Save as m4a, separate files, and echo cancellation are disabled; the menu bar time switch and Show in Finder stay usable.

## Permissions
- [ ] **First-launch prompts.** Run `tccutil reset All com.kozian.kRecord`, delete the app preferences file (see Settings), and launch: macOS asks for microphone access and then for system audio recording access, with the texts "kRecord records your microphone into local audio files on this Mac." and "kRecord records system audio (other meeting participants) into local audio files on this Mac.". There is no other onboarding, and the prompts do not return on the next launch.
- [ ] **Granting later.** Deny the microphone, then allow it in System Settings and switch back to the app: the warning disappears without restarting, and the next recording includes the microphone.
- [ ] **Only one source permitted.** With the microphone denied, a recording starts and contains system audio only.
- [ ] **Deep links.** "Open System Settings" next to the microphone warning opens Privacy & Security → Microphone; the one in the system audio hint opens the pane with the system audio recording permission.
- [ ] **No network use.** During a recording `lsof -a -i -p $(pgrep -x kRecord)` lists no network connections.

## Localization
- [ ] **Russian.** Start the app with Russian as the preferred language (System Settings → General → Language & Region, or `open -n kRecord.app --args -AppleLanguages "(ru)"`): the main window, Settings window, menu bar menu, quit alert, error messages, and the permission prompts are Russian, with no English leftovers.
- [ ] **Unsupported language.** With German as the preferred language the whole interface is English.
- [ ] **Long text.** In Russian, check that no text is cut off in the main window banners, the Settings window (including the echo cancellation note), and the quit alert.

## Results

| Date | macOS version | Mac model | Tester | Result | Notes |
|------|---------------|-----------|--------|--------|-------|
| 2026-10-10 | 27.0 | Mac mini (M4 Pro) | project owner | Partial pass, accepted | Audio capture checked (15 of 17; 60-minute sync and default-input switch not run, the switch was verified with the debug harness). Other sections were not run item by item; the app behaved as specified in the edge cases tried. Problems found later are fixed in separate changes. |
