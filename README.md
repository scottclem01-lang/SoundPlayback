# SoundPlayback

macOS multi-track music playback for TV / interface output. Timeline-first: import, place, trim, route — no inputs, EQ, or effects.

## Locked decisions (v1)

- **Stereo import** → split L/R onto separate mono tracks
- **Tracks** → default 4, add more as needed
- **Routing** → each track can feed any combination of outs 1–4 (unavailable outs grayed by device channel count)
- **Transport**
  - Space → play / stop (stop returns to last start point)
  - `P` → pause (resume continues from pause position)
  - Click ruler (above tracks) → set start point; drag → scrub
- **Markers** → `M` drops a numbered marker at the playhead / start point
  - Digits `1`–`9` / `0` → jump to markers 1–10
  - `Shift` + digit → markers 11–20 (`Shift+4` = 14, `Shift+0` = 20)
- **Sessions** → save / reopen (`.soundplayback`)
- **Output device** → app-selected Core Audio device (independent of System Settings)

## Requirements

- macOS 14+
- Swift 5.9+

## Build & run

```bash
cd ~/Documents/GitHub/SoundPlayback
swift build
swift run SoundPlayback
```

Or open `Package.swift` in Xcode and run the `SoundPlayback` target.

## Current scaffold

UI shell + session model + device enumeration. Still to wire: real WAV/MP3 decode + stereo split, waveform peaks, clip drag/trim/move, and Core Audio playback to the selected outs.
