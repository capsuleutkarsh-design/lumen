// Generated covers, Change cover, the spinning disc (Now Playing, Disc mode, mini player),
// frame strips of the disc, CPU while it spins, and 20k-song scrolling with generated covers.
// Run (never touches the real library; audio goes to mpv's null output):
//   flutter test integration_test/art_shots_test.dart -d windows
//     --dart-define=MP_DATA=<scratch>\appdata --dart-define=MP_ROOT=<repo>
//     --dart-define=MP_MUSIC=<folder holding testlib and real_music> --dart-define=MP_SHOTS=<out folder>
import 'dart:convert';
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:music_player/art/generative_cover.dart';
import 'package:music_player/main.dart';
import 'package:music_player/ui/app.dart';
import 'package:music_player/ui/cover_picker.dart';
import 'package:music_player/ui/disc.dart';
import 'package:music_player/ui/widgets.dart';
import 'package:music_player/ui/mini_player.dart';
import 'package:music_player/ui/now_playing.dart';
import 'package:path/path.dart' as p;
import 'package:window_manager/window_manager.dart';

import 'ui_shots_test.dart' show fakeTracks, waitFor, root, shots, testlib, realMusic;

final _log = StringBuffer();
void say(String s) {
  _log.writeln(s);
  File(p.join(shots, 'art_shots_log.txt')).writeAsStringSync(_log.toString());
}

/// CPU time used by this process so far (ms), from Windows.
Future<double> cpuMs() async {
  final r = await Process.run('powershell', ['-NoProfile', '-Command', '(Get-Process -Id $pid).TotalProcessorTime.TotalMilliseconds']);
  return double.parse((r.stdout as String).trim());
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('art screenshots', (tester) async {
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
    Future<void> shot(String name, [int ms = 700]) async {
      await settle(ms);
      await captureShot(name, shots);
      final e = errors.skip(seen).toSet();
      seen = errors.length;
      say('$name: ${e.isEmpty ? 'ok' : 'ERRORS ${e.join(' | ')}'}');
    }

    await windowManager.setSize(const Size(1440, 900));
    await tester.pumpWidget(const App());
    lib.folders = [testlib, realMusic];
    await waitFor(() => lib.scan.value == null && lib.tracks.length >= 45, timeout: const Duration(minutes: 3));
    fakeTracks(60, prefix: 'noart', startId: 500000, perAlbum: 10);
    lib.load();
    say('low-quality covers found by the scan: ${lib.lowCovers.length}');
    say('albums: ${lib.albums.length}, with generated art: ${lib.albums.where((a) => lib.artFor(a.key, a.cover).generated).length}');

    // 1. Grids and rows with generated covers.
    nav.go('albums');
    await shot('a01_albums', 3000);
    final noArt = lib.albums.firstWhere((a) => a.title == 'Velvet Static');
    nav.push('album', noArt.key);
    await shot('a02_album_generated', 1500);
    nav.go('home');
    await shot('a03_home', 1500);
    nav.go('songs');
    await shot('a04_songs', 1500);
    nav.go('artists');
    await shot('a05_artists', 1500);

    // 2. Change cover: the picker, a pick, and reset.
    final deep = lib.albums.firstWhere((a) => a.title == 'Deep Water');
    nav.push('album', deep.key);
    await settle(500);
    final ctx = tester.element(find.byType(Scaffold).first);
    showCoverPicker(ctx, deep);
    await shot('a06_change_cover', 3000);
    await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.byType(CoverArt)).at(4));
    await shot('a07_album_after_change', 1500);
    say('choice stored: ${lib.coverChoices[deep.key]}');
    showCoverPicker(ctx, deep);
    await shot('a08_change_cover_picked', 2000);
    await tester.tap(find.text('Reset to automatic'));
    await settle(500);
    say('after reset: ${lib.coverChoices[deep.key]}');

    // 3. Now Playing with the disc: CD and vinyl, paused and playing, real and generated art.
    final withArt = lib.albums.firstWhere((a) => a.cover != null && !lib.artFor(a.key, a.cover).generated);
    await engine.setVolume(0);
    await engine.playTracks(withArt.tracks);
    await engine.pause();
    discStyle.value = DiscStyle.cd;
    nav.go('home');
    nav.setNowPlaying(true);
    await shot('a10_np_cd_paused', 1500);
    discStyle.value = DiscStyle.vinyl;
    await shot('a11_np_vinyl_paused', 1500);
    discStyle.value = DiscStyle.off;
    await shot('a12_np_disc_off', 1000);
    discStyle.value = DiscStyle.cd;

    // Frame strips: the disc sliding out on a track change, then spinning.
    Future<void> strip(String name, int frames, int everyMs) async {
      final sw = Stopwatch()..start();
      for (var i = 0; i < frames; i++) {
        final due = i * everyMs;
        while (sw.elapsedMilliseconds < due) {
          await tester.pump();
          await Future<void>.delayed(const Duration(milliseconds: 8));
        }
        await captureShot('${name}_${i.toString().padLeft(2, '0')}', p.join(shots, 'strips'));
        say('$name frame $i at ${sw.elapsedMilliseconds} ms');
      }
    }

    // A real album (files that play) with generated art: drawn by Lumen, or picked with Change cover.
    final real = lib.albums.where((a) => a != withArt && File(a.first.path).existsSync()).toList();
    final gen = real.firstWhere((a) => lib.artFor(a.key, a.cover).generated, orElse: () => real.first);
    if (!lib.artFor(gen.key, gen.cover).generated) lib.setCoverChoice(gen.key, '${GenerativeCover.seedFor('${gen.key}#3')}');
    say('generated-art album for the disc: ${gen.title}');
    await engine.playTracks(gen.tracks);
    await strip('strip_cd_slide', 10, 90);
    await strip('strip_cd_spin', 8, 400);
    discStyle.value = DiscStyle.vinyl;
    await engine.next();
    await strip('strip_vinyl_slide', 10, 90);
    await strip('strip_vinyl_spin', 8, 250);
    await shot('a13_np_vinyl_playing_generated', 500);
    discStyle.value = DiscStyle.cd;
    await shot('a14_np_cd_playing_generated', 1500);

    // 4. CPU while the disc spins (this is a debug build: the release figures are lower).
    Future<double> cpu(String what, {int seconds = 15}) async {
      await settle(1500);
      final frames = <FrameTiming>[];
      void onT(List<FrameTiming> t) => frames.addAll(t);
      SchedulerBinding.instance.addTimingsCallback(onT);
      final a = await cpuMs();
      final sw = Stopwatch()..start();
      await Future<void>.delayed(Duration(seconds: seconds));
      final pct = (await cpuMs() - a) / sw.elapsedMilliseconds * 100;
      SchedulerBinding.instance.removeTimingsCallback(onT);
      final raster = frames.map((t) => t.rasterDuration.inMicroseconds / 1000).toList()..sort();
      final build = frames.map((t) => t.buildDuration.inMicroseconds / 1000).toList()..sort();
      say(
        'CPU $what: ${pct.toStringAsFixed(1)} % of one core; ${(frames.length / seconds).toStringAsFixed(0)} frames/s'
        '${frames.isEmpty ? '' : ', build p50 ${build[build.length ~/ 2].toStringAsFixed(2)} ms, raster p50 ${raster[raster.length ~/ 2].toStringAsFixed(2)} ms'}',
      );
      return pct;
    }

    await engine.pause();
    await cpu('Now Playing, paused (CD)');
    final idleTicking = SchedulerBinding.instance.transientCallbackCount;
    say('transient callbacks while paused: $idleTicking');
    await engine.play();
    discStyle.value = DiscStyle.off;
    await cpu('Now Playing, playing, disc off');
    discStyle.value = DiscStyle.cd;
    await cpu('Now Playing, playing, CD spinning');
    discStyle.value = DiscStyle.vinyl;
    await cpu('Now Playing, playing, vinyl spinning');
    discStyle.value = DiscStyle.cd;

    // 5. Disc mode: nothing but the cover and the disc; controls on mouse move.
    nav.setDisc(true);
    await shot('a20_discmode', 1500);
    await cpu('Disc mode, playing, CD spinning');
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(700, 500));
    await mouse.moveTo(const Offset(720, 520));
    await shot('a21_discmode_controls', 400);
    await settle(2600);
    await captureShot('a22_discmode_controls_hidden', shots);
    await mouse.removePointer();
    await toggleFullScreen();
    await shot('a23_discmode_fullscreen', 1500);
    await toggleFullScreen();
    await engine.pause();
    discStyle.value = DiscStyle.vinyl;
    await shot('a24_discmode_vinyl_paused', 1500);
    discStyle.value = DiscStyle.cd;
    nav.setDisc(false);
    nav.setNowPlaying(false);
    await settle(500);

    // 6. The mini player: compact, expanded, then back to the full window.
    await engine.play();
    await setMini(true);
    await shot('a30_mini', 1500);
    say(
      'mini window: ${await windowManager.getSize()} at ${await windowManager.getPosition()}, on top: ${await windowManager.isAlwaysOnTop()}',
    );
    await setMiniExpanded(true);
    await shot('a31_mini_expanded', 1500);
    say('mini expanded: ${await windowManager.getSize()}');
    await setMiniExpanded(false);
    await setMini(false);
    await shot('a32_back_to_full', 1000);
    say(
      'full again: ${await windowManager.getSize()}, on top: ${await windowManager.isAlwaysOnTop()}, mini saved at ${lib.setting('mini')}',
    );
    await engine.pause();

    // 7. Drawing cost of one cover on the UI thread (what ArtCache does once per album and size).
    for (final px in [128, 384]) {
      final ms = <double>[];
      for (var i = 0; i < 60; i++) {
        final sw = Stopwatch()..start();
        GenerativeCover(GenerativeCover.seedFor('bench/$i')).record(px).dispose();
        ms.add(sw.elapsedMicroseconds / 1000);
      }
      ms.sort();
      say(
        'record $px px on the UI thread: p50 ${ms[30].toStringAsFixed(1)} p90 ${ms[54].toStringAsFixed(1)} max ${ms.last.toStringAsFixed(1)} ms',
      );
    }

    // 8. Scrolling 20k songs whose albums all need generated covers (first render, nothing cached).
    fakeTracks(20000, prefix: 'big', startId: 1000000, albumOffset: 100);
    lib.load();
    nav.go('songs');
    await settle(800);
    final sp = tester
        .stateList<ScrollableState>(find.byType(Scrollable))
        .map((s) => s.position)
        .reduce((a, b) => a.maxScrollExtent >= b.maxScrollExtent ? a : b); // the page, not the rail
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
    double pct(List<double> xs, double q) => xs[(xs.length * q).floor().clamp(0, xs.length - 1)];
    List<double> sorted(double Function(FrameTiming) f) => timings.map(f).toList()..sort();
    final b = sorted((t) => t.buildDuration.inMicroseconds / 1000);
    final r = sorted((t) => t.rasterDuration.inMicroseconds / 1000);
    final total = sorted((t) => t.totalSpan.inMicroseconds / 1000);
    say('scrolled to ${sp.pixels.round()} of ${sp.maxScrollExtent.round()} px');
    say(
      'scroll ${lib.tracks.length} songs (${lib.albums.length} albums): ${timings.length} frames; build p50 ${pct(b, .5)} p90 ${pct(b, .9)} max ${b.last} ms; '
      'raster p50 ${pct(r, .5)} p90 ${pct(r, .9)} max ${r.last} ms; total span p90 ${pct(total, .9)} max ${total.last} ms',
    );
    await shot('a40_songs_20k_generated', 3000);
    final drawn = Directory(p.join(const String.fromEnvironment('MP_DATA'), 'art')).listSync().length;
    say('generated cover files in the cache: $drawn');
    say('window setting: ${jsonDecode(lib.setting('window') ?? 'null')}');
    await engine.shutdown();
    FlutterError.onError = old;
    expect(errors, isEmpty, reason: errors.toSet().join('\n'));
  });
}
