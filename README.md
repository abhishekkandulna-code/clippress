# ClipPress

A small macOS app that joins video clips into one file and compresses it. It uses Apple's
built-in AVFoundation and the Mac's hardware video encoder (VideoToolbox), so there are no
third-party dependencies, and the whole app is only a few MB.

## Features

- **Timeline:** drop or choose MP4, MOV and M4V files. They are joined in order into one video.
  Reorder them with the arrow buttons or remove them. A strip shows each clip to scale.
  Portrait and landscape clips are rotated upright and letterboxed into one frame size.
- **Speed:** one decimal value for the whole timeline, from 0.1× to 10× (e.g. 1.25, 0.5).
  Audio is time-stretched so voices keep their pitch.
- **Volume:** one decimal gain for the whole timeline, from 0× to 4×. 0 removes the sound;
  above 1 boosts it, and peaks past full scale are clipped.
- Quality: Smaller, Balanced or Better. Format: H.264 (plays everywhere) or HEVC (about 40%
  smaller). Resolution: Original, 1080p, 720p or 480p.
- Live size estimate before exporting, progress with time left and elapsed time, and cancel.
- Output is an MP4. HDR footage is converted to standard colour.

## Long videos (hours)

- Video is streamed frame by frame, so memory use stays flat whatever the length.
- The Mac is kept from idle-sleeping while an export runs.
- Free space on the destination disk is checked before starting.
- Quitting during an export asks first, and deletes the unfinished file if you stop.
- Outputs over an hour skip the "fast start" pass that moves the index to the front of the
  file. That pass rewrites the whole file at the end, which on a multi-GB export takes
  minutes with no progress. Shorter outputs keep it, so they start playing instantly online.

## Build and run (on a Mac)

Requires macOS 13 or later and Xcode 15+ (or its Command Line Tools).

```sh
./scripts/build-app.sh          # creates build/ClipPress.app (universal: Apple Silicon + Intel)
open build/ClipPress.app

./scripts/make-dmg.sh           # creates build/ClipPress-1.0.dmg for sharing
```

The DMG opens to the app and an Applications shortcut; drag one onto the other to install.
The app is only ad-hoc signed, so on another Mac the first launch needs right-click → **Open**
(or `xattr -dr com.apple.quarantine /Applications/ClipPress.app`). Signing with a Developer ID
and notarizing removes that step.

During development you can run it directly with `swift run`, or open `Package.swift` in Xcode
and press Run.

## Layout

| File | What it does |
|---|---|
| `Sources/ClipPress/Clip.swift` | Reads a video's tracks, size, rotation, frame rate and thumbnail |
| `Sources/ClipPress/Exporter.swift` | Output settings, size estimate, joining and hardware encoding |
| `Sources/ClipPress/AppModel.swift` | App state: clips, settings, import, export, errors |
| `Sources/ClipPress/ContentView.swift` | Window layout and the clip list |
| `Sources/ClipPress/OutputPanel.swift` | Settings, estimate, progress and the export button |
| `Sources/ClipPress/Components.swift` | Buttons, tabs, checkbox, notification, progress bar |
| `Sources/ClipPress/Theme.swift`, `Icons.swift` | Kennect design tokens, Poppins font, Tabler-style icons |

## Limits

- Only formats macOS can read natively. MKV, AVI and WebM files are rejected with a message.
- Clips are joined with straight cuts; there are no transitions or trimming yet.
- Speed and volume apply to the whole timeline, not to individual clips.
- If the app crashes or the Mac loses power mid-export, the partial MP4 can't be played;
  the export has to be started again.

Poppins is licensed under the SIL Open Font License (`Resources/Fonts/OFL.txt`).
