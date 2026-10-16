import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

export '../../audio/sound.dart' show friendlyFormat;

import '../../platform/android.dart' show pickAndroidFolder;
import '../../platform/update.dart';
import '../../platform/window.dart' show isTouch;
import '../../art/art_sources.dart';
import '../app.dart';
import '../disc.dart';
import '../theme.dart';
import '../widgets.dart';
import 'credits.dart';
import 'settings_extras.dart';

/// Asks for a folder and adds it to the library (Settings, the empty Home, drag and drop).
/// On Android the folder may be on the phone or on an SD card / USB stick.
Future<void> addMusicFolder() async {
  final String? dir;
  try {
    dir = Platform.isAndroid ? await pickAndroidFolder() : await getDirectoryPath(confirmButtonText: 'Use this folder');
  } on PlatformException {
    return notify('Gleo can only read folders on the phone or an SD card. Please choose one there.');
  }
  if (dir != null && !lib.folders.contains(dir)) lib.folders = [...lib.folders, dir];
}

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  Widget _card(String title, String? subtitle, List<Widget> children) => Padding(
    padding: const EdgeInsets.only(bottom: S.x4),
    child: Panel(
      padding: const EdgeInsets.all(S.x5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: T.heading),
          if (subtitle != null) ...[const SizedBox(height: S.x1), Text(subtitle, style: T.small)],
          const SizedBox(height: S.x4),
          ...children,
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([lib, engine, discStyle]),
    builder: (context, _) {
      final folders = lib.folders;
      return ListView(
        key: const PageStorageKey('settings'),
        padding: EdgeInsets.zero,
        children: [
          const PageHeader('Settings'),
          Align(
            alignment: Alignment.topLeft,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 880),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _card(
                    'Library folders',
                    Platform.isAndroid
                        ? 'Gleo reads these folders, and looks again each time you come back to it (or pull down on a list). Your files are never changed.'
                        : 'The player reads these folders and watches them for changes. Your files are never changed.',
                    [
                      if (folders.isEmpty) Text('No folders yet.', style: T.small.copyWith(color: C.faint)),
                      for (final f in folders)
                        Container(
                          margin: const EdgeInsets.only(bottom: S.x2),
                          padding: const EdgeInsets.fromLTRB(S.x3, S.x1, S.x1, S.x1),
                          decoration: BoxDecoration(
                            color: C.raised2,
                            borderRadius: BorderRadius.circular(R.small + 2),
                            border: Border.all(color: C.border),
                          ),
                          child: Row(
                            children: [
                              Icon(LucideIcons.folder, size: 16, color: C.dim),
                              const SizedBox(width: S.x3),
                              Expanded(
                                child: Text(f, style: T.label, overflow: TextOverflow.ellipsis),
                              ),
                              IconBtn(
                                LucideIcons.x,
                                size: 14,
                                box: 32,
                                tooltip: 'Remove folder',
                                onTap: () async {
                                  if (await confirm(
                                    context,
                                    'Remove this folder?',
                                    '$f\n\nIts songs leave the library (the files stay on disk). Their play counts are kept for 6 months in case you add it back.',
                                    action: 'Remove',
                                  )) {
                                    lib.folders = [...folders]..remove(f);
                                  }
                                },
                              ),
                            ],
                          ),
                        ),
                      const SizedBox(height: S.x2),
                      Wrap(
                        spacing: S.x3,
                        runSpacing: S.x2,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          PillButton('Add folder', icon: LucideIcons.folderPlus, primary: true, onTap: addMusicFolder),
                          PillButton('Rescan now', icon: LucideIcons.refreshCw, onTap: folders.isEmpty ? null : lib.rescan),
                          Padding(
                            padding: const EdgeInsets.only(left: S.x1),
                            child: ValueListenableBuilder(
                              valueListenable: lib.scan,
                              builder: (_, s, _) => Text(
                                s != null
                                    ? (s.$2 == 0 ? 'Checking for new music…' : 'Reading ${fmtInt(s.$1)} of ${fmtInt(s.$2)} songs…')
                                    : '${plural(lib.tracks.length, 'song')} · ${plural(lib.albums.length, 'album')}${lib.lastScan == null ? '' : ' · up to date'}',
                                style: T.caption,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (lib.corruptBackup != null) ...[
                        const SizedBox(height: S.x3),
                        Text(
                          'The library file could not be read, so a fresh library was started. The old file is kept at ${lib.corruptBackup}',
                          style: T.caption.copyWith(color: C.accent),
                        ),
                      ],
                      if (lib.skippedFolders.isNotEmpty) ...[
                        const SizedBox(height: S.x3),
                        Text(
                          'Could not read ${plural(lib.skippedFolders.length, 'folder')} (songs already in them are kept):\n${lib.skippedFolders.join('\n')}',
                          style: T.caption,
                        ),
                      ],
                    ],
                  ),
                  _card(
                    'Sound',
                    Platform.isAndroid
                        ? 'The equalizer, headphone correction, crossfeed and ReplayGain.'
                        : 'Output device, exclusive mode, the equalizer, headphone correction and ReplayGain.',
                    [PillButton('Open Sound settings', icon: LucideIcons.slidersVertical, onTap: () => nav.go('sound'))],
                  ),
                  _card('Disc & covers', 'Appearance', [
                    Row(
                      children: [
                        SizedBox(width: 140, child: Text('Spinning disc', style: T.label)),
                        Expanded(
                          child: Wrap(
                            spacing: S.x2,
                            runSpacing: S.x2,
                            children: [
                              for (final (s, label) in const [(DiscStyle.cd, 'CD'), (DiscStyle.vinyl, 'Vinyl'), (DiscStyle.off, 'Off')])
                                PillButton(label, dense: true, primary: discStyle.value == s, onTap: () => discStyle.value = s),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: S.x2),
                    Text(
                      'Shown beside the cover in Now Playing, Disc mode (D) and the mini player. It turns only while music plays.',
                      style: T.caption,
                    ),
                    const SizedBox(height: S.x4),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(width: 140, child: Text('Cover art from', style: T.label)),
                        Expanded(
                          child: Wrap(
                            spacing: S.x2,
                            runSpacing: S.x2,
                            children: [
                              for (final s in artSources.where((s) => s.weight > 0))
                                PillButton(
                                  s.name,
                                  dense: true,
                                  icon: sourcesInUse(lib.artSourcesOn).contains(s) ? LucideIcons.check : null,
                                  primary: sourcesInUse(lib.artSourcesOn).contains(s),
                                  onTap: () => lib.artSourcesOn = lib.artSourcesOn.contains(s.id)
                                      ? ({...lib.artSourcesOn}..remove(s.id))
                                      : {...lib.artSourcesOn, s.id},
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: S.x3),
                    Text(
                      'Albums without a cover, or with a small or blurry one, get artwork from the collections that are on: '
                      'public-domain paintings (Masterpieces), styles Gleo paints itself (Painted), illustrations made for Gleo (Illustrated) and code-drawn shapes (Abstract). '
                      '${isTouch ? 'Long-press' : 'Right-click'} an album and choose Change cover to pick another or keep the original. Your music files are never changed.',
                      style: T.small,
                    ),
                  ]),
                  _card('Theme', null, [const ThemeSettings()]),
                  if (!Platform.isAndroid) _card('Window', null, [const WindowSettings()]),
                  if (!Platform.isAndroid)
                    _card('Keyboard', null, [
                      for (final (k, v) in const [
                        ('Space', 'Play / pause'),
                        ('Ctrl + ← / →', 'Previous / next song'),
                        ('← / →', 'Back / forward 5 seconds'),
                        ('Ctrl + K', 'Search (Shift + Enter plays next)'),
                        ('Ctrl + L', 'Lyrics'),
                        ('↑ / ↓, Enter', 'Move through songs, play'),
                        ('Ctrl + A', 'Select all songs'),
                        ('Menu key', 'Right-click menu (or Shift + F10)'),
                        ('Esc', 'Back, close Now Playing, clear selection'),
                        ('D', 'Disc mode (F11: full screen)'),
                      ])
                        Padding(
                          padding: const EdgeInsets.only(bottom: S.x2),
                          child: Row(
                            children: [
                              SizedBox(
                                width: 140,
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: S.x2, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: C.raised2,
                                      borderRadius: BorderRadius.circular(R.small - 2),
                                      border: Border.all(color: C.borderStrong),
                                    ),
                                    child: Text(
                                      k,
                                      style: T.caption.copyWith(color: C.text, fontWeight: FontWeight.w600),
                                    ),
                                  ),
                                ),
                              ),
                              Text(v, style: T.small),
                            ],
                          ),
                        ),
                    ]),
                  _card('Data and updates', null, [const DataAndUpdates()]),
                  _card('About', null, [
                    Row(
                      children: [
                        const Wordmark(height: 40),
                        const SizedBox(width: S.x4),
                        Expanded(
                          child: Text(
                            'Gleo · © 2026 Utkarsh Tripathi · UT Community Licence 2.0\n\n'
                            'Version $shortVersion · Gleo audio engine (mpv + FFmpeg, built in public at github.com/capsuleutkarsh-design/lumen-audio-engine). '
                            'Design inspired by Wora (MIT). '
                            'Font: Inter (SIL Open Font License). Icons: Lucide (ISC). No AI. Suggestions come only from what you play here, '
                            'and nothing goes to the internet unless you turn on the update check.',
                            style: T.small,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: S.x4),
                    PillButton('Credits', icon: LucideIcons.award, onTap: () => showCredits(context)),
                  ]),
                ],
              ),
            ),
          ),
        ],
      );
    },
  );
}
