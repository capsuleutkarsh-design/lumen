// UI/UX audit screenshots: the states the other harnesses skip (first start, dialogs, focus,
// hover, errors, mini player, disc mode, big and small windows, a big library's frame times).
// Run (never touches the real library; audio goes to mpv's null output):
//   flutter test integration_test/audit_shots_test.dart -d windows
//     --dart-define=MP_DATA=<scratch>\appdata --dart-define=MP_ROOT=<repo>
//     --dart-define=MP_MUSIC=<folder holding testlib and real_music> --dart-define=MP_SHOTS=<out folder>
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:gleo/main.dart';
import 'package:gleo/ui/app.dart';
import 'package:gleo/ui/cover_picker.dart';
import 'package:gleo/ui/mini_player.dart';
import 'package:gleo/ui/pages/albums.dart';
import 'package:gleo/ui/pages/credits.dart';
import 'package:gleo/ui/pages/songs.dart';
import 'package:gleo/ui/player_bar.dart';
import 'package:gleo/ui/theme.dart';
import 'package:gleo/ui/tracks.dart';
import 'package:gleo/ui/widgets.dart';
import 'package:path/path.dart' as p;
import 'package:window_manager/window_manager.dart';

import 'ui_shots_test.dart' as u show fakeTracks, byFile, waitFor, music;

const _shots = String.fromEnvironment('MP_SHOTS');
final shots = p.join(_shots, 'audit');
final log = StringBuffer();

void say(String s) {
  log.writeln(s);
  File(p.join(shots, 'audit_log.txt')).writeAsStringSync(log.toString());
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('audit screenshots', (tester) async {
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
    void check(String name) {
      final e = errors.skip(seen).toSet();
      seen = errors.length;
      say('$name: ${e.isEmpty ? 'ok' : 'ERRORS ${e.join(' | ')}'}');
    }

    Future<void> shot(String name, [int ms = 700]) async {
      await settle(ms);
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

    BuildContext ctx() => tester.element(find.byType(Scaffold).first);
    Future<void> closeDialog() async {
      Navigator.of(tester.element(find.byType(AlertDialog))).pop();
      await settle(300);
    }

    Future<void> esc() async {
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await settle(200);
    }

    /// Frame build/raster times while jumping down the page's first scrollable.
    Future<void> frames(String what, {int steps = 150, double by = 300}) async {
      final sp = tester.state<ScrollableState>(find.byType(Scrollable).first).position;
      final timings = <FrameTiming>[];
      void onT(List<FrameTiming> t) => timings.addAll(t);
      SchedulerBinding.instance.addTimingsCallback(onT);
      for (var i = 0; i < steps; i++) {
        sp.jumpTo((sp.pixels + by).clamp(0, sp.maxScrollExtent));
        await tester.pump();
        await Future<void>.delayed(const Duration(milliseconds: 16));
      }
      await settle(500);
      SchedulerBinding.instance.removeTimingsCallback(onT);
      if (timings.isEmpty) return say('$what: no frame timings');
      double pct(List<double> xs, double q) => xs[(xs.length * q).floor().clamp(0, xs.length - 1)];
      final b = timings.map((t) => t.buildDuration.inMicroseconds / 1000).toList()..sort();
      final r = timings.map((t) => t.rasterDuration.inMicroseconds / 1000).toList()..sort();
      final slow = timings.where((t) => t.totalSpan.inMicroseconds > 16667).length;
      say(
        '$what: ${timings.length} frames, $slow over 16.7 ms; build p50 ${pct(b, .5)} p90 ${pct(b, .9)} max ${b.last} ms; '
        'raster p50 ${pct(r, .5)} p90 ${pct(r, .9)} max ${r.last} ms',
      );
    }

    final testlib = p.join(u.music, 'testlib');
    final realMusic = p.join(u.music, 'real_music');

    // ------------------------------------------------------------ 1. First start, empty library
    await size(1360, 860); // the default window
    await tester.pumpWidget(const App());
    await shot('a01_first_home');
    for (final pg in ['songs', 'albums', 'artists', 'folders', 'playlists', 'favourites', 'genres', 'stats', 'settings', 'sound']) {
      nav.go(pg);
      await shot('a02_first_$pg');
    }
    nav.go('home');
    nav.toggleQueue();
    await shot('a03_first_queue_empty');
    nav.toggleQueue();
    nav.toggleLyrics();
    await shot('a04_first_lyrics_nothing');
    nav.toggleLyrics();
    nav.setNowPlaying(true);
    await shot('a05_first_nowplaying_nothing');
    nav.setNowPlaying(false);
    nav.setSearch(true);
    await shot('a06_first_search_hint');
    nav.setSearch(false);
    setAppearance('light');
    await shot('a07_first_home_light');
    setAppearance('dark');
    await size(960, 640);
    await shot('a08_first_home_min');
    await size(1360, 860);

    // ------------------------------------------------------------ 2. Adding folders: the first scan
    lib.folders = [testlib, realMusic];
    await tester.pump();
    await shot('a10_scan_starts', 100);
    await shot('a11_scan_later', 400);
    await u.waitFor(() => lib.scan.value == null && lib.tracks.length >= 45, timeout: const Duration(minutes: 3));
    await shot('a12_home_after_scan_no_plays');

    // ------------------------------------------------------------ 3. History, favourites, playlists
    final now = DateTime.now();
    void plays(String f, List<int> daysAgo) {
      for (final d in daysAgo) {
        lib.recordPlay(u.byFile(f).id, skipped: false, at: now.subtract(Duration(days: d, hours: 1)));
      }
    }

    plays(r'Northern Lights (2017)\03 Magnetic.flac', [0, 1, 2, 4]);
    plays(r'CD1\02 Kelp Forest.flac', [2, 5, 6]);
    plays(r'Summer Mix\03 Lemonade.mp3', [40, 45, 50, 60]);
    plays(r'Hi-Res Sketches\04 Chalk Lines.flac', [8]);
    lib.toggleFavourite(u.byFile(r'Northern Lights (2017)\03 Magnetic.flac').id);
    lib.toggleFavourite(u.byFile(r'CD2\03 Currents.flac').id);
    u.fakeTracks(30, prefix: 'noart', startId: 500000, perAlbum: 10);
    lib.load();
    final pl = lib.createPlaylist('Late night drive', [
      for (final f in [r'CD1\03 Pressure.flac', r'Hi-Res Sketches\03 Interlude.flac', r'Summer Mix\07 Late August.flac']) u.byFile(f).id,
    ]);
    final empty = lib.createPlaylist('Empty for now');
    lib.load();
    final etude = u.byFile(r'Hi-Res Sketches\01 Etude in Glass.flac');
    final hiRes = lib.albumByKey[etude.albumKey]!;
    final summer = lib.albums.firstWhere((a) => a.title == 'Summer Mix');
    final deep = lib.albums.firstWhere((a) => a.title == 'Deep Water');
    await engine.playTracks(hiRes.tracks);
    await engine.seek(const Duration(milliseconds: 6400));
    await u.waitFor(() => engine.position.value > const Duration(seconds: 6));
    await engine.player.pause();
    await engine.setVolume(60);
    final smartId = lib.smartPlaylists.first.id;

    // ------------------------------------------------------------ 4. Every page, default window
    final pages = <(String, void Function())>[
      ('home', () => nav.go('home')),
      ('songs', () => nav.go('songs')),
      ('albums', () => nav.go('albums')),
      ('album_compilation', () => nav.push('album', summer.key)),
      ('album_twodiscs', () => nav.push('album', deep.key)),
      ('artists', () => nav.go('artists')),
      ('artist', () => nav.push('artist', 'Aurora Fields')),
      ('folders', () => nav.go('folders')),
      ('folders_sub', () => nav.push('folder', p.join(testlib, 'The Tidal Set', 'Deep Water'))),
      ('playlists', () => nav.go('playlists')),
      ('playlist', () => nav.push('playlist', pl)),
      ('playlist_empty', () => nav.push('playlist', empty)),
      ('smart', () => nav.push('smart', smartId)),
      ('favourites', () => nav.go('favourites')),
      ('genres', () => nav.go('genres')),
      ('years', () => nav.go('years')),
      ('duplicates', () => nav.go('duplicates')),
      ('stats', () => nav.go('stats')),
      ('settings', () => nav.go('settings')),
      ('sound', () => nav.go('sound')),
    ];
    for (final (i, (name, go)) in pages.indexed) {
      go();
      await shot('b${(i + 1).toString().padLeft(2, '0')}_$name');
    }
    nav.go('settings');
    await settle();
    await Scrollable.ensureVisible(tester.element(find.text('Keyboard')), alignment: 0.1);
    await shot('b30_settings_lower');
    await Scrollable.ensureVisible(tester.element(find.text('About')), alignment: 0.5);
    await shot('b31_settings_bottom');

    // ------------------------------------------------------------ 5. Hover and keyboard focus
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    nav.go('albums');
    await settle();
    await mouse.addPointer(location: tester.getCenter(find.byType(AlbumCard).first));
    await shot('c01_hover_album_card', 1200);
    nav.go('songs');
    await settle();
    await mouse.moveTo(tester.getCenter(find.byType(TrackRow).at(2)));
    await shot('c02_hover_song_row', 1200);
    await mouse.moveTo(tester.getCenter(find.byType(PlayerBar)) + const Offset(-200, 0));
    await shot('c03_hover_player_bar', 1200);
    await mouse.removePointer();
    nav.go('home');
    await settle();
    for (var i = 1; i <= 12; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await settle(100);
      if (i == 1 || i == 4 || i == 12) await shot('c1${i.toString().padLeft(2, '0')}_focus_home_tab$i');
    }
    nav.go('songs');
    await settle();
    await tester.tap(find.byType(TrackRow).at(1), warnIfMissed: false);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await shot('c20_keyboard_rows');
    selection.clear();

    // ------------------------------------------------------------ 6. Menus and dialogs
    nav.go('albums');
    await settle();
    await tester.tap(find.textContaining('Sort:'));
    await shot('d01_sort_menu');
    await esc();
    await tester.tap(find.byTooltip('Sleep timer'));
    await shot('d02_sleep_menu');
    await esc();
    await tester.tap(find.descendant(of: find.byType(PlayerBar), matching: find.byTooltip('More')));
    await shot('d03_player_more_menu');
    await esc();
    unawaited(addToPlaylistDialog(ctx(), hiRes.tracks.take(2).toList()));
    await shot('d04_add_to_playlist');
    await tester.tap(find.text('Late night drive').last);
    await shot('d05_toast_added_to_playlist', 400);
    unawaited(askText(ctx(), 'New playlist', action: 'Create'));
    await shot('d06_new_playlist');
    await closeDialog();
    unawaited(confirm(ctx(), 'Delete “Late night drive”?', 'The songs stay in your library; only the playlist is removed.'));
    await shot('d07_confirm_delete');
    await closeDialog();
    unawaited(showCoverPicker(ctx(), deep));
    await shot('d08_change_cover', 2500);
    await closeDialog();
    unawaited(showCredits(ctx()));
    await shot('d09_credits', 1200);
    await closeDialog();
    nav.push('album', deep.key);
    await settle();
    await tester.tap(find.byType(TrackRow).first, buttons: kSecondaryButton);
    await shot('d10_song_menu');
    await esc();

    // ------------------------------------------------------------ 7. Toasts and errors
    await engine.playTracks([lib.byId[500001]!]); // the file does not exist
    await shot('e01_error_missing_file', 1500);
    await engine.playTracks(hiRes.tracks);
    await engine.player.pause();
    lib.toggleFavourite(hiRes.tracks[1].id);
    await shot('e02_after_favourite_no_toast', 400);

    // ------------------------------------------------------------ 8. Queue, lyrics, Now Playing, disc, mini
    await engine.addToQueue([...summer.tracks, ...deep.tracks]);
    nav.go('home');
    nav.toggleQueue();
    await shot('f01_queue_long');
    nav.toggleQueue();
    await engine.playTracks(summer.tracks);
    await engine.player.pause();
    nav.toggleLyrics();
    await shot('f02_lyrics_none');
    nav.toggleLyrics();
    nav.setNowPlaying(true);
    await shot('f03_nowplaying_no_lyrics');
    nav.setNowPlaying(false);
    await engine.playTracks(hiRes.tracks);
    await engine.player.pause();
    nav.setDisc(true);
    await shot('f04_disc_mode', 1200);
    nav.setDisc(false);
    await setMini(true);
    await shot('f05_mini_compact', 1200);
    await setMiniExpanded(true);
    await shot('f06_mini_expanded', 1200);
    await setMiniExpanded(false);
    await setMini(false);
    await settle(800);

    // ------------------------------------------------------------ 8b. States the 0.4 desktop fixes added
    nav.toggleLyrics();
    await shot('w01_lyrics_synced', 1200);
    nav.toggleLyrics();
    await engine.addToQueue([...summer.tracks, ...deep.tracks]);
    await engine.next();
    await engine.next();
    await engine.player.pause();
    nav.toggleQueue();
    await settle();
    await tester.tap(find.textContaining('History ·'));
    await shot('w02_queue_history');
    await tester.tap(find.text('Clear'));
    await shot('w03_queue_cleared_undo', 400);
    nav.toggleQueue();
    setSleep(30);
    await settle(200);
    await tester.tap(find.byTooltip(sleepTip(ctx())));
    await shot('w04_sleep_menu_on');
    await esc();
    nav.push('folder', p.join(testlib, 'The Tidal Set'));
    await settle();
    nav.push('folder', p.join(testlib, 'The Tidal Set', 'Deep Water'));
    await settle();
    nav.back();
    await shot('w05_folders_after_back');
    if (lib.composers.isNotEmpty) {
      nav.push('composer', lib.composers.keys.first);
      await shot('w06_composer');
    }
    nav.go('songs');
    await settle();
    selection.selectAll();
    toast(ctx(), 'A toast while songs are selected');
    await shot('w07_toast_over_selection', 400);
    selection.clear();
    nav.setSearch(true);
    await settle(300);
    await tester.enterText(find.byType(TextField).last, 'an');
    await tester.ensureVisible(find.textContaining('Show all'));
    await shot('w08_search_show_all');
    await tester.tap(find.textContaining('Show all'));
    await shot('w09_songs_filtered');
    songsFilter.value = '';
    await engine.playTracks([lib.byId[500003]!, lib.byId[500004]!, lib.byId[500005]!]); // missing files, one after another
    await shot('w10_failures_merged', 2500);
    await engine.playTracks(hiRes.tracks);
    await engine.player.pause();
    await size(960, 640);
    await tester.tap(find.descendant(of: find.byType(PlayerBar), matching: find.byTooltip('More · ${sleepTip(ctx())}')));
    await shot('w11_min_more_menu_with_sleep');
    await esc();
    setSleep(0);
    await size(1360, 860);

    // ------------------------------------------------------------ 9. Large window (maximised on 1920 x 1080) and 1920 x 1080 offscreen
    await windowManager.maximize();
    await settle(800);
    for (final (name, go) in <(String, void Function())>[
      ('home', () => nav.go('home')),
      ('albums', () => nav.go('albums')),
      ('album', () => nav.push('album', deep.key)),
      ('songs', () => nav.go('songs')),
      ('settings', () => nav.go('settings')),
      ('sound', () => nav.go('sound')),
    ]) {
      go();
      await shot('g_max_$name');
    }
    nav.go('home');
    nav.setNowPlaying(true);
    await shot('g_max_nowplaying');
    nav.setNowPlaying(false);
    nav.setSearch(true);
    await settle(300);
    await tester.enterText(find.byType(TextField), 'a');
    await shot('g_max_search_many');
    await tester.enterText(find.byType(TextField), 'zzqx');
    await shot('g_max_search_none');
    nav.setSearch(false);
    await windowManager.unmaximize();
    await size(1360, 860);

    // ------------------------------------------------------------ 10. The smallest window (960 x 640), both themes
    await size(960, 640);
    for (final theme in ['dark', 'light']) {
      setAppearance(theme);
      for (final (name, go) in <(String, void Function())>[
        ('home', () => nav.go('home')),
        ('album', () => nav.push('album', deep.key)),
        ('artist', () => nav.push('artist', 'Aurora Fields')),
        ('songs', () => nav.go('songs')),
        ('settings', () => nav.go('settings')),
        ('sound', () => nav.go('sound')),
        ('stats', () => nav.go('stats')),
      ]) {
        go();
        await shot('h_min_${theme}_$name');
      }
      nav.go('home');
      nav.setNowPlaying(true);
      await shot('h_min_${theme}_nowplaying');
      nav.setNowPlaying(false);
      nav.toggleQueue();
      nav.go('albums');
      await shot('h_min_${theme}_albums_queue');
      nav.toggleQueue();
    }

    // ------------------------------------------------------------ 11. Light theme at the default size: what extras skips
    await size(1360, 860);
    setAppearance('light');
    nav.go('albums');
    await settle();
    unawaited(addToPlaylistDialog(ctx(), hiRes.tracks.take(2).toList()));
    await shot('i01_light_add_to_playlist');
    await closeDialog();
    await tester.tap(find.textContaining('Sort:'));
    await shot('i02_light_menu');
    await esc();
    nav.go('home');
    nav.toggleQueue();
    await shot('i03_light_queue');
    nav.toggleQueue();
    unawaited(showCoverPicker(ctx(), deep));
    await shot('i04_light_change_cover', 2500);
    await closeDialog();
    await engine.playTracks([lib.byId[500002]!]);
    await shot('i05_light_error_toast', 1500);
    await engine.playTracks(hiRes.tracks);
    await engine.player.pause();
    nav.setDisc(true);
    await shot('i06_light_disc_mode', 1200);
    nav.setDisc(false);
    setAppearance('dark');

    // ------------------------------------------------------------ 12. Below the minimum size (offscreen; the window cannot get this small)
    nav.go('home');
    await offscreen('j01_900x600_home', const Size(900, 600));
    nav.push('album', deep.key);
    await offscreen('j02_900x600_album', const Size(900, 600));
    nav.go('home');
    await offscreen('j03_1920x1080_home', const Size(1920, 1080));
    nav.go('albums');
    await offscreen('j04_1920x1080_albums', const Size(1920, 1080));
    for (final (name, go) in <(String, void Function())>[
      ('songs', () => nav.go('songs')),
      ('album', () => nav.push('album', deep.key)),
      ('home', () => nav.go('home')),
    ]) {
      go();
      await offscreen('j1_text150_$name', const Size(1360, 860), text: 1.5);
    }
    for (final (name, go) in <(String, void Function())>[
      ('songs', () => nav.go('songs')),
      ('album', () => nav.push('album', deep.key)),
      ('home', () => nav.go('home')),
    ]) {
      go();
      await offscreen('j1_text150_$name', const Size(1360, 860), text: 1.5);
    }
    await tester.pumpWidget(const App());
    await settle();

    // ------------------------------------------------------------ 13. A big library: 2,400 more songs in 200 albums with drawn covers
    u.fakeTracks(2400, prefix: 'big', startId: 1000000, albumOffset: 100);
    lib.load();
    say('library: ${lib.tracks.length} songs, ${lib.albums.length} albums, ${lib.artists.length} artists');
    nav.go('albums');
    await settle(1500);
    await frames('scroll albums grid', steps: 120, by: 400);
    await shot('k01_big_albums_scrolled', 300);
    nav.go('artists');
    await settle(1500);
    await frames('scroll artists grid', steps: 80, by: 400);
    nav.go('songs');
    await settle(800);
    await frames('scroll songs list', steps: 150, by: 300);
    nav.go('home');
    await settle(800);
    nav.go('songs');
    final sw = Stopwatch()..start();
    await tester.pump();
    say('open Songs with ${lib.tracks.length} songs: first frame after ${sw.elapsedMilliseconds} ms');
    await shot('k02_big_songs');

    await engine.shutdown();
    FlutterError.onError = old;
    say('flutter errors: ${errors.toSet().join(' | ')}');
  });
}
