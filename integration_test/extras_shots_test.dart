// Wave 2 "extras": screenshots of the Browse pages (Genres, Years, Composers, Duplicates,
// Statistics), smart playlists and every page in the light theme, the accent from cover art,
// small windows and 130 % text, plus the tray actions and close-to-tray on the real window.
// Run (never touches the real library; audio goes to mpv's null output):
//   flutter test integration_test/extras_shots_test.dart -d windows
//     --dart-define=MP_DATA=<scratch>\appdata --dart-define=MP_ROOT=<repo>
//     --dart-define=MP_MUSIC=<folder holding testlib and real_music> --dart-define=MP_SHOTS=<out folder>
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:gleo/main.dart';
import 'package:gleo/platform/tray.dart';
import 'package:gleo/platform/window.dart';
import 'package:gleo/ui/app.dart';
import 'package:gleo/ui/art_accent.dart';
import 'package:gleo/ui/pages/smart_playlists.dart';
import 'package:gleo/ui/player_bar.dart';
import 'package:gleo/ui/theme.dart';
import 'package:path/path.dart' as p;
import 'package:window_manager/window_manager.dart';

const root = String.fromEnvironment('MP_ROOT');
const _music = String.fromEnvironment('MP_MUSIC');
const _shots = String.fromEnvironment('MP_SHOTS');
final music = _music.isEmpty ? p.join(root, '_scratch') : _music;
final shots = p.join(_shots.isEmpty ? p.join(root, '_scratch', 'shots') : _shots, 'extras');
final log = StringBuffer();

void say(String s) {
  log.writeln(s);
  File(p.join(shots, 'extras_log.txt')).writeAsStringSync(log.toString());
}

Future<void> waitFor(bool Function() ok, {Duration timeout = const Duration(seconds: 60)}) async {
  final sw = Stopwatch()..start();
  while (!ok()) {
    if (sw.elapsed > timeout) throw TimeoutException('waitFor');
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

/// Classical rows (composer, work, movements) and a few duplicate copies; their files do not exist.
void fakeRows() {
  final db = lib.db;
  final ins = db.prepare(
    '''INSERT INTO tracks(id,path,root,folder,mtime,size,title,artist,album_artist_tag,compilation,album,album_artist,album_key,
      track_no,disc_no,year,genre,duration_ms,codec,sample_rate,bit_depth,channels,bitrate,cover,added_at,composer,work,movement,movement_no)
      VALUES(?,?,?,?,0,?,?,?,?,0,?,?,?,?,1,?,?,?,?,?,?,2,?,NULL,?,?,?,?,?)''',
  );
  var id = 700000;
  void row(
    String album,
    String artist,
    String title,
    int no,
    int year,
    String genre,
    int ms,
    String codec,
    int rate,
    int bits,
    int kbps, {
    String? composer,
    String? work,
    String? movement,
    int? mvt,
  }) {
    final dir = p.join(music, 'missing', 'extras', artist, album);
    ins.execute([
      id++,
      p.join(dir, '$no $title.${codec.toLowerCase()}'),
      p.join(music, 'missing'),
      dir,
      ms * kbps ~/ 8,
      title,
      artist,
      artist,
      album,
      artist,
      '${artist.toLowerCase()}\u0000${album.toLowerCase()}\u0000${dir.toLowerCase()}',
      no,
      year,
      genre,
      ms,
      codec,
      rate,
      bits,
      kbps,
      DateTime.now().millisecondsSinceEpoch - id * 1000,
      composer,
      work,
      movement,
      mvt,
    ]);
  }

  const beethoven = 'Ludwig van Beethoven', bach = 'Johann Sebastian Bach';
  final sym5 = ['Allegro con brio', 'Andante con moto', 'Scherzo. Allegro', 'Allegro'];
  for (final (i, m) in sym5.indexed) {
    row(
      'Symphonies 5 & 7',
      'Wiener Philharmoniker',
      'Symphony No. 5 in C minor, Op. 67: ${['I', 'II', 'III', 'IV'][i]}. $m',
      i + 1,
      1975,
      'Classical',
      420000 + i * 37000,
      'FLAC',
      96000,
      24,
      2900,
      composer: beethoven,
      work: 'Symphony No. 5 in C minor, Op. 67',
      movement: m,
      mvt: i + 1,
    );
  }
  final sym7 = ['Poco sostenuto – Vivace', 'Allegretto', 'Presto', 'Allegro con brio'];
  for (final (i, m) in sym7.indexed) {
    row(
      'Symphonies 5 & 7',
      'Wiener Philharmoniker',
      'Symphony No. 7 in A major, Op. 92: ${['I', 'II', 'III', 'IV'][i]}. $m',
      i + 5,
      1975,
      'Classical',
      380000 + i * 41000,
      'FLAC',
      96000,
      24,
      2900,
      composer: beethoven,
      work: 'Symphony No. 7 in A major, Op. 92',
      movement: m,
      mvt: i + 1,
    );
  }
  for (final (i, m) in ['Prelude', 'Allemande', 'Courante', 'Sarabande', 'Menuet I & II', 'Gigue'].indexed) {
    row(
      'Cello Suites',
      'Mischa Maisky',
      'Suite No. 1 in G major, BWV 1007: $m',
      i + 1,
      1999,
      'Classical; Baroque',
      150000 + i * 20000,
      'FLAC',
      44100,
      16,
      900,
      composer: bach,
      work: 'Cello Suite No. 1 in G major, BWV 1007',
      movement: m,
      mvt: i + 1,
    );
  }
  // Copies of real songs in other formats: the Duplicates page.
  for (final t in lib.tracks.take(3)) {
    row(
      '${t.album} (old rip)',
      t.artist,
      t.title,
      t.trackNo ?? 1,
      t.year ?? 2001,
      t.genre ?? 'Pop',
      t.durationMs + 600,
      'MP3',
      44100,
      0,
      320,
    );
  }
  ins.close();
  lib.load();
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('extras: browse pages, smart playlists, light theme, accent, tray', (tester) async {
    expect(root, isNotEmpty, reason: 'pass --dart-define=MP_ROOT=<repo>');
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
    void check(String name) {
      final e = errors.skip(seen).toSet();
      seen = errors.length;
      say('$name: ${e.isEmpty ? 'ok' : 'ERRORS ${e.join(' | ')}'}');
    }

    Future<void> shot(String name) async {
      await settle();
      await captureShot(name, shots);
      check(name);
    }

    Future<void> size(double w, double h) async {
      await windowManager.setSize(Size(w, h));
      await settle(500);
    }

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
      check(name);
    }

    await size(1440, 900);
    await setupWindow(lib, () async {}); // the real close handler, for close-to-tray
    await tester.pumpWidget(const App());
    lib.folders = [p.join(music, 'testlib'), p.join(music, 'real_music')];
    await waitFor(
      () => lib.scan.value == null && lib.tracks.length >= 45,
      timeout: const Duration(minutes: 3),
    ).catchError((Object e) => throw StateError('scan: ${lib.lastScan}, ${lib.tracks.length} songs, ${lib.scan.value}, folders ${lib.folders}'));
    fakeRows();

    // Some listening history over the last weeks, and a favourite.
    final now = DateTime.now();
    final real = lib.tracks.where((t) => t.id < 700000).toList();
    for (var d = 0; d < 40; d++) {
      for (var k = 0; k < (d * 7 + 3) % 6; k++) {
        lib.recordPlay(
          real[(d * 3 + k) % real.length].id,
          skipped: false,
          at: now.subtract(Duration(days: d, hours: k)),
        );
      }
    }
    lib.toggleFavourite(real.first.id);
    lib.load();

    final colourful = real.firstWhere(
      (t) => t.cover != null && t.album == 'Northern Lights',
      orElse: () => real.firstWhere((t) => t.cover != null),
    );
    await engine.playTracks(lib.albumByKey[colourful.albumKey]!.tracks);
    await engine.player.pause();
    await engine.seek(const Duration(seconds: 12)); // so the seek bar has a filled part to colour
    await waitFor(() => artAccent.value != null || !accentFromArt, timeout: const Duration(seconds: 10)).catchError((_) {});
    say('art accent for "${colourful.album}": ${artAccent.value}');

    final classical = lib.composers.keys.firstWhere((c) => c.contains('Beethoven'));
    final genre = lib.genres.keys.contains('Classical') ? 'Classical' : lib.genres.keys.first;
    final album = lib.albumByKey[colourful.albumKey]!;
    final smartId = lib.smartPlaylists.firstWhere((s) => s.name == 'Most played').id;
    final playlist = lib.createPlaylist('Evening', [for (final t in real.take(6)) t.id]);

    Future<void> pages(String theme) async {
      final pages = <(String, void Function())>[
        ('home', () => nav.go('home')),
        ('albums', () => nav.go('albums')),
        ('album', () => nav.push('album', album.key)),
        ('artists', () => nav.go('artists')),
        ('artist', () => nav.push('artist', album.artist)),
        ('songs', () => nav.go('songs')),
        ('folders', () => nav.go('folders')),
        ('playlists', () => nav.go('playlists')),
        ('playlist', () => nav.push('playlist', playlist)),
        ('smart', () => nav.push('smart', smartId)),
        ('favourites', () => nav.go('favourites')),
        ('genres', () => nav.go('genres')),
        ('genre', () => nav.push('genre', genre)),
        ('years', () => nav.go('years')),
        ('composers', () => nav.go('composers')),
        ('composer', () => nav.push('composer', classical)),
        ('duplicates', () => nav.go('duplicates')),
        ('stats', () => nav.go('stats')),
        ('settings', () => nav.go('settings')),
      ];
      for (final (i, (name, go)) in pages.indexed) {
        go();
        await shot('${theme}_${(i + 1).toString().padLeft(2, '0')}_$name');
      }
      nav.go('home');
      nav.toggleLyrics();
      await shot('${theme}_20_lyrics');
      nav.toggleLyrics();
      nav.setNowPlaying(true);
      await settle();
      // A simulated mouse (not the real one) over the big seek bar: it fills in the cover's colour.
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: tester.getCenter(find.byType(SeekBar).last));
      await mouse.moveBy(const Offset(40, 0));
      await shot('${theme}_21_nowplaying_accent');
      await mouse.removePointer();
      nav.setNowPlaying(false);
      nav.setSearch(true);
      await settle(300);
      await tester.enterText(find.byType(TextField), 'li');
      await shot('${theme}_22_search');
      nav.setSearch(false);
      // The smart playlist editor.
      nav.go('playlists');
      await settle();
      unawaited(editSmart(tester.element(find.byType(Scaffold).first), lib.smartPlaylist(smartId)));
      await shot('${theme}_23_smart_editor');
      Navigator.of(tester.element(find.text('Cancel'))).pop();
      await settle(300);
    }

    // 1. Every page, dark then light.
    await pages('dark');
    setAppearance('light');
    await settle();
    say('light palette active: ${C.isLight}; art accent now ${artAccent.value}');
    await pages('light');

    // 2. Small window (960 x 640) with the queue open, both themes.
    await size(960, 640);
    nav.toggleQueue();
    for (final theme in ['light', 'dark']) {
      setAppearance(theme);
      for (final pg in ['genres', 'years', 'composers', 'duplicates', 'stats']) {
        nav.go(pg);
        await shot('small_${theme}_$pg');
      }
      nav.push('smart', smartId);
      await shot('small_${theme}_smart');
    }
    nav.toggleQueue();
    await size(1440, 900);

    // 3. 130 % text on the new pages, both themes.
    for (final theme in ['dark', 'light']) {
      C.use(theme == 'light' ? Palette.light : Palette.dark); // the App (which follows the setting) is not on screen here
      for (final pg in ['genres', 'years', 'composers', 'duplicates', 'stats']) {
        nav.go(pg);
        await offscreen('text130_${theme}_$pg', const Size(1424, 860), text: 1.3);
      }
      nav.push('composer', classical);
      await offscreen('text130_${theme}_composer', const Size(1424, 860), text: 1.3);
    }
    await tester.pumpWidget(const App());
    setAppearance('dark');
    await settle();

    // 4. Tray: the menu's actions on the real engine, and close-to-tray on the real window.
    await setupTray(lib, engine);
    final playing = engine.playing;
    await trayAction('play');
    await waitFor(() => engine.playing != playing, timeout: const Duration(seconds: 10));
    final before = engine.current?.id;
    await trayAction('next');
    await waitFor(() => engine.current?.id != before, timeout: const Duration(seconds: 10));
    await trayAction('previous');
    await engine.player.pause();
    say('tray: play/pause toggled, next moved from $before to another song, previous ran');
    lib.setSetting('closeToTray', '1');
    await windowManager.close();
    await settle(500);
    final hidden = !await windowManager.isVisible();
    await trayAction('show');
    await settle(500);
    final shown = await windowManager.isVisible();
    lib.setSetting('closeToTray', '0');
    say('close to tray: hidden after close = $hidden, visible after Show = $shown');
    expect(hidden, isTrue);
    expect(shown, isTrue);
    await shot('tray_after_show');

    await engine.shutdown();
    FlutterError.onError = old;
    expect(errors, isEmpty, reason: errors.toSet().join('\n'));
  });
}
