# Third-party notices

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
| [file_selector](https://pub.dev/packages/file_selector), [path_provider](https://pub.dev/packages/path_provider), [path](https://pub.dev/packages/path) | Folder/file pickers, app data folder, paths | BSD 3-Clause (Flutter / Dart authors) |
| [Flutter](https://flutter.dev) engine and framework | UI toolkit | BSD 3-Clause |

The full licence texts of the Dart and Flutter packages are kept in each package and are bundled into the app by Flutter (`NOTICES` in the build output).

## Design credit

The layout and feel are inspired by [Wora](https://github.com/playwora/wora) by its authors (MIT licence). No Wora code is used; its screenshots in `docs/study/wora/` are kept only as a design reference.

## Test material (not shipped)

`_scratch/` (git-ignored) holds generated test tones and music from Wikimedia Commons used only for local testing; see `_scratch/real_music/CREDITS.txt`.

You may replace the LGPL libraries (libmpv, FFmpeg) with your own builds: `libmpv-2.dll` sits next to the program.

## Cover art: Masterpieces pack

`assets/covers/masterpieces/` holds 100 square crops (768 px) of paintings and prints from [Wikimedia Commons](https://commons.wikimedia.org). Every work is in the public domain everywhere: each artist died before 1926 (life + 100 years), every work was published long before 1931 (US), and each Commons file carries a public-domain tag (PD-Art / PD-old-100 / PD-old-auto-expired or similar). The crops are faithful reproductions, so they add no new copyright.

`assets/covers/masterpieces/credits.json` lists every file with its title, artist, year, the artist's death year, the Commons page it came from and its licence tag. Lumen shows the title and artist when one of these is used as a cover. Artists: Vincent van Gogh, Katsushika Hokusai, Utagawa Hiroshige, Gustav Klimt, J. M. W. Turner, Caspar David Friedrich, Georges Seurat, Paul Cézanne, Pierre-Auguste Renoir, Edgar Degas, Paul Gauguin, Alfred Sisley, Camille Pissarro, Berthe Morisot, Gustave Caillebotte, Henri-Edmond Cross, Odilon Redon, Henri Rousseau, Arnold Böcklin, Mikalojus Konstantinas Čiurlionis, John William Waterhouse, John Atkinson Grimshaw, James McNeill Whistler, Ivan Aivazovsky, Peder Balke, Winslow Homer, Gustave Courbet, Frederic Edwin Church, Albert Bierstadt, Thomas Cole, Isaac Levitan, Ivan Shishkin, Egon Schiele, Vilhelm Hammershøi, Franz Marc, August Macke, Ogata Kōrin, Itō Jakuchū, Albrecht Dürer, Rachel Ruysch, Ernst Haeckel and Pierre-Joseph Redouté.

The painted cover styles (`lib/art/painted.dart`) are drawn by Lumen's own code and copy no artwork.
