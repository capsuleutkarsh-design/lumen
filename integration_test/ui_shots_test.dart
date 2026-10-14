// Screenshots of every UI state, plus frame timing while scrolling 20k songs.
// Run (never touches the real library; audio goes to mpv's null output):
//   flutter test integration_test/ui_shots_test.dart -d windows
//     --dart-define=MP_DATA=<scratch>\appdata --dart-define=MP_ROOT=<repo>
//     --dart-define=MP_MUSIC=<folder holding testlib and real_music> --dart-define=MP_SHOTS=<out folder>
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:music_player/library/models.dart';
import 'package:music_player/main.dart';
import 'package:music_player/ui/app.dart';
import 'package:music_player/ui/theme.dart';
import 'package:music_player/ui/tracks.dart';
import 'package:path/path.dart' as p;
import 'package:window_manager/window_manager.dart';

const root = String.fromEnvironment('MP_ROOT');
const _music = String.fromEnvironment('MP_MUSIC');
const _shots = String.fromEnvironment('MP_SHOTS');
final music = _music.isEmpty ? p.join(root, '_scratch') : _music;
final shots = _shots.isEmpty ? p.join(root, '_scratch', 'shots') : _shots;
final testlib = p.join(music, 'testlib');
final realMusic = p.join(music, 'real_music');
final log = StringBuffer();

void say(String s) {
  log.writeln(s);
  File(p.join(shots, 'ui_shots_log.txt')).writeAsStringSync(log.toString());
}

Future<void> waitFor(bool Function() ok, {Duration timeout = const Duration(seconds: 60)}) async {
  final sw = Stopwatch()..start();
  while (!ok()) {
    if (sw.elapsed > timeout) throw TimeoutException('waitFor');
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

Track byFile(String rel) => lib.tracks.firstWhere((t) => t.path.toLowerCase().endsWith(rel.toLowerCase()));

/// Rows that point at files that do not exist: big libraries and songs without cover art.
void fakeTracks(int n, {required String prefix, required int startId, String? lyrics, int perAlbum = 12, int albumOffset = 0}) {
  final db = lib.db;
  db.execute('BEGIN');
  final ins = db.prepare(
    '''INSERT OR REPLACE INTO tracks(id,path,root,folder,mtime,size,title,artist,album_artist_tag,compilation,album,album_artist,album_key,
      track_no,disc_no,year,genre,duration_ms,codec,sample_rate,bit_depth,channels,bitrate,cover,lyrics,added_at) VALUES(?,?,?,?,?,?,?,?,?,0,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)''',
  );
  const names = ['Velvet Static', 'Paper Moons', 'Quiet Engines', 'Low Tide', 'Glass Harbour', 'Night Bloom', 'Ember Lane', 'Saltwater'];
  const artists = ['Juniper Vale', 'The Hollow Pines', 'Orla Finch', 'Kestrel', 'Marlow & Wren'];
  for (var i = 0; i < n; i++) {
    final a = i ~/ perAlbum + albumOffset;
    final artist = '${artists[a % artists.length]}${a >= 40 ? ' ${a ~/ 40}' : ''}';
    final album = '${names[a % names.length]}${a >= names.length ? ' ${a ~/ names.length + 1}' : ''}';
    final dir = p.join(music, 'missing', prefix, artist, album);
    ins.execute([
      startId + i,
      p.join(dir, '${i % perAlbum + 1} Song $i.flac'),
      p.join(music, 'missing'),
      dir,
      0,
      0,
      'Song ${i + 1} of $album',
      artist,
      artist,
      album,
      artist,
      '${artist.toLowerCase()}\u0000${album.toLowerCase()}',
      i % perAlbum + 1,
      1,
      1990 + a % 30,
      'Rock',
      200000 + i * 37 % 90000,
      'FLAC',
      i.isEven ? 96000 : 44100,
      i.isEven ? 24 : 16,
      2,
      900,
      null,
      lyrics,
      DateTime.now().millisecondsSinceEpoch - i,
    ]);
  }
  ins.close();
  db.execute('COMMIT');
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('ui screenshots', (tester) async {
    expect(root, isNotEmpty, reason: 'pass --dart-define=MP_ROOT=<repo>');
    final data = Directory(const String.fromEnvironment('MP_DATA'));
    if (data.existsSync()) data.deleteSync(recursive: true);
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

    Future<void> size(double w, double h) async {
      await windowManager.setSize(Size(w, h));
      await settle(500);
    }

    /// Renders the shell at any size / text scale without resizing the real window.
    final offKey = GlobalKey();
    Future<void> offscreen(String name, Size s, {double text = 1}) async {
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: buildTheme(),
          home: Builder(
            builder: (c) => OverflowBox(
              alignment: Alignment.topLeft,
              minWidth: s.width,
              maxWidth: s.width,
              minHeight: s.height,
              maxHeight: s.height,
              child: MediaQuery(
                data: MediaQuery.of(c).copyWith(size: s, textScaler: TextScaler.linear(text)),
                child: RepaintBoundary(key: offKey, child: const Shell()),
              ),
            ),
          ),
        ),
      );
      await settle(900);
      final img = await (offKey.currentContext!.findRenderObject() as RenderRepaintBoundary).toImage();
      final png = await img.toByteData(format: ui.ImageByteFormat.png);
      File(p.join(shots, '$name.png')).writeAsBytesSync(png!.buffer.asUint8List());
      final e = errors.skip(seen).toSet();
      seen = errors.length;
      say('$name: ${e.isEmpty ? 'ok' : 'ERRORS ${e.join(' | ')}'}');
    }

    await size(1440, 900);
    await tester.pumpWidget(const App());

    // 1. First run and a big first scan.
    await shot('01_firstrun_home');
    lib.setSetting('folders', jsonEncode([testlib]));
    lib.scan.value = (1200, 20000);
    lib.notifyListeners();
    await shot('02_scanning_empty');
    lib.scan.value = null;
    lib.folders = [testlib, realMusic];
    await waitFor(() => lib.scan.value == null && lib.tracks.length >= 45, timeout: const Duration(minutes: 3));

    // 2. Some history, favourites, a playlist, and albums with no cover art.
    final now = DateTime.now();
    void plays(String f, List<int> daysAgo) {
      for (final d in daysAgo) {
        lib.recordPlay(byFile(f).id, skipped: false, at: now.subtract(Duration(days: d, hours: 1)));
      }
    }

    plays(r'Northern Lights (2017)\03 Magnetic.flac', [0, 1, 2, 4]);
    plays(r'CD1\02 Kelp Forest.flac', [2, 5, 6]);
    plays(r'Summer Mix\03 Lemonade.mp3', [40, 45, 50, 60]);
    plays(r'Hi-Res Sketches\04 Chalk Lines.flac', [8]);
    lib.toggleFavourite(byFile(r'Northern Lights (2017)\03 Magnetic.flac').id);
    lib.toggleFavourite(byFile(r'CD2\03 Currents.flac').id);
    fakeTracks(60, prefix: 'noart', startId: 500000, perAlbum: 10);
    fakeTracks(
      1,
      prefix: 'plain',
      startId: 600000,
      albumOffset: 7,
      lyrics: 'This song has plain lyrics\nwith no time stamps\n\nSo every line is shown\nat full strength, calm and readable',
    );
    lib.load();
    final pl = lib.createPlaylist('Late night drive with a rather long playlist name', [
      for (final f in [r'CD1\03 Pressure.flac', r'Hi-Res Sketches\03 Interlude.flac', r'Summer Mix\07 Late August.flac']) byFile(f).id,
      500003,
      500012,
    ]);
    for (final id in [500001, 500011, 500021]) {
      lib.recordPlay(id, skipped: false, at: now.subtract(const Duration(hours: 3)));
    }
    lib.load();

    final etude = byFile(r'Hi-Res Sketches\01 Etude in Glass.flac');
    final album = lib.albumByKey[etude.albumKey]!;
    await engine.playTracks(album.tracks);
    await engine.seek(const Duration(milliseconds: 6400));
    await waitFor(() => engine.position.value > const Duration(seconds: 6));
    await engine.player.pause();
    await engine.setVolume(60);

    // 3. Every page.
    nav.go('home');
    await shot('03_home');
    nav.go('albums');
    await shot('04_albums');
    nav.push('album', lib.albums.firstWhere((a) => a.title == 'Deep Water').key);
    await shot('05_album');
    nav.go('albums');
    nav.push('album', lib.albums.firstWhere((a) => a.title == 'Velvet Static').key);
    await shot('06_album_noart');
    nav.go('artists');
    await shot('07_artists');
    nav.push('artist', 'Aurora Fields');
    await shot('08_artist');
    nav.go('songs');
    await shot('09_songs');
    nav.go('folders');
    await shot('10_folders');
    nav.go('playlists');
    await shot('11_playlists');
    nav.push('playlist', pl);
    await shot('12_playlist');
    nav.go('favourites');
    await shot('13_favourites');
    nav.go('settings');
    await shot('14_settings');
    nav.go('home');
    nav.toggleLyrics();
    await shot('15_lyrics_synced');
    nav.toggleLyrics();
    await engine.playTracks([lib.byId[600000]!]);
    await settle(300);
    nav.toggleLyrics();
    await shot('16_lyrics_plain');
    nav.toggleLyrics();
    await engine.playTracks(album.tracks);
    await engine.player.pause();
    nav.setSearch(true);
    await settle(300);
    await tester.enterText(find.byType(TextField), 'li');
    await shot('17_search');
    nav.setSearch(false);
    await settle(300);

    // 3b. Now Playing (with synced lyrics beside it), and a song without art.
    nav.go('home');
    nav.setNowPlaying(true);
    await shot('18_nowplaying');
    nav.setNowPlaying(false);
    await engine.playTracks(lib.albums.firstWhere((a) => a.title == 'Velvet Static').tracks);
    await settle(300);
    nav.setNowPlaying(true);
    await shot('19_nowplaying_noart');
    nav.setNowPlaying(false);
    await engine.playTracks(album.tracks);
    await engine.player.pause();

    // 3c. Multi-select with real clicks (click, Ctrl+click, Shift+click) and the selection bar.
    nav.go('songs');
    await settle();
    Future<void> click(Finder f, {LogicalKeyboardKey? hold}) async {
      if (hold != null) await tester.sendKeyDownEvent(hold);
      await tester.tap(f, warnIfMissed: false);
      if (hold != null) await tester.sendKeyUpEvent(hold);
      await settle(150);
    }

    final rows = find.byType(TrackRow);
    await click(rows.at(1));
    await click(rows.at(3), hold: LogicalKeyboardKey.controlLeft);
    await click(rows.at(6), hold: LogicalKeyboardKey.shiftLeft);
    say('selected after click, ctrl+click, shift+click: ${selection.length}');
    await shot('20_multiselect');
    // Right-click on a selected row: the menu acts on all of them.
    await tester.tap(rows.at(4), buttons: kSecondaryButton);
    await shot('21_menu_selection');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await settle(200);
    selection.clear();

    // 3d. Right-click menus on an album card, an artist card, a playlist card and an album header.
    nav.go('albums');
    await settle();
    await tester.tap(find.text('Deep Water').first, buttons: kSecondaryButton);
    await shot('22_menu_album_card');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    nav.go('artists');
    await settle();
    await tester.tap(find.text('Aurora Fields').first, buttons: kSecondaryButton);
    await shot('23_menu_artist_card');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    nav.go('playlists');
    await settle();
    await tester.tap(find.textContaining('Late night').first, buttons: kSecondaryButton);
    await shot('24_menu_playlist_card');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    nav.push('playlist', pl);
    await settle();
    await tester.tap(find.byTooltip('More').first);
    await shot('25_menu_playlist_header');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await settle(200);

    // 3e. A toast with Undo / Show queue, above the player bar.
    nav.go('albums');
    nav.push('album', lib.albums.firstWhere((a) => a.title == 'Quiet Engines').key);
    await settle();
    await queueTracks(
      tester.element(find.byType(Scaffold).first),
      lib.albums.firstWhere((a) => a.title == 'Quiet Engines').tracks,
      next: false,
    );
    await shot('26_toast');
    await settle(200);

    // 4. The smallest window with the queue open.
    await size(960, 640);
    nav.go('home');
    nav.toggleQueue();
    await shot('40_small_home_queue');
    nav.push('album', album.key);
    await shot('41_small_album_queue');
    nav.go('playlists');
    nav.push('playlist', pl);
    await shot('42_small_playlist_queue');
    nav.go('songs');
    await shot('43_small_songs_queue');
    nav.toggleQueue();
    nav.setNowPlaying(true);
    await shot('43b_small_nowplaying');
    nav.setNowPlaying(false);
    await size(1440, 900);

    // 5. A large window and 130 % text.
    nav.go('albums');
    await offscreen('44_large_albums', const Size(2560, 1440));
    nav.go('home');
    await offscreen('45_large_home', const Size(2560, 1440));
    for (final pg in ['home', 'songs', 'albums']) {
      nav.go(pg);
      await offscreen('46_text130_$pg', const Size(1424, 860), text: 1.3);
    }
    nav.push('album', album.key);
    await offscreen('46_text130_album', const Size(1424, 860), text: 1.3);
    nav.go('playlists');
    await offscreen('46_text130_playlists', const Size(1424, 860), text: 1.3);
    nav.go('home');
    await offscreen('47_text150_home', const Size(1424, 860), text: 1.5);
    nav.go('songs');
    await offscreen('47_text150_songs', const Size(1424, 860), text: 1.5);
    nav.push('album', album.key);
    await offscreen('47_text150_album', const Size(1424, 860), text: 1.5);
    nav.go('home');
    nav.toggleQueue();
    await offscreen('47_text150_small_queue', const Size(944, 600), text: 1.5);
    nav.toggleQueue();
    await tester.pumpWidget(const App());
    await settle();

    // 6. Frame timing while scrolling 20k songs.
    fakeTracks(20000, prefix: 'big', startId: 1000000, albumOffset: 100);
    lib.load();
    nav.go('songs');
    await settle(800);
    final sp = tester.state<ScrollableState>(find.byType(Scrollable).first).position;
    final timings = <FrameTiming>[];
    void onT(List<FrameTiming> t) => timings.addAll(t);
    SchedulerBinding.instance.addTimingsCallback(onT);
    for (var i = 0; i < 200; i++) {
      sp.jumpTo((sp.pixels + 300).clamp(0, sp.maxScrollExtent));
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 16));
    }
    await settle(500);
    SchedulerBinding.instance.removeTimingsCallback(onT);
    if (timings.isNotEmpty) {
      double pct(List<double> xs, double q) => xs[(xs.length * q).floor().clamp(0, xs.length - 1)];
      final b = timings.map((t) => t.buildDuration.inMicroseconds / 1000).toList()..sort();
      final r = timings.map((t) => t.rasterDuration.inMicroseconds / 1000).toList()..sort();
      say(
        'scroll ${lib.tracks.length} songs: ${timings.length} frames; build p50 ${pct(b, .5)} p90 ${pct(b, .9)} max ${b.last} ms; '
        'raster p50 ${pct(r, .5)} p90 ${pct(r, .9)} max ${r.last} ms',
      );
    }
    await shot('50_songs_20k');
    await engine.shutdown();
    FlutterError.onError = old;
    expect(errors, isEmpty, reason: errors.toSet().join('\n'));
  });
}
