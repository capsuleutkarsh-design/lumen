# Third-party notices

Lumen · © 2026 Utkarsh Tripathi · UT Community Licence 2.0

Lumen uses and credits the following work.

## Bundled with the app

| Component | What it is | Licence |
|---|---|---|
| [Inter](https://github.com/rsms/inter) 4.1 by Rasmus Andersson and the Inter Project Authors | The app's font (`assets/fonts/Inter-*.ttf`) | SIL Open Font License 1.1, full text in [`assets/fonts/Inter-OFL.txt`](assets/fonts/Inter-OFL.txt) |
| [FFmpeg](https://ffmpeg.org) 8.1.3, inside Lumen's audio engine `libmpv-2.dll` | Audio decoding, filters (EQ, crossfeed, limiter, ...) | LGPL-3.0-or-later (built with `--enable-version3`, without `--enable-gpl`), text in `LGPL-3.0.txt` and `GPL-3.0.txt` |
| [mpv](https://mpv.io) 0.41.0 (libmpv), in `libmpv-2.dll` | Playback and audio output | LGPL-2.1-or-later |
| [libplacebo](https://code.videolan.org/videolan/libplacebo) 7.360.1 (with [fast_float](https://github.com/fastfloat/fast_float)), in `libmpv-2.dll` | Needed to build mpv | LGPL-2.1-or-later (fast_float: MIT / Apache-2.0 / BSL-1.0) |
| [libsoxr](https://sourceforge.net/projects/soxr/) 0.1.3, in `libmpv-2.dll` | High-quality resampler | LGPL-2.1-or-later |
| [libbs2b](http://bs2b.sourceforge.net) 3.1.0, in `libmpv-2.dll` | Headphone crossfeed | MIT, Copyright (c) 2005 Boris Mikhaylov |
| [libass](https://github.com/libass/libass) 0.17.5, [HarfBuzz](https://harfbuzz.github.io) 14.6.0, [FreeType](https://freetype.org) 2.14.3, [FriBidi](https://github.com/fribidi/fribidi) 1.0.17, in `libmpv-2.dll` | Needed to build mpv (subtitle text, not used by Lumen) | ISC; MIT; FreeType License (FTL); LGPL-2.1-or-later |
| [zlib](https://zlib.net) 1.3.2, in `libmpv-2.dll` | Compressed tags and containers | zlib |
| [llvm-mingw](https://github.com/mstorsjo/llvm-mingw) runtime (libc++, libunwind, compiler-rt, mingw-w64 CRT), in `libmpv-2.dll` | Compiler runtime | Apache-2.0 WITH LLVM-exception; mingw-w64 runtime licence |
| Microsoft Visual C++ runtime (`msvcp140*.dll`, `vcruntime140*.dll`, `concrt140.dll`) | C++ runtime for `lumen.exe` and the plugins | Microsoft Visual C++ Redistributable, distributed under the Visual Studio licence terms |
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

### Lumen's audio engine (`libmpv-2.dll`)

- **What it is:** mpv and FFmpeg built for audio only, with Lumen's audio filters and the soxr resampler. Network protocols are switched off; it opens local files only.
- **Source code:** every release of [capsuleutkarsh-design/lumen-audio-engine](https://github.com/capsuleutkarsh-design/lumen-audio-engine/releases) has the complete corresponding source (`lumen-audio-engine-<tag>-source.tar`: the exact source tarballs, the build script and the configure lines). The release this version of Lumen uses is named in `windows/CMakeLists.txt` (`LUMEN_ENGINE_TAG`).
- **Licence texts:** `LGPL-3.0.txt` and `GPL-3.0.txt` sit next to `lumen.exe`. The licence of every library inside the DLL is in [`licenses/`](licenses/) and in the app (Credits, All package licences).
- Portions of this software are copyright © 2026 The FreeType Project (https://freetype.org). All rights reserved.
- The engine has no TLS library, so the mbedTLS notice of the old build no longer applies.

## Design credit

The layout and feel are inspired by [Wora](https://github.com/playwora/wora) (MIT licence, Copyright (c) 2024 Wora; full text in [`docs/study/wora/LICENSE`](docs/study/wora/LICENSE)). No Wora code is used; its screenshots in `docs/study/wora/` are kept only as a design reference.

## Test material (not shipped)

Local tests use generated test tones and music from Wikimedia Commons. They are kept outside the repository and are not part of Lumen.

You may replace the LGPL libraries (libmpv, FFmpeg) with your own builds: `libmpv-2.dll` sits next to the program.
