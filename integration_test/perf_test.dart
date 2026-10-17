// Frame times with a big library: flinging Songs, Albums, Artists, Home and an album page, opening each tab,
// Now Playing, a library reload and a rescan that finds nothing new. Prints `PERF` lines (p50/p90/p99 build and
// raster ms, the share of frames over 16.7 ms, and on Android the CPU ms the UI and raster threads used), and
// fails when a fling over Songs (playing) has a p90 frame time (build or raster, the slower; build only on an
// emulator) over [budgetMs].
// Meaningful in profile mode only (debug mode just reports). Idle frames can't be counted here (the test binding
// draws frames of its own): check an idle page with `adb shell top` on the app itself.
// Android: push a big library to /sdcard/Music/GleoPerf (a media scan after `adb push`:
//   adb shell content call --method scan_volume --uri content://media --arg external_primary),
// grant the permission as in android_test.dart, then (in Git Bash also set MSYS_NO_PATHCONV=1):
//   flutter build apk --profile --target-platform android-arm64 -t integration_test/perf_test.dart --dart-define=MP_DATA=/data/user/0/com.capsuleutkarsh.gleo/files/perf
//   adb install -r build/app/outputs/flutter-apk/app-profile.apk
//   flutter drive --profile --no-dds -d <device> --use-application-binary build/app/outputs/flutter-apk/app-profile.apk
//     --driver=test_driver/perf_driver.dart --target=integration_test/perf_test.dart --dart-define=MP_DATA=/data/user/0/com.capsuleutkarsh.gleo/files/perf
//   (android-x64 on an emulator; its numbers are only for comparing before and after.)
// Windows: flutter drive --profile --no-dds -d windows --driver=test_driver/perf_driver.dart --target=integration_test/perf_test.dart
//   --dart-define=MP_DATA=<scratch folder> --dart-define=MP_MUSIC=<music folder>   (silent: the engine plays no sound there)
import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:gleo/main.dart';
import 'package:gleo/platform/android.dart' show androidMusic;
import 'package:gleo/ui/app.dart';
import 'package:window_manager/window_manager.dart';

const budgetMs = 16.7;

/// p50 / p90 / p99 of build and raster, and the share of frames over [budgetMs].
class Frames {
  Frames(List<FrameTiming> t)
    : n = t.length,
      build = _ms(t.map((f) => f.buildDuration)),
      raster = _ms(t.map((f) => f.rasterDuration)),
      worst = _ms(t.map((f) => f.buildDuration > f.rasterDuration ? f.buildDuration : f.rasterDuration));
  final int n;
  final List<double> build, raster, worst;
  static List<double> _ms(Iterable<Duration> d) => d.map((x) => x.inMicroseconds / 1000).toList()..sort();
  static double pc(List<double> v, double p) => v.isEmpty ? 0 : v[((v.length - 1) * p).round()];
  double get jank => n == 0 ? 0 : worst.where((x) => x > budgetMs).length * 100 / n;
  String _p(List<double> v) => [.5, .9, .99].map((p) => pc(v, p).toStringAsFixed(1)).join('/');
  @override
  String toString() => 'frames $n | build p50/90/99 ${_p(build)} | raster ${_p(raster)} | jank ${jank.toStringAsFixed(1)}%';
}

/// CPU ms used so far by the UI (main) and raster threads, on Android. Unlike the raster time above,
/// it leaves out waiting for the display (an emulator's raster time is mostly that).
Map<String, int> cpu() {
  final m = <String, int>{};
  if (!Platform.isAndroid) return m;
  for (final d in Directory('/proc/self/task').listSync()) {
    try {
      final s = File('${d.path}/stat').readAsStringSync();
      final name = s.substring(s.indexOf('(') + 1, s.lastIndexOf(')'));
      final key = d.path.endsWith('/$pid') ? 'ui' : (name == '1.raster' ? 'raster' : null); // Dart runs on the main thread
      if (key == null) continue;
      final f = s.substring(s.lastIndexOf(')') + 2).split(' ');
      m[key] = (m[key] ?? 0) + (int.parse(f[11]) + int.parse(f[12])) * 10; // utime + stime, in 10 ms ticks
    } catch (_) {} // a thread that just ended
  }
  return m;
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.benchmarkLive;

  testWidgets('perf', (tester) async {
    final results = <String, Object>{};
    void say(String s) => debugPrint('PERF $s');

    final data = Directory(const String.fromEnvironment('MP_DATA'));
    expect(data.path, isNotEmpty, reason: 'pass --dart-define=MP_DATA=<scratch folder>');
    const music = String.fromEnvironment('MP_MUSIC', defaultValue: '$androidMusic/GleoPerf');
    await boot(silent: !Platform.isAndroid); // never a sound on the PC
    if (lib.folders.join() != music) lib.folders = [music];
    final sw = Stopwatch()..start();
    while (lib.tracks.isEmpty || lib.scan.value != null || !lib.tracks.every((t) => t.path.startsWith(music))) {
      if (sw.elapsed > const Duration(minutes: 20)) fail('scan took too long');
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    say('library: ${lib.tracks.length} songs, ${lib.albums.length} albums (ready after ${sw.elapsed.inSeconds} s)');

    // A rescan that finds nothing new (Android rescans on every return to the app): how long, and no reload.
    var reloads = 0;
    void count() => reloads++;
    lib.addListener(count);
    sw.reset();
    await lib.rescan();
    lib.removeListener(count);
    say('rescan with nothing new: ${sw.elapsedMilliseconds} ms, library reloads: $reloads');

    if (Platform.isWindows) {
      await windowManager.ensureInitialized();
      await windowManager.setSize(const Size(1920, 1080));
      await windowManager.center();
    }
    runApp(const App());
    // Live frames: the app draws only what it schedules itself.
    Future<void> wait(int ms) => Future<void>.delayed(Duration(milliseconds: ms));

    /// Frame timings of [action] (timings arrive in batches: wait for the last one).
    Future<Frames> measure(String name, Future<void> Function() action) async {
      final got = <FrameTiming>[];
      void cb(List<FrameTiming> t) => got.addAll(t);
      SchedulerBinding.instance.addTimingsCallback(cb);
      final c0 = cpu();
      await action();
      final c1 = cpu();
      await Future<void>.delayed(const Duration(milliseconds: 1200));
      SchedulerBinding.instance.removeTimingsCallback(cb);
      final f = Frames(got);
      final used = {for (final k in c1.keys) k: c1[k]! - (c0[k] ?? 0)};
      say('$name: $f${used.isEmpty ? '' : ' | cpu ms ui ${used['ui']} raster ${used['raster']}'}');
      results[name] = {
        'frames': f.n,
        'jank%': f.jank,
        'build': [for (final p in [.5, .9, .99]) Frames.pc(f.build, p)],
        'raster': [for (final p in [.5, .9, .99]) Frames.pc(f.raster, p)],
        'cpu': used,
      };
      return f;
    }

    final size = tester.view.physicalSize / tester.view.devicePixelRatio;
    final mid = Offset(size.width / 2, size.height * 0.55);
    Future<void> flings({int n = 3, Offset? at, bool across = false}) async {
      for (var i = 0; i < n * 2; i++) {
        final down = i < n; // n flings down the list, then n back up
        final d = across ? Offset(down ? -300 : 300, 0) : Offset(0, (down ? -1 : 1) * size.height * 0.6);
        await tester.flingFrom(at ?? mid, d, 3000);
        await wait(900);
      }
    }

    Future<void> open(String name, VoidCallback go) => measure('open $name', () async {
      go();
      await wait(1500); // covers decode in the background: their frames count too
    });

    await wait(2000);
    for (final tab in ['songs', 'albums', 'artists', 'home']) {
      await open(tab, () => nav.go(tab));
      await measure('fling $tab', () => flings(n: 4)); // the first time: covers decode (and some are drawn)
      await measure('fling $tab again', () => flings(n: 4));
      if (tab == 'home') await measure('fling home shelf', () => flings(n: 2, at: Offset(size.width / 2, size.height * 0.4), across: true));
    }

    // A library reload (after a scan that found something) while Songs is open: the load, then the rebuild.
    nav.go('songs');
    await wait(1500);
    await measure('reload on songs', () async {
      final sw = Stopwatch()..start();
      lib.load();
      say('library load: ${sw.elapsedMilliseconds} ms');
      await wait(1000);
    });
    final album = lib.albums.reduce((a, b) => a.tracks.length >= b.tracks.length ? a : b);
    await open('album page', () => nav.push('album', album.key));
    await measure('fling album page', () => flings(n: 2));

    // Playing (silent on the PC: the engine runs without sound there).
    nav.go('songs');
    await wait(1000);
    await engine.playTracks(lib.tracks.take(50).toList());
    await wait(2000);
    final songs = await measure('fling songs (playing)', () => flings(n: 4));
    await measure('now playing open/close', () async {
      for (var i = 0; i < 3; i++) {
        nav.setNowPlaying(true);
        await wait(1200);
        nav.setNowPlaying(false);
        await wait(1200);
      }
    });
    nav.setNowPlaying(true);
    await wait(1500);
    await measure('now playing (playing)', () => wait(3000)); // the disc turns: a frame every vsync
    nav.setNowPlaying(false);
    await engine.togglePlay();
    await wait(1500);
    say('memory: rss ${ProcessInfo.currentRss >> 20} MB (max ${ProcessInfo.maxRss >> 20} MB), '
        'image cache ${imageCache.currentSizeBytes >> 20} MB in ${imageCache.currentSize} images');
    binding.reportData = results;
    await engine.shutdown();
    if (kProfileMode) {
      // An emulator's raster time is mostly waiting for its display: only the build time counts there.
      final emulator = Platform.isAndroid && (File('/dev/goldfish_pipe').existsSync() || File('/dev/qemu_pipe').existsSync());
      final p90 = Frames.pc(emulator ? songs.build : songs.worst, .9);
      expect(p90, lessThanOrEqualTo(budgetMs), reason: 'Songs fling p90 frame time $p90 ms');
    }
  }, timeout: const Timeout(Duration(minutes: 30)), semanticsEnabled: false); // as on a phone with no accessibility service on
}
