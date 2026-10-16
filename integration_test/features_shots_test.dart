// 0.4 features (track B3) on the real Windows app: screenshots of the Playback card, ratings (Songs
// column, Now Playing, Rate menu), Back up / Restore and Online settings, the restore summary, the lyrics
// empty state, a CUE album and the resume toast. Audio goes to mpv's null output; never the real library.
//   flutter test integration_test/features_shots_test.dart -d windows --dart-define=MP_DATA=<scratch>\appdata
//     --dart-define=MP_MUSIC=<folder with testlib> --dart-define=MP_CUE=<folder with a CUE album> --dart-define=MP_SHOTS=<out>
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:gleo/library/backup.dart';
import 'package:gleo/main.dart';
import 'package:gleo/platform/window.dart';
import 'package:gleo/ui/app.dart';
import 'package:gleo/ui/pages/settings_extras.dart';
import 'package:gleo/ui/tracks.dart';
import 'package:gleo/ui/widgets.dart';
import 'package:path/path.dart' as p;
import 'package:window_manager/window_manager.dart';

const music = String.fromEnvironment('MP_MUSIC');
const cue = String.fromEnvironment('MP_CUE');
final shots = p.join(const String.fromEnvironment('MP_SHOTS'), 'b3');
final log = StringBuffer();

void say(String s) {
  log.writeln(s);
  File(p.join(shots, 'b3_log.txt')).writeAsStringSync(log.toString());
}

Future<void> waitFor(bool Function() ok, {Duration timeout = const Duration(seconds: 60)}) async {
  final sw = Stopwatch()..start();
  while (!ok()) {
    if (sw.elapsed > timeout) throw TimeoutException('waitFor');
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('B3 features', (tester) async {
    final data = Directory(const String.fromEnvironment('MP_DATA'));
    if (data.existsSync()) data.deleteSync(recursive: true);
    if (Directory(shots).existsSync()) Directory(shots).deleteSync(recursive: true);
    Directory(shots).createSync(recursive: true);
    final errors = <String>[];
    final old = FlutterError.onError;
    FlutterError.onError = (d) {
      errors.add(d.exceptionAsString().split('\n').first);
      old?.call(d);
    };
    await boot(silent: true);
    await windowManager.ensureInitialized();

    Future<void> settle([int ms = 700]) async {
      for (var i = 0; i < ms ~/ 50; i++) {
        await tester.pump(const Duration(milliseconds: 50));
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    }

    var seen = 0;
    Future<void> shot(String name) async {
      await settle();
      await captureShot(name, shots);
      final e = errors.skip(seen).toSet();
      seen = errors.length;
      say('$name: ${e.isEmpty ? 'ok' : 'ERRORS ${e.join(' | ')}'}');
    }

    await windowManager.setSize(const Size(1440, 900));
    await setupWindow(lib, () async {});
    await tester.pumpWidget(const App());
    lib.folders = [p.join(music, 'testlib'), cue];
    await waitFor(() => lib.scan.value == null && lib.albums.any((a) => a.title == 'Moonrise Live'), timeout: const Duration(minutes: 3));
    final moon = lib.albums.firstWhere((a) => a.title == 'Moonrise Live');
    say('CUE album: ${[for (final t in moon.tracks) '${t.trackNo}. ${t.title} — ${t.artist} (${t.startMs} ms, ${t.durationMs} ms, ${t.badge})'].join('; ')}');
    final songs = lib.tracks.where((t) => t.startMs == null).toList();
    for (final (i, t) in songs.take(12).indexed) {
      lib.setRating([t.id], 5 - i % 5);
    }

    // Sound → Playback, crossfade on so its length shows.
    engine.setPlayback(crossfade: 6);
    nav.go('sound');
    await settle();
    await tester.ensureVisible(find.text('Playback'));
    await shot('b3_sound_playback');
    engine.setPlayback(crossfade: 0);

    // Songs: the Rating column (wide window).
    nav.go('songs');
    await shot('b3_songs_ratings');

    // The track menu with Rate ▸, then its stars.
    final row = find.byType(TrackRow).first;
    final ctx = tester.element(row);
    final at = tester.getCenter(row);
    unawaited(showTrackMenu(ctx, at, [songs.first]));
    await shot('b3_track_menu');
    await tester.tap(find.text('Rate ▸'));
    await settle(400);
    await shot('b3_rate_menu');
    Navigator.of(tester.element(find.text('No rating'))).pop();
    await settle(300);

    // The CUE album, then Now Playing with stars by the heart.
    nav.push('album', moon.key);
    await shot('b3_cue_album');
    await engine.playTracks(moon.tracks, 1);
    await waitFor(() => engine.playing && engine.position.value > const Duration(milliseconds: 500));
    say('playing CUE track 2: position ${engine.position.value}, duration ${engine.duration}');
    lib.setRating([moon.tracks[1].id], 4);
    nav.setNowPlaying(true);
    await shot('b3_now_playing_stars');
    nav.setNowPlaying(false);

    // The lyrics empty state with Find lyrics online…
    nav.toggleLyrics();
    await shot('b3_lyrics_empty');
    nav.toggleLyrics();
    await engine.pause();

    // Settings: Back up / Restore and Online.
    nav.go('settings');
    await settle();
    await tester.ensureVisible(find.text('Online'));
    await shot('b3_settings_backup_online');

    // The restore summary for a backup of this very library.
    final text = makeBackup(lib, app: 'test', platform: 'windows');
    File(p.join(shots, 'sample.gleobackup')).writeAsStringSync(text);
    unawaited(restoreFrom(tester.element(find.text('Online')), text, 'sample.gleobackup'));
    await shot('b3_restore_confirm');
    await tester.tap(find.text('Cancel'));
    await settle(300);

    // The resume toast (the engine's real stream; the mpv test plays the real thing).
    toast(null, 'Resumed at 23:10', action: 'Start over', onAction: () {});
    await shot('b3_resume_toast');

    say('errors: ${errors.isEmpty ? 'none' : errors.toSet().join(' | ')}');
    expect(errors, isEmpty);
  });
}
