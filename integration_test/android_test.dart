// Lumen on Android, end to end on an emulator: scan a real folder, play, next / previous, the queue,
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
import 'package:media_kit/media_kit.dart' hide Track;
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

    // The Sound page's filters on media_kit's Android libmpv: which of them run (a failing chain turns off with a toast).
    Future<String> filters(String name, void Function(SoundSettings s) edit) async {
      sound.change(edit);
      await Future<void>.delayed(const Duration(seconds: 2));
      final af = await mpv.getProperty('af');
      say('$name: chain "${sound.chain}", ${af.isEmpty ? 'nothing runs' : 'runs'}; playing ${engine.playing}; sends ${engine.outputFormat}');
      expect(engine.playing, isTrue, reason: name);
      return af;
    }

    expect(await filters('EQ +3 dB at 1 kHz', (s) => s.eq = Eq(on: true, graphic: [0, 0, 0, 0, 0, 3, 0, 0, 0, 0])), isNotEmpty);
    await filters('Crossfeed', (s) => s.crossfeed = Crossfeed.values.last);
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
