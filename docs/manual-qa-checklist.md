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

## Recording output

## Recording session

## Main window

## Menu bar

## Settings

## Permissions

## Localization

## Results

| Date | macOS version | Mac model | Tester | Result | Notes |
|------|---------------|-----------|--------|--------|-------|
