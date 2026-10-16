import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../art/art_sources.dart' show sourcesOn;
import '../../audio/sound.dart' show SoundSettings;
import '../../library/backup.dart';
import '../../platform/android.dart' show saveText;
import '../../platform/tray.dart';
import '../../platform/update.dart' show shortVersion;
import '../app.dart';
import '../art_accent.dart';
import '../disc.dart';
import '../lyrics_view.dart' show lyricsOnline;
import '../theme.dart';
import '../widgets.dart';
import 'browse.dart';

/// Settings → Theme: dark, light or follow Windows, and the accent from album art.
class ThemeSettings extends StatelessWidget {
  const ThemeSettings({super.key});
  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: appearance,
    builder: (context, mode, _) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: S.x4,
          runSpacing: S.x2,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(width: 124, child: Text('Colours', style: T.label)),
            Segmented(
              value: mode,
              options: [('dark', 'Dark'), ('light', 'Light'), ('system', Platform.isAndroid ? 'Follow the phone' : 'Follow Windows')],
              onChanged: setAppearance,
            ),
          ],
        ),
        const SizedBox(height: S.x4),
        _Toggle(
          'Accent from album art',
          'Now Playing glows, and the seek bar fills, in a colour from the cover. Grey, very dark or very light covers keep gold.',
          accentFromArt,
          (v) {
            lib.setSetting('artAccent', v ? '1' : '0');
            refreshArtAccent();
          },
        ),
      ],
    ),
  );
}

/// Settings → Online: lyrics from LRCLIB (off by default; the update check is under Data and updates).
class OnlineSettings extends StatelessWidget {
  const OnlineSettings({super.key});
  @override
  Widget build(BuildContext context) => _Toggle(
    'Download lyrics from LRCLIB',
    'Off unless you turn it on. For a song with no lyrics, Gleo then asks lrclib.net (free, no account) by artist, title, '
        'album and length, and keeps what it finds in its own data folder. Nothing else is sent, and your music files are never changed.',
    lyricsOnline,
    (v) => lib.setSetting('lyricsOnline', v ? '1' : '0'),
  );
}

/// Settings → Window: close to the tray.
class WindowSettings extends StatelessWidget {
  const WindowSettings({super.key});
  @override
  Widget build(BuildContext context) => _Toggle(
    'Close to tray',
    'Closing the window keeps Gleo playing in the notification area. Click its icon to come back; right-click it to quit.',
    closeToTray(lib),
    (v) => lib.setSetting('closeToTray', v ? '1' : '0'),
  );
}

class _Toggle extends StatefulWidget {
  const _Toggle(this.title, this.body, this.value, this.onChanged);
  final String title, body;
  final bool value;
  final ValueChanged<bool> onChanged;
  @override
  State<_Toggle> createState() => _ToggleState();
}

class _ToggleState extends State<_Toggle> {
  late bool _v = widget.value;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.title, style: T.label),
            const SizedBox(height: 2),
            Text(widget.body, style: T.small),
          ],
        ),
      ),
      const SizedBox(width: S.x4),
      Switch(
        value: _v,
        onChanged: (v) {
          setState(() => _v = v);
          widget.onChanged(v);
        },
      ),
    ],
  );
}

const _backup = XTypeGroup(label: 'Gleo backup', extensions: ['gleobackup']);

/// Settings → Data and updates: Back up… and Restore… (one .gleobackup file).
class BackupButtons extends StatelessWidget {
  const BackupButtons({super.key});
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text('Back up and restore', style: T.label),
      const SizedBox(height: 2),
      Text(
        'One file with your playlists, smart playlists, favourites, ratings, play history, cover choices and settings '
        '(EQ presets too). Restore it here, or on another computer or phone: songs are found by their tags when the '
        'folders differ. Music files are not in it.',
        style: T.small,
      ),
      const SizedBox(height: S.x3),
      Wrap(
        spacing: S.x3,
        runSpacing: S.x2,
        children: [
          PillButton('Back up…', icon: LucideIcons.download, onTap: () => backUp(context)),
          PillButton('Restore…', icon: LucideIcons.upload, onTap: () => restore(context)),
        ],
      ),
    ],
  );
}

Future<void> backUp(BuildContext context) async {
  final day = DateTime.now().toIso8601String().substring(0, 10);
  final text = makeBackup(lib, app: shortVersion, platform: Platform.operatingSystem);
  final to = await saveText('Gleo backup $day.gleobackup', text, _backup);
  if (to != null && context.mounted) toast(context, 'Backed up to $to');
}

/// Reads a backup, says what it found and what it will replace, and restores it on OK.
Future<void> restore(BuildContext context) async {
  // Android's file screen knows no .gleobackup type: any file can be picked there.
  final f = await openFile(acceptedTypeGroups: [Platform.isAndroid ? const XTypeGroup(label: 'Gleo backup') : _backup]);
  if (f == null) return;
  final RestorePlan plan;
  try {
    plan = planRestore(lib, await f.readAsString());
  } catch (e) {
    if (context.mounted) toast(context, '${f.name} is not a Gleo backup');
    return;
  }
  if (!context.mounted) return;
  final missing = plan.total - plan.matched;
  final ok = await confirm(
    context,
    'Restore this backup?',
    'Found ${fmtInt(plan.matched)} of ${plural(plan.total, 'song')} from the backup in this library'
        '${missing > 0 ? ". The other ${fmtInt(missing)} aren't here, so their plays, ratings and places in playlists are left out" : ''}.\n\n'
        'This replaces your playlists (${plan.count('playlists')} in the backup), smart playlists (${plan.count('smart')}), '
        'favourites (${plan.count('favourites')}), ratings (${plan.count('ratings')}), play history (${plural(plan.count('plays'), 'play')}), '
        'hidden songs, cover choices and settings. Your library folders and music files stay as they are.',
    action: 'Replace',
  );
  if (!ok) return;
  applyRestore(lib, plan);
  // Settings that were read once at start.
  loadAppearance();
  refreshArtAccent();
  discStyle.value = DiscStyle.values.asNameMap()[lib.setting('disc')] ?? DiscStyle.cd;
  lib.artSourcesOn = sourcesOn(lib.setting('artSources'));
  sound.s = SoundSettings.parse(lib.setting('sound'));
  sound.change((_) {});
  engine.setPlayback(
    crossfade: int.tryParse(lib.setting('crossfade') ?? '') ?? 0,
    trimSilence: lib.setting('trimSilence') == '1',
    resumeLong: lib.setting('resumeLong') == '1',
  );
  if (context.mounted) toast(context, 'Backup restored');
}
