# Music player: plan

A beautiful, fast music player for lossless libraries. **Windows first**, Android later from the same code.

Inspired by [Wora](https://github.com/playwora/wora) (MIT licence: ideas and design may be reused, with credit), and fixing what the owner found broken there.

## What's wrong in Wora (owner's findings)

| Problem | Likely cause in Wora | Our fix |
|---|---|---|
| **Can't seek in FLAC** | It plays through the browser's `<audio>` via a custom file protocol. Seeking needs byte-range reads, and FLAC needs a seek table; without both, seeking fails. | A native engine (libmpv) reads the file directly and seeks by sample, with or without a seek table. |
| **Next / previous are bad** | A simple list index; no real play queue. | A real **play queue**: "Play next", "Add to queue", history for Previous (Previous restarts the track if more than 3 s in), shuffle that never repeats until all have played, repeat one/all, and gapless playback to the next track. |
| **Library and its management are bad** | A slow JS scan, with tags read on the UI thread. | A background scanner into a local SQLite database: watch folders, rescan only changed files, albums/artists/genres/years, "Various Artists" and disc numbers handled, edit tags, find duplicates and missing files, multiple library folders. |
| **Bad suggestions** | – | Local, explainable suggestions from your own listening (no AI, no internet): play counts, skips, time of day, same artist/album/genre/year, "not played lately", "forgotten favourites". |

## Features

### v1: a solid player
- Every lossless format: FLAC (any rate), ALAC, WAV, AIFF, APE, WavPack, DSD, plus MP3/AAC/Opus/OGG.
- Gapless playback, accurate seeking, ReplayGain (track/album).
- **Windows:** WASAPI exclusive / bit-perfect output, an output device picker, and a format badge (e.g. "FLAC 24/96").
- A library from folders, a fast background scan, search, and a command palette (Ctrl+K) for quick play.
- The queue as above, plus playlists (create, reorder, import/export M3U).
- A beautiful UI: big cover art, background colours from the cover, a mini player, a dark/light theme.
- Media keys and Windows media controls (the volume overlay and lock screen).

### v2
- Synced lyrics (LRC files, embedded tags), `.cue` sheets, an equalizer (parametric presets), crossfade (optional, off for gapless albums).
- A tag editor, cover art fetch from folder images, smart playlists (rules), statistics.

### v3: Android
- The same app for Android: background playback, notification and lock-screen controls, USB DAC support, and folder access.

## Tech

**Flutter (Dart) + `media_kit` (libmpv)** for playback, **SQLite** for the library, and a native tag reader for fast scans.
- One codebase gives Windows now and Android later.
- libmpv handles formats, gapless, seeking and WASAPI exclusive mode.

## Setup checklist (Windows build)
- [x] Git
- [x] Visual Studio 2022: check that the "Desktop development with C++" workload is installed
- [x] Android Studio + Android SDK (for later)
- [x] Flutter SDK 3.47.7 in `C:devlutter` (on PATH, analytics off)
- [ ] Flutter + Dart plugins in Android Studio
- [x] `flutter doctor` all green for Windows; empty app builds
- [ ] Android: cmdline-tools + `flutter doctor --android-licenses` (owner)
