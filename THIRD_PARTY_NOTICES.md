# Third-party notices

Gleo · © 2026 Utkarsh Tripathi · UT Community Licence 2.0

Gleo uses and credits the following work.

## Bundled with the app

| Component | What it is | Licence |
|---|---|---|
| [Inter](https://github.com/rsms/inter) 4.1 by Rasmus Andersson and the Inter Project Authors | The app's font (`assets/fonts/Inter-*.ttf`) | SIL Open Font License 1.1, full text in [`assets/fonts/Inter-OFL.txt`](assets/fonts/Inter-OFL.txt) |
| [Outfit](https://github.com/Outfitio/Outfit-Fonts) by the Outfit Project Authors | The letters of the Gleo logo and wordmark, drawn as shapes (the font file itself is not in the app; `tool/brand/make_logo.py` reads it from `tool/brand/fonts/`) | SIL Open Font License 1.1, full text in [`tool/brand/fonts/OFL.txt`](tool/brand/fonts/OFL.txt) |
| [FFmpeg](https://ffmpeg.org) 8.1.3, inside Gleo's audio engine `libmpv-2.dll` | Audio decoding, filters (EQ, crossfeed, limiter, ...) | LGPL-3.0-or-later (built with `--enable-version3`, without `--enable-gpl`), text in `LGPL-3.0.txt` and `GPL-3.0.txt` |
| [mpv](https://mpv.io) 0.41.0 (libmpv), in `libmpv-2.dll` | Playback and audio output | LGPL-2.1-or-later |
| [libplacebo](https://code.videolan.org/videolan/libplacebo) 7.360.1 (with [fast_float](https://github.com/fastfloat/fast_float)), in `libmpv-2.dll` | Needed to build mpv | LGPL-2.1-or-later (fast_float: MIT / Apache-2.0 / BSL-1.0) |
| [libsoxr](https://sourceforge.net/projects/soxr/) 0.1.3, in `libmpv-2.dll` | High-quality resampler | LGPL-2.1-or-later |
| [libbs2b](http://bs2b.sourceforge.net) 3.1.0, in `libmpv-2.dll` | Headphone crossfeed | MIT, Copyright (c) 2005 Boris Mikhaylov |
| [libass](https://github.com/libass/libass) 0.17.5, [HarfBuzz](https://harfbuzz.github.io) 14.6.0, [FreeType](https://freetype.org) 2.14.3, [FriBidi](https://github.com/fribidi/fribidi) 1.0.17, in `libmpv-2.dll` | Needed to build mpv (subtitle text, not used by Gleo) | ISC; MIT; FreeType License (FTL); LGPL-2.1-or-later |
| [zlib](https://zlib.net) 1.3.2, in `libmpv-2.dll` | Compressed tags and containers | zlib |
| [llvm-mingw](https://github.com/mstorsjo/llvm-mingw) runtime (libc++, libunwind, compiler-rt, mingw-w64 CRT), in `libmpv-2.dll` | Compiler runtime | Apache-2.0 WITH LLVM-exception; mingw-w64 runtime licence |
| Gleo's audio engine for Android, `libmpv.so` (arm64-v8a, armeabi-v7a, x86_64) | The same FFmpeg, mpv, libplacebo, libsoxr, libbs2b, libass, HarfBuzz, FreeType, FriBidi and zlib as above, built for Android | As above |
| [Android NDK](https://developer.android.com/ndk) r28c runtime (libc++, libc++abi, libunwind, compiler-rt), in `libmpv.so` | Compiler runtime (Android) | Apache-2.0 WITH LLVM-exception |
| Microsoft Visual C++ runtime (`msvcp140*.dll`, `vcruntime140*.dll`, `concrt140.dll`) | C++ runtime for `gleo.exe` and the plugins | Microsoft Visual C++ Redistributable, distributed under the Visual Studio licence terms |
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
| [tray_manager](https://pub.dev/packages/tray_manager) 0.5.3, [menu_base](https://pub.dev/packages/menu_base) | The tray icon and its menu (a plain C++ plugin) | MIT |
| [shortid](https://pub.dev/packages/shortid), pulled in by tray_manager | | BSD 3-Clause |
| [audio_service](https://pub.dev/packages/audio_service), [audio_session](https://pub.dev/packages/audio_session) | Android: background playback, the media notification and lock screen controls, audio focus | MIT |
| [flutter_cache_manager](https://pub.dev/packages/flutter_cache_manager), pulled in by audio_service | | MIT |
| [sqflite](https://pub.dev/packages/sqflite), pulled in by flutter_cache_manager | | BSD 2-Clause |
| [rxdart](https://pub.dev/packages/rxdart), pulled in by audio_service | | Apache 2.0 |
| [js](https://pub.dev/packages/js), pulled in by audio_service_web | Not used on Windows or Android | BSD 3-Clause |
| [Flutter](https://flutter.dev) engine and framework | UI toolkit | BSD 3-Clause |

The full licence texts of the Dart and Flutter packages are kept in each package and are bundled into the app by Flutter (`NOTICES` in the build output).

### Gleo's audio engine (`libmpv-2.dll` on Windows, `libmpv.so` on Android)

- **What it is:** mpv and FFmpeg built for audio only, with Gleo's audio filters and the soxr resampler. Network protocols are switched off; it opens local files only.
- **Source code:** every release of [capsuleutkarsh-design/lumen-audio-engine](https://github.com/capsuleutkarsh-design/lumen-audio-engine/releases) has the complete corresponding source (`lumen-audio-engine-<tag>-source.tar`: the exact source tarballs, the build script and the configure lines). The releases this version of Gleo uses are named in `windows/CMakeLists.txt` (`GLEO_ENGINE_TAG`) and `android/app/build.gradle.kts` (`gleoEngineTag`, a `-android` release).
- **Licence texts:** `LGPL-3.0.txt` and `GPL-3.0.txt` sit next to `gleo.exe`. The licence of every library inside the DLL and `libmpv.so` is in [`licenses/`](licenses/) and in the app (Credits, All package licences).
- Portions of this software are copyright © 2026 The FreeType Project (https://freetype.org). All rights reserved.
- On Android, `libmediakitandroidhelper.so` next to `libmpv.so` is media_kit's own helper (MIT), from media_kit_libs_android_audio.
- The engine has no TLS library, so the mbedTLS notice of the old build no longer applies.

## Design credit

The layout and feel are inspired by [Wora](https://github.com/playwora/wora) (MIT licence, Copyright (c) 2024 Wora; full text in [`docs/study/wora/LICENSE`](docs/study/wora/LICENSE)). No Wora code is used; its screenshots in `docs/study/wora/` are kept only as a design reference.

## Test material (not shipped)

Local tests use generated test tones and music from Wikimedia Commons. They are kept outside the repository and are not part of Gleo.

You may replace the LGPL libraries (libmpv, FFmpeg) with your own builds: `libmpv-2.dll` sits next to the program, and on Android `lib/<abi>/libmpv.so` can be swapped in the APK (then re-sign it).

## Cover art: Masterpieces pack

`assets/covers/masterpieces/` holds 100 square crops (768 px) of paintings and prints from [Wikimedia Commons](https://commons.wikimedia.org). Every work is in the public domain everywhere: each artist died before 1926 (life + 100 years), every work was published long before 1931 (US), and each Commons file carries a public-domain tag (PD-Art / PD-old-100 / PD-old-auto-expired or similar). The crops are faithful reproductions, so they add no new copyright.

`assets/covers/masterpieces/credits.json` lists every file with its title, artist, year, the artist's death year, the Commons page it came from and its licence tag. Gleo shows the title and artist when one of these is used as a cover. Artists: Vincent van Gogh, Katsushika Hokusai, Utagawa Hiroshige, Gustav Klimt, J. M. W. Turner, Caspar David Friedrich, Georges Seurat, Paul Cézanne, Pierre-Auguste Renoir, Edgar Degas, Paul Gauguin, Alfred Sisley, Camille Pissarro, Berthe Morisot, Gustave Caillebotte, Henri-Edmond Cross, Odilon Redon, Henri Rousseau, Arnold Böcklin, Mikalojus Konstantinas Čiurlionis, John William Waterhouse, John Atkinson Grimshaw, James McNeill Whistler, Ivan Aivazovsky, Peder Balke, Winslow Homer, Gustave Courbet, Frederic Edwin Church, Albert Bierstadt, Thomas Cole, Isaac Levitan, Ivan Shishkin, Egon Schiele, Vilhelm Hammershøi, Franz Marc, August Macke, Ogata Kōrin, Itō Jakuchū, Albrecht Dürer, Rachel Ruysch, Ernst Haeckel and Pierre-Joseph Redouté.

The painted cover styles (`lib/art/painted.dart`) are drawn by Gleo's own code and copy no artwork.

## Cover art: Illustrated pack

Illustrated cover pack: made for Gleo by Utkarsh Tripathi with Magnific AI.

`assets/covers/illustrated/` holds 100 storybook illustrations (768 px), made for Gleo by its author with [Magnific AI](https://www.magnific.com) on his own account. `assets/covers/illustrated/credits.json` lists each file with its title, the prompt it was made from, the date and the line "Made with Magnific AI for Gleo", which Gleo shows when one is used as a cover.
