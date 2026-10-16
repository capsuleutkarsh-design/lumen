// Lumen on Android, end to end on an emulator: scan a real folder, play, next / previous, the queue, the sleep timer,
// the output Android reports, and screenshots of every phone screen in dark and light.
// Run (the music permission is granted first, as the app's own button would after "Allow"):
//   adb push <testlib> /sdcard/Music/LumenTest/testlib
//   adb shell pm grant com.capsuleutkarsh.lumen android.permission.READ_EXTERNAL_STORAGE   (READ_MEDIA_AUDIO on 13+)
//   flutter test integration_test/android_test.dart -d emulator-5554 --dart-define=MP_DATA=/data/user/0/com.capsuleutkarsh.lumen/files/itest
// Screenshots and the report go to the app's external files folder:
//   adb pull /sdcard/Android/data/com.capsuleutkarsh.lumen/files/shots
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:media_kit/media_kit.dart' hide Track;
import 'package:music_player/audio/engine.dart' show StopAfter;
import 'package:music_player/audio/sound.dart';
import 'package:music_player/main.dart';
import 'package:music_player/platform/android.dart';
import 'package:music_player/ui/app.dart';
import 'package:music_player/ui/lyrics_view.dart';
import 'package:path_provider/path_provider.dart';

const music = '$androidMusic/LumenTest';

Future<void> waitFor(bool Function() ok, {Duration timeout = const Duration(seconds: 30), String what = ''}) async {
  final sw = Stopwatch()..start();
  while (!ok()) {
    if (sw.elapsed > timeout) throw TimeoutException('waiting for $what');
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
}

void main() {
  if (!Platform.isAndroid) {
    test('android end to end', () {}, skip: 'runs on an Android device or emulator');
    return;
  }
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('android end to end', (tester) async {
    final shots = '${(await getExternalStorageDirectory())!.path}/shots';
    Directory(shots).createSync(recursive: true);
    final report = StringBuffer();
    void say(String s) {
      report.writeln(s);
      debugPrint('REPORT $s');
      File('$shots/android_report.txt').writeAsStringSync(report.toString());
    }

    final data = Directory(const String.fromEnvironment('MP_DATA'));
    expect(data.path, isNotEmpty, reason: 'pass --dart-define=MP_DATA=<app folder>');
    if (data.existsSync()) data.deleteSync(recursive: true);
    final errors = <String>[];
    final old = FlutterError.onError;
    FlutterError.onError = (d) {
      errors.add(d.exceptionAsString().split('\n').first);
      old?.call(d);
    };

    await boot(logLevel: MPVLogLevel.v);
    engine.player.stream.log.listen((l) {
      if (l.prefix.startsWith('ao') || l.level == 'error' || l.level == 'warn' || l.text.contains('audio')) debugPrint('MPV ${l.prefix}: ${l.text.trim()}');
    });
    say('Android API ${audioRoute.value?.sdk}; music access: ${musicAccess.value}; output: ${audioRoute.value?.name}, '
        'mixer ${audioRoute.value?.mixerRate} Hz, device rates ${audioRoute.value?.rates}');
    expect(musicAccess.value, isTrue, reason: 'grant the music permission with adb first');
    expect(audioRoute.value, isNotNull);

    // The library: a real folder on shared storage, read through dart:io.
    lib.folders = [music];
    await waitFor(() => lib.tracks.isNotEmpty, timeout: const Duration(minutes: 3), what: 'scan');
    await waitFor(() => lib.scan.value == null, timeout: const Duration(minutes: 3), what: 'scan end');
    final deep = lib.albums.firstWhere((a) => a.title == 'Deep Water');
    final northern = lib.albums.firstWhere((a) => a.title.startsWith('Northern Lights'));
    final etude = lib.tracks.firstWhere((t) => t.title == 'Etude in Glass');
    say('Scanned ${lib.tracks.length} songs in ${lib.albums.length} albums (${lib.lastScan})');
    say('folder.jpg cover (Northern Lights): ${northern.cover != null}; embedded cover (Etude): ${etude.cover != null}; '
        '.lrc lyrics beside Etude: ${lyricsFor(etude) != null}');
    final names = {for (final t in lib.tracks) t.path.split('/').last};
    say('Not in the library: ${[for (final f in Directory(music).listSync(recursive: true).whereType<File>()) if (!names.contains(f.path.split('/').last)) f.path.split('/').last]}');
    expect(deep.tracks.length, 8);
    expect(lib.tracks.length, greaterThanOrEqualTo(35));
    expect(etude.cover, isNotNull, reason: 'embedded cover');

    runApp(const App());
    Future<void> settle([int ms = 800]) async {
      for (var i = 0; i < ms ~/ 50; i++) {
        await tester.pump(const Duration(milliseconds: 50));
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    }

    await settle(1500);

    // Play an album, then next / previous through the queue.
    final mpv = engine.player.platform as NativePlayer;
    await engine.playTracks(deep.tracks);
    await Future<void>.delayed(const Duration(seconds: 3));
    say('After 3 s: playing ${engine.playing}, at ${engine.position.value}, ao ${await mpv.getProperty('current-ao')}, idle ${await mpv.getProperty('idle-active')}');
    await waitFor(() => engine.playing && engine.position.value > const Duration(seconds: 1), what: 'playing');
    say('Playing ${engine.current!.title}: ao ${await mpv.getProperty('current-ao')}, '
        'source ${engine.srcFormat} ${engine.srcRate} Hz, sends ${engine.outputFormat}');
    say('Signal path: ${sound.path.steps.join(' → ')} | not bit-perfect: ${sound.path.why.join(', ')}');
    expect(engine.queue.items.length, 8);
    await engine.next();
    await waitFor(() => engine.current?.id == deep.tracks[1].id && engine.playing, what: 'next');
    await engine.previous();
    await waitFor(() => engine.current?.id == deep.tracks[0].id && engine.playing, what: 'previous');
    await engine.addToQueue([etude]);
    expect(engine.queue.items.length, 9);
    say('Next, previous and Add to queue: ok');

    // The Sound page on Lumen's own Android libmpv: every filter and soxr run, the song keeps playing,
    // and mpv logs no error ("osc" is media_kit asking for the Lua OSC, which the engine leaves out).
    final mpvErrors = <String>[];
    engine.player.stream.log.listen((l) {
      if (l.level == 'error' && !l.text.contains('osc')) mpvErrors.add('${l.prefix}: ${l.text.trim()}');
    });
    Future<String> filters(String name, void Function(SoundSettings s) edit) async {
      final errs = mpvErrors.length;
      sound.change(edit);
      await Future<void>.delayed(const Duration(seconds: 1));
      final from = engine.position.value;
      await Future<void>.delayed(const Duration(seconds: 2));
      final af = await mpv.getProperty('af');
      final moved = engine.position.value - from;
      say('$name: chain "${sound.chain}", ${af.isEmpty ? 'nothing runs' : 'runs'}; resampler "${await mpv.getProperty('audio-swresample-o')}"; '
          'in ${await mpv.getProperty('audio-params/samplerate')} Hz, out ${await mpv.getProperty('audio-out-params/samplerate')} Hz '
          '${await mpv.getProperty('audio-out-params/format')}; played ${moved.inMilliseconds} ms in 2 s; mpv errors ${mpvErrors.skip(errs).toList()}');
      expect(engine.playing, isTrue, reason: name);
      expect(af, isNotEmpty, reason: name);
      expect(moved, greaterThan(const Duration(milliseconds: 1500)), reason: '$name: the sound must keep going');
      expect(mpvErrors.skip(errs), isEmpty, reason: name);
      return af;
    }

    final rock = builtInPresets.firstWhere((p) => p.name == 'Rock').copy()..on = true;
    expect(await filters('EQ preset Rock', (s) => s.eq = rock.copy()), contains('equalizer'));
    expect(await filters('Crossfeed', (s) => s.crossfeed = Crossfeed.values.last), contains('bs2b'));
    await filters('Night mode', (s) => s.eq.night = true);
    await filters('Advanced EQ curve', (s) {
      s.crossfeed = Crossfeed.off;
      s.eq.night = false;
      s.eq.advanced = true;
      s.eq.curve.addAll([(100.0, 2.0), (1000.0, -1.0), (8000.0, 1.0)]);
    });
    await filters('Levelling', (s) {
      s.eq = Eq();
      s.levelling = true;
    });
    // Best quality with a song whose rate differs from Android's output: soxr converts it.
    final native = audioRoute.value!.nativeRate;
    final other = lib.tracks.firstWhere((t) => t.sampleRate > 0 && t.sampleRate != native);
    await engine.playTracks([other]);
    await waitFor(() => engine.playing && engine.position.value > const Duration(milliseconds: 500), what: 'Best quality song');
    final best = await filters(
      'Best quality, Rock and crossfeed (${other.sampleRate} Hz song, Android at $native Hz)',
      (s) => s
        ..bestQuality = true
        ..levelling = false
        ..eq = rock.copy()
        ..crossfeed = Crossfeed.values.last,
    );
    expect(best, allOf(contains('equalizer'), contains('bs2b')));
    expect(await mpv.getProperty('audio-swresample-o'), contains('soxr'));
    expect(await mpv.getProperty('audio-out-params/samplerate'), '$native');
    await engine.playTracks(deep.tracks);
    await waitFor(() => engine.playing, what: 'back to Deep Water');
    sound.change((s) => s
      ..eq = Eq()
      ..levelling = false
      ..crossfeed = Crossfeed.off);
    await Future<void>.delayed(const Duration(seconds: 1));
    await engine.play();

    // Screenshots of every main phone screen, dark and light.
    Future<void> shot(String name) async {
      await settle();
      final boundary = shotKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 2);
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      File('$shots/$name.png').writeAsBytesSync(png!.buffer.asUint8List());
    }

    // The sleep timer on the phone's Now Playing: the moon's sheet sets it (highlighted, with the time it
    // pauses), stops after this song, turns it off; a short timer fades out and pauses.
    nav.setNowPlaying(true);
    await settle();
    final moon = find.byIcon(LucideIcons.moon).first;
    await tester.tap(moon);
    await shot('dark_sleep_sheet');
    await tester.tap(find.text('15 minutes'));
    await settle();
    expect(engine.sleepAt, isNotNull);
    expect(find.textContaining('pauses at'), findsWidgets);
    await shot('dark_sleep_on');
    await tester.tap(moon);
    await settle();
    await tester.tap(find.text('End of this song'));
    await settle();
    expect((engine.sleepAt, engine.stopAfter), (null, StopAfter.song));
    expect(find.text('Stops after this song'), findsOneWidget);
    await tester.tap(moon);
    await settle();
    await tester.tap(find.text('Turn off'));
    await settle();
    expect((engine.sleepAt, engine.stopAfter), (null, StopAfter.none));
    expect(find.textContaining('Stops after'), findsNothing);
    nav.setNowPlaying(false);
    engine.sleepIn(const Duration(seconds: 3));
    await waitFor(() => !engine.playing, timeout: const Duration(seconds: 10), what: 'sleep timer pause');
    expect(engine.sleepAt, isNull);
    say('Sleep timer: the sheet sets 15 minutes, End of this song and Turn off; a 3 s timer paused the music');
    await engine.play();

    for (final theme in ['dark', 'light']) {
      setAppearance(theme);
      await settle();
      for (final page in ['home', 'albums', 'artists', 'songs', 'genres', 'playlists', 'folders', 'favourites', 'sound', 'settings']) {
        nav.go(page);
        await shot('${theme}_$page');
      }
      nav.push('album', deep.key);
      await shot('${theme}_album');
      nav.go('home');
      await tester.tap(find.byKey(const ValueKey('nav.more')));
      await shot('${theme}_more');
      Navigator.of(tester.element(find.text('Playlists').last)).pop();
      await settle();
      nav.setNowPlaying(true);
      await shot('${theme}_now_playing');
      nav.setNowPlaying(false);
      nav.toggleQueue();
      await shot('${theme}_queue');
      nav.toggleQueue();
      nav.setDisc(true);
      await shot('${theme}_disc');
      nav.setDisc(false);
    }

    // Disc mode, Now Playing and a page in landscape.
    setAppearance('dark');
    final size = tester.view.physicalSize;
    tester.view.physicalSize = Size(size.height, size.width);
    nav.setDisc(true);
    await shot('dark_disc_landscape');
    nav.setDisc(false);
    nav.setNowPlaying(true);
    await shot('dark_now_playing_landscape');
    nav.setNowPlaying(false);
    nav.go('songs');
    await shot('dark_songs_landscape');
    tester.view.resetPhysicalSize();
    await settle();

    say('Errors on screen: ${errors.isEmpty ? 'none' : errors.join(' | ')}');
    expect(errors, isEmpty);
    await engine.pause();
  });
}
