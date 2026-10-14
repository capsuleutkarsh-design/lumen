# Third-party notices

Lumen · © 2026 Utkarsh Tripathi · UT Community Licence 2.0

Lumen uses and credits the following work.

## Bundled with the app

| Component | What it is | Licence |
|---|---|---|
| [Inter](https://github.com/rsms/inter) 4.1 by Rasmus Andersson and the Inter Project Authors | The app's font (`assets/fonts/Inter-*.ttf`) | SIL Open Font License 1.1, full text in [`assets/fonts/Inter-OFL.txt`](assets/fonts/Inter-OFL.txt) |
| [libmpv](https://mpv.io) and [FFmpeg](https://ffmpeg.org), audio-only builds shipped by `media_kit_libs_windows_audio` | Audio decoding and output (`libmpv-2.dll`) | LGPL 2.1 or later |
| [SQLite](https://sqlite.org) | The library database (`sqlite3.dll`) | Public domain |
| [Lucide](https://lucide.dev) icons, via `lucide_icons_flutter` | Icons | ISC (icons), MIT (package) |
| [media_kit](https://github.com/media-kit/media-kit), media_kit_libs_audio | Dart bindings for libmpv | MIT |
| [sqlite3](https://pub.dev/packages/sqlite3) (Dart) | SQLite bindings | MIT |
| [window_manager](https://pub.dev/packages/window_manager), screen_retriever | Frameless window | MIT |
| [image](https://pub.dev/packages/image) | Cover thumbnails | MIT |
| [file_selector](https://pub.dev/packages/file_selector), [path_provider](https://pub.dev/packages/path_provider), [path](https://pub.dev/packages/path), [ffi](https://pub.dev/packages/ffi), [crypto](https://pub.dev/packages/crypto) | Folder/file pickers, app data folder, paths, fast folder listing on Windows, the licence check | BSD 3-Clause (Flutter / Dart authors) |
| [desktop_drop](https://pub.dev/packages/desktop_drop) | Drag and drop from Explorer | Apache 2.0 |
| [dbus](https://pub.dev/packages/dbus) (Dart), pulled in by desktop_drop for Linux | Unmodified; not used on Windows. Source: pub.dev | Mozilla Public License 2.0 |
| [xml](https://pub.dev/packages/xml), [petitparser](https://pub.dev/packages/petitparser), pulled in by dbus | | MIT |
| [Flutter](https://flutter.dev) engine and framework | UI toolkit | BSD 3-Clause |

The full licence texts of the Dart and Flutter packages are kept in each package and are bundled into the app by Flutter (`NOTICES` in the build output).

## Design credit

The layout and feel are inspired by [Wora](https://github.com/playwora/wora) (MIT licence, Copyright (c) 2024 Wora; full text in [`docs/study/wora/LICENSE`](docs/study/wora/LICENSE)). No Wora code is used; its screenshots in `docs/study/wora/` are kept only as a design reference.

## Test material (not shipped)

Local tests use generated test tones and music from Wikimedia Commons. They are kept outside the repository and are not part of Lumen.

You may replace the LGPL libraries (libmpv, FFmpeg) with your own builds: `libmpv-2.dll` sits next to the program.
