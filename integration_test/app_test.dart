// End-to-end check in the real app with real libmpv:
//  1. seeking is exact (±0.2 s) on every format, including 24/192 FLAC without a seek table;
//  2. track changes are gapless (no position gap, audio output never reopened);
//  3. screenshots of every page.
// Run (never touches the real library; sound is at volume 0):
//   flutter test integration_test -d windows --dart-define=MP_DATA=<root>\_scratch\appdata --dart-define=MP_ROOT=<root>
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media_kit/media_kit.dart' hide Track;
import 'package:music_player/library/models.dart';
import 'package:music_player/main.dart';
import 'package:music_player/ui/app.dart';
import 'package:path/path.dart' as p;
import 'package:window_manager/window_manager.dart';

const root = String.fromEnvironment('MP_ROOT');
final testlib = p.join(root, '_scratch', 'testlib');
final realMusic = p.join(root, '_scratch', 'real_music');
final shots = p.join(root, '_scratch', 'shots');

Future<void> waitFor(bool Function() ok, {Duration timeout = const Duration(seconds: 20), String what = ''}) async {
  final sw = Stopwatch()..start();
  while (!ok()) {
    if (sw.elapsed > timeout) throw TimeoutException('waiting for $what');
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

Track byFile(String rel) =>
    lib.tracks.firstWhere((t) => t.path.toLowerCase().endsWith(rel.toLowerCase()), orElse: () => throw StateError('no $rel'));

NativePlayer get mpv => engine.player.platform as NativePlayer;
Future<double> timePos() async => double.tryParse(await mpv.getProperty('time-pos')) ?? -1;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  // The test music is not in git: testlib is made by tool\make_testlib.ps1; real_music holds the
  // owner's copies of Wikimedia Commons recordings. Without them the test is skipped, not failed.
  if (!Directory(testlib).existsSync() || !Directory(realMusic).existsSync()) {
    test('end-to-end test', () {}, skip: 'needs $testlib and $realMusic');
    return;
  }
  final report = StringBuffer();

  testWidgets('library scan of both folders', (tester) async {
    expect(root, isNotEmpty, reason: 'pass --dart-define=MP_ROOT=<project folder>');
    final data = Directory(const String.fromEnvironment('MP_DATA'));
    if (data.existsSync()) data.deleteSync(recursive: true);
    await boot(logLevel: MPVLogLevel.info);
    await engine.setVolume(0); // real output device, but silent
    lib.folders = [testlib, realMusic];
    await waitFor(() => lib.scan.value == null && lib.tracks.length >= 45, timeout: const Duration(minutes: 3), what: 'scan');
    expect(lib.tracks.length, greaterThanOrEqualTo(45));
    // Album grouping in the real scan.
    final deep = lib.albums.firstWhere((a) => a.title == 'Deep Water');
    expect(deep.tracks.length, 8);
    expect(deep.discCount, 2);
    final mix = lib.albums.firstWhere((a) => a.title == 'Summer Mix');
    expect(mix.artist, variousArtists);
    expect(mix.tracks.length, 7, reason: 'the WAV without an album artist tag joins the compilation');
    expect(byFile('01 Etude in Glass.flac').cover, isNotNull, reason: 'embedded cover');
    expect(byFile(r'CD2\01 Bioluminescence.flac').cover, isNotNull, reason: 'cover.jpg in the folder');
  });

  testWidgets('exact seeking on every format', (tester) async {
    final files = [
      r'Hi-Res Sketches\01 Etude in Glass.flac', // 24/192, no seek table (the required case)
      r'Northern Lights (2017)\01 First Light.flac', // 16/44.1, no seek table
      r'Northern Lights (2017)\02 Polar Drift.flac', // 16/44.1, seek table
      r'CD1\01 Undertow.flac', // 24/96, seek table
      r'Summer Mix\01 Heatwave.mp3',
      r'Summer Mix\04 Golden Hour.m4a',
      r'Summer Mix\05 Tide Pools.wav',
      ...[
        for (final f in Directory(realMusic).listSync(recursive: true).whereType<File>())
          if (!f.path.endsWith('.txt')) p.relative(f.path, from: realMusic),
      ],
    ];
    report
      ..writeln('| File | Format | Plays | Duration (tags / mpv) | Seek to 80 %: error | Seek time | Clock 1 s later | Tags | Cover |')
      ..writeln('|---|---|---|---|---|---|---|---|---|');
    var failures = 0;
    for (final f in files) {
      final t = byFile(f);
      await engine.playTracks([t]);
      final started = await Future.any([
        waitFor(() => engine.playing && engine.position.value > const Duration(milliseconds: 300), what: 'play $f').then((_) => true),
        Future<bool>.delayed(const Duration(seconds: 15), () => false),
      ]).catchError((_) => false);
      final mpvDur = engine.duration;
      await engine.player.pause();
      final target = mpvDur.inMilliseconds * 0.8 / 1000;
      final sw = Stopwatch()..start();
      await engine.seek(Duration(milliseconds: (target * 1000).round()));
      // mpv shows the target while still seeking: wait until the seek has really finished.
      while (await mpv.getProperty('seeking') == 'yes' && sw.elapsed < const Duration(seconds: 3)) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      final seekMs = sw.elapsedMilliseconds;
      final err = await timePos() - target;
      // Then play on: the clock must continue from the target (a failed seek would jump elsewhere).
      final run = Stopwatch()..start();
      await engine.player.play();
      await Future<void>.delayed(const Duration(seconds: 1));
      final drift = await timePos() - target - run.elapsedMicroseconds / 1e6;
      final ok = started && err.abs() <= 0.2 && drift.abs() <= 0.4;
      if (!ok) failures++;
      final durOk = (t.durationMs - mpvDur.inMilliseconds).abs() < 1000 || t.durationMs == 0;
      final tags = t.artist != 'Unknown artist' ? '${t.artist} – ${t.album}' : 'title only';
      report.writeln(
        '| ${p.basename(f)} | ${t.badge} | ${started ? 'yes' : 'NO'} '
        '| ${fmt(t.durationMs)} / ${fmt(mpvDur.inMilliseconds)}${durOk ? '' : ' (differs)'} '
        '| ${err >= 0 ? '+' : ''}${err.toStringAsFixed(3)} s ${ok ? 'ok' : 'FAIL'} | $seekMs ms '
        '| ${drift >= 0 ? '+' : ''}${drift.toStringAsFixed(2)} s | $tags | ${t.cover != null ? 'yes' : 'no'} |',
      );
    }
    await engine.player.pause();
    File(p.join(root, '_scratch', 'report_seek.md')).writeAsStringSync(report.toString());
    expect(failures, 0, reason: report.toString());
  });

  testWidgets('gapless track changes', (tester) async {
    final out = StringBuffer('| From → to | Format | Timeline gap | Audio output reopened |\n|---|---|---|---|\n');
    final pairs = [
      (r'Hi-Res Sketches\01 Etude in Glass.flac', r'Hi-Res Sketches\02 Paper Birds.flac'),
      (r'CD1\04 Abyssal.flac', r'CD2\01 Bioluminescence.flac'),
      (r'No. 13 - II. Andante (Paul Pitman).flac', r'No. 13 - III. Allegro (Paul Pitman).flac'),
      (r'Op. 65 - II. Scherzo.mp3', r'Op. 65 - III. Largo.mp3'),
    ];
    var failures = 0;
    for (final (fa, fb) in pairs) {
      final a = byFile(fa), b = byFile(fb);
      await engine.playTracks([a, b]);
      await waitFor(() => engine.playing && engine.position.value > const Duration(milliseconds: 200), what: 'play $fa');
      final durA = engine.duration;
      final samples = <(int, int, Duration)>[]; // (wall µs, track id, position)
      final wall = Stopwatch()..start();
      var aoOpens = 0;
      final logSub = engine.player.stream.log.listen((l) {
        if (l.text.startsWith('AO: [')) aoOpens++;
      });
      void sample() => samples.add((wall.elapsedMicroseconds, engine.current!.id, engine.position.value));
      engine.position.addListener(sample);
      await engine.seek(durA - const Duration(milliseconds: 1500));
      await waitFor(
        () => engine.current?.id == b.id && engine.position.value > const Duration(milliseconds: 800),
        timeout: const Duration(seconds: 10),
        what: 'gapless to $fb',
      );
      engine.position.removeListener(sample);
      await logSub.cancel();
      // Last position heard on A and first on B: wall time between them should equal media time between them.
      final lastA = samples.lastWhere((s) => s.$2 == a.id && s.$3 > durA - const Duration(milliseconds: 800));
      final firstB = samples.firstWhere((s) => s.$2 == b.id && s.$3 > Duration.zero && s.$3 < const Duration(milliseconds: 600));
      final wallGap = (firstB.$1 - lastA.$1) / 1e6;
      final mediaGap = (durA - lastA.$3).inMicroseconds / 1e6 + firstB.$3.inMicroseconds / 1e6;
      final gap = wallGap - mediaGap;
      final ok = gap.abs() < 0.1 && aoOpens == 0;
      if (!ok) failures++;
      out.writeln(
        '| ${p.basename(fa)} → ${p.basename(fb)} | ${a.badge} | ${(gap * 1000).round()} ms ${ok ? 'ok' : 'FAIL'} | ${aoOpens == 0 ? 'no' : 'yes ($aoOpens)'} |',
      );
    }
    await engine.player.pause();
    File(p.join(root, '_scratch', 'report_gapless.md')).writeAsStringSync(out.toString());
    expect(failures, 0, reason: out.toString());
  });

  testWidgets('screenshots of every page', (tester) async {
    await windowManager.ensureInitialized();
    await windowManager.setSize(const Size(1440, 900));
    await windowManager.center();
    // Some listening history so Home has something to show (test data only).
    final now = DateTime.now();
    void plays(String f, List<int> daysAgo) {
      for (final d in daysAgo) {
        lib.recordPlay(byFile(f).id, skipped: false, at: now.subtract(Duration(days: d, hours: 1)));
      }
    }

    plays(r'Northern Lights (2017)\03 Magnetic.flac', [0, 1, 2, 4]);
    plays(r'Northern Lights (2017)\05 Corona.flac', [1, 3]);
    plays(r'CD1\02 Kelp Forest.flac', [2, 5, 6]);
    plays(r'Summer Mix\03 Lemonade.mp3', [40, 45, 50, 60]);
    plays(r'Summer Mix\06 Sundial.flac', [35, 38, 44]);
    plays(r'Hi-Res Sketches\04 Chalk Lines.flac', [8]);
    lib.recordPlay(byFile(r'Northern Lights (2017)\08 Last Light.flac').id, skipped: true);
    lib.toggleFavourite(byFile(r'Northern Lights (2017)\03 Magnetic.flac').id);
    lib.toggleFavourite(byFile(r'CD2\03 Currents.flac').id);
    lib.toggleFavourite(byFile(r'Summer Mix\04 Golden Hour.m4a').id);
    final pl = lib.createPlaylist('Late night', [
      for (final f in [
        r'CD1\03 Pressure.flac',
        r'Hi-Res Sketches\03 Interlude.flac',
        r'Northern Lights (2017)\07 Green Veil.flac',
        r'Summer Mix\07 Late August.flac',
      ])
        byFile(f).id,
    ]);
    lib.load();

    await tester.pumpWidget(const App());
    Future<void> settle([int ms = 900]) async {
      for (var i = 0; i < ms ~/ 50; i++) {
        await tester.pump(const Duration(milliseconds: 50));
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    }

    Future<void> shot(String name) async {
      await settle();
      await captureShot(name, shots);
    }

    // Something playing in the bar: the Etude, a few seconds in (it has an .lrc).
    final etude = byFile(r'Hi-Res Sketches\01 Etude in Glass.flac');
    final album = lib.albumByKey[etude.albumKey]!;
    await engine.playTracks(album.tracks);
    await engine.seek(const Duration(milliseconds: 6400));
    await waitFor(() => engine.position.value > const Duration(seconds: 6));
    await engine.player.pause();
    await engine.setVolume(80); // paused from here on: show a normal volume in the pictures

    await shot('01_home');
    nav.go('albums');
    await shot('02_albums');
    nav.push('album', lib.albums.firstWhere((a) => a.title == 'Deep Water').key);
    await shot('03_album_two_discs');
    nav.go('albums');
    nav.push('album', lib.albums.firstWhere((a) => a.title == 'Summer Mix').key);
    await shot('04_album_compilation');
    nav.go('artists');
    await shot('05_artists');
    nav.push('artist', 'Aurora Fields');
    await shot('06_artist');
    nav.go('songs');
    await shot('07_songs');
    nav.go('folders');
    await shot('08_folders');
    await tester.tap(find.textContaining('testlib'));
    await settle(200);
    await tester.tap(find.text('Aurora Fields'));
    await settle(200);
    await tester.tap(find.text('Northern Lights (2017)'));
    await shot('08b_folder_inside');
    nav.go('playlists');
    await shot('09_playlists');
    nav.push('playlist', pl);
    await shot('10_playlist');
    nav.go('favourites');
    await shot('11_favourites');
    nav.go('settings');
    await shot('12_settings');
    nav.go('home');
    nav.toggleLyrics();
    await shot('13_lyrics_synced');
    nav.toggleLyrics();
    nav.toggleQueue();
    await shot('14_queue');
    nav.toggleQueue();
    nav.setSearch(true);
    await settle(300);
    await tester.enterText(find.byType(TextField), 'a');
    await shot('15_search');
    nav.setSearch(false);
    await settle(300);
  });
}

String fmt(int ms) => '${ms ~/ 60000}:${(ms ~/ 1000 % 60).toString().padLeft(2, '0')}.${(ms % 1000 ~/ 100)}';
