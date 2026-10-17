// Gleo on Android, end to end on an emulator: scan a real folder, play, next / previous, the queue, the sleep timer,
// the output Android reports, the phone's search, tabs, sheets, EQ and folders, text contrast over bright covers,
// and screenshots of every phone screen in dark and light.
// Run (the music permission is granted first, as the app's own button would after "Allow"):
//   adb push <testlib> /sdcard/Music/GleoTest/testlib
//   adb push <contrast> /sdcard/Music/GleoTest/contrast   (optional: White, Cyan and Yellow albums with plain covers)
//   adb shell pm grant com.capsuleutkarsh.gleo android.permission.READ_EXTERNAL_STORAGE   (READ_MEDIA_AUDIO on 13+)
//   flutter test integration_test/android_test.dart -d emulator-5554 --no-uninstall --dart-define=MP_DATA=/data/user/0/com.capsuleutkarsh.gleo/files/itest
// Screenshots and the report go to the app's external files folder:
//   adb pull /sdcard/Android/data/com.capsuleutkarsh.gleo/files/shots
import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media_kit/media_kit.dart' hide Track;
import 'package:gleo/audio/engine.dart' show StopAfter;
import 'package:gleo/audio/sound.dart';
import 'package:gleo/main.dart';
import 'package:gleo/platform/android.dart';
import 'package:gleo/ui/app.dart';
import 'package:gleo/ui/lyrics_view.dart';
import 'package:gleo/ui/theme.dart';
import 'package:gleo/ui/tracks.dart' show selection;
import 'package:gleo/ui/widgets.dart' show fmtTime;
import 'package:path_provider/path_provider.dart';

const music = '$androidMusic/GleoTest';

Future<void> waitFor(bool Function() ok, {Duration timeout = const Duration(seconds: 30), String what = ''}) async {
  final sw = Stopwatch()..start();
  while (!ok()) {
    if (sw.elapsed > timeout) throw TimeoutException('waiting for $what');
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
}

/// The length the sleep picker shows, in minutes ("2 h 1 min" → 121).
int engineMinutes(WidgetTester tester) {
  final t = tester.widget<Text>(find.byKey(const ValueKey('sleep.length'))).data!;
  final h = RegExp(r'(\d+) h').firstMatch(t), m = RegExp(r'(\d+) min').firstMatch(t);
  return int.parse(h?.group(1) ?? '0') * 60 + int.parse(m?.group(1) ?? '0');
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
    // A first start scans the whole Music folder first (other test folders too): wait for the rescan of this one.
    await waitFor(
      () => lib.scan.value == null && lib.tracks.every((t) => t.path.startsWith(music)),
      timeout: const Duration(minutes: 3),
      what: 'scan end',
    );
    final deep = lib.albums.firstWhere((a) => a.title == 'Deep Water');
    final northern = lib.albums.firstWhere((a) => a.title.startsWith('Northern Lights'));
    final etude = lib.tracks.firstWhere((t) => t.title == 'Etude in Glass');
    say('Scanned ${lib.tracks.length} songs in ${lib.albums.length} albums (${lib.lastScan})');
    say('folder.jpg cover (Northern Lights): ${northern.cover != null}; embedded cover (Etude): ${etude.cover != null}; '
        '.lrc lyrics beside Etude: ${lyricsFor(etude) != null}');
    final names = {for (final t in lib.tracks) t.path.split('/').last};
    say('Not in the library: ${[for (final f in Directory(music).listSync(recursive: true).whereType<File>()) if (!names.contains(f.path.split('/').last)) f.path.split('/').last]}');
    expect(deep.tracks.length, 8);
    expect(lib.tracks.length, greaterThanOrEqualTo(29)); // testlib alone; more with real_music
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

    // The 0.4 platform calls reach MainActivity / GleoWidget (none may be missing on the device).
    const android = MethodChannel('gleo/android');
    for (final (m, arg) in [('keepOn', true), ('keepOn', false), ('lockAllowed', false), ('askNotifications', null)]) {
      await android.invokeMethod(m, arg);
    }
    await const MethodChannel('gleo/widget').invokeMethod('update', {'title': 'T', 'artist': 'A', 'art': '', 'playing': true});
    say('Keep screen on, lock-screen gate, notification ask and widget update: ok');

    // The Sound page on Gleo's own Android libmpv: every filter and soxr run, the song keeps playing,
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
    final moon = find.text('Sleep'); // the button under the controls
    await tester.tap(moon);
    await shot('dark_sleep_sheet');
    await tester.tap(find.text('15 minutes'));
    await settle();
    expect(engine.sleepAt, isNotNull);
    expect(find.textContaining('Pauses at'), findsWidgets);
    expect(find.textContaining('min left'), findsWidgets);
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
    // Custom…: any length (the slider, then a minute more), remembered; then Bedtime with that length.
    await tester.tap(moon);
    await settle();
    await tester.tap(find.text('Custom…'));
    await settle();
    final slider = tester.getRect(find.byKey(const ValueKey('sleep.slider')));
    await tester.tapAt(Offset(slider.left + slider.width / 2, slider.center.dy)); // about 2 hours
    await settle();
    await tester.tap(find.byKey(const ValueKey('sleep.more')));
    await settle();
    final picked = engineMinutes(tester);
    await shot('dark_sleep_custom');
    await tester.tap(find.byKey(const ValueKey('sleep.start')));
    await settle();
    final left = engine.sleepAt!.difference(DateTime.now()).inMinutes;
    expect(left, inInclusiveRange(picked - 1, picked));
    expect(lib.setting('sleepCustom'), '$picked');
    expect(find.byKey(const ValueKey('sleep.line')), findsOneWidget);
    await shot('dark_sleep_custom_on');
    await tester.tap(moon);
    await settle();
    await tester.tap(find.textContaining('Bedtime · '));
    await settle();
    expect(engine.bedtime, isTrue);
    expect(find.textContaining('Bedtime: pauses at'), findsOneWidget);
    await shot('dark_bedtime_on');
    await tester.tap(moon);
    await settle();
    await tester.tap(find.text('Turn off'));
    await settle();
    expect((engine.sleepAt, engine.bedtime), (null, false));
    say('Custom sleep timer: $picked min set from the sheet and remembered; Bedtime on and off');
    nav.setNowPlaying(false);
    engine.sleepIn(const Duration(seconds: 3));
    await waitFor(() => !engine.playing && engine.sleepAt == null, timeout: const Duration(seconds: 10), what: 'sleep timer pause');
    expect(engine.sleepAt, isNull);
    say('Sleep timer: the sheet sets 15 minutes, End of this song and Turn off; a 3 s timer paused the music');
    await engine.play();

    for (final theme in ['dark', 'light']) {
      setAppearance(theme);
      await settle();
      for (final page in ['home', 'albums', 'artists', 'songs', 'library', 'genres', 'playlists', 'folders', 'favourites', 'sound', 'settings']) {
        nav.go(page);
        await shot('${theme}_$page');
      }
      nav.push('album', deep.key);
      await shot('${theme}_album');
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

    // ---- The phone UI round (0.4): search, tabs, sheets, the EQ under a swipe, Back in folders.
    final pop = tester.binding.handlePopRoute; // Android's Back
    setAppearance('dark');
    nav.go('home');
    await settle();

    // Search opens as a full screen (it was a grey error screen), finds a song, and a tap plays it.
    nav.setSearch(true);
    await settle();
    await tester.enterText(find.byType(TextField), 'Etude');
    await shot('dark_search');
    await tester.tap(find.textContaining('Etude in Glass  Song')); // the result row: title and kind
    await settle();
    expect(nav.search, isFalse);
    await waitFor(() => engine.current?.id == etude.id, what: 'search plays the song');
    nav.setSearch(true);
    await settle();
    expect(await pop(), isTrue);
    expect(nav.search, isFalse, reason: 'Back closes search');
    say('Search: opens, finds "Etude in Glass", a tap plays it, Back closes it');

    // Five tabs, Library's rows, the Settings gear; Back from a Library page returns to Library.
    for (final (key, page) in [('home', 'home'), ('songs', 'songs'), ('albums', 'albums'), ('artists', 'artists'), ('library', 'library')]) {
      await tester.tap(find.byKey(ValueKey('nav.$key')));
      await settle(400);
      expect(nav.top.page, page);
    }
    await tester.tap(find.byKey(const ValueKey('library.playlists')));
    await settle(400);
    expect((nav.top.page, nav.canBack), ('playlists', true));
    expect(await pop(), isTrue);
    expect(nav.top.page, 'library');
    await tester.tap(find.byKey(const ValueKey('nav.settings')));
    await settle(400);
    expect(nav.top.page, 'settings');
    say('Tabs: Home, Songs, Albums, Artists, Library; Library → Playlists → Back; Settings from the top bar');

    // A long press on a song opens a bottom sheet (not the desktop pop-up), with the song on top.
    nav.go('songs');
    await settle();
    await tester.longPress(find.text(lib.tracks.reduce((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()) <= 0 ? a : b).title).first);
    await settle();
    expect(find.text('Play next'), findsOneWidget);
    expect(find.byType(BottomSheet), findsOneWidget);
    await shot('dark_song_sheet');
    expect(await pop(), isTrue);
    await settle();
    expect(selection.length, 0, reason: 'the row is not left selected after its menu');

    // Now Playing's ⋮: everything for the song in one sheet.
    nav.setNowPlaying(true);
    await settle();
    await tester.tap(find.byKey(const ValueKey('np.more')));
    await settle();
    for (final s in ['Add to playlist…', 'Go to album', 'Go to artist', 'Change cover…', 'Sound', 'Disc mode']) {
      expect(find.text(s), findsOneWidget, reason: s);
    }
    await shot('dark_np_more');
    await pop();
    await settle();
    nav.setNowPlaying(false);

    // A swipe that starts on the EQ (off the thumbs) scrolls the page and changes nothing.
    nav.go('home');
    nav.push('sound', '');
    await settle();
    final eqBefore = (sound.s.eq.on, [...sound.s.eq.graphic]);
    await tester.ensureVisible(find.byType(RotatedBox).at(5));
    await settle();
    final band = tester.getRect(find.byType(RotatedBox).at(5)); // a band's slider, its thumb in the middle at 0 dB
    final list = find.ancestor(of: find.byType(RotatedBox).at(5), matching: find.byType(Scrollable)).first;
    final before = tester.state<ScrollableState>(list).position.pixels;
    await tester.dragFrom(band.center + Offset(0, band.height * 0.35), const Offset(0, -300));
    await settle();
    expect(sound.s.eq.on, eqBefore.$1, reason: 'the EQ must not switch on');
    expect(sound.s.eq.graphic, eqBefore.$2, reason: 'the bands must not change');
    expect(tester.state<ScrollableState>(list).position.pixels, greaterThan(before), reason: 'the page scrolls');
    await shot('dark_sound_after_swipe');
    say('EQ: a swipe over the bands scrolled the page; the EQ stayed ${eqBefore.$1 ? 'on' : 'off'} and flat');

    // Folders: each level is a page, so Back goes up one level, then back to Library (the app stays open).
    nav.go('library');
    nav.push('folders', '');
    await settle();
    await tester.tap(find.textContaining('GleoTest').first);
    await settle(400);
    await tester.tap(find.text('testlib'));
    await settle(400);
    await tester.tap(find.text('The Tidal Set'));
    await settle(400);
    expect(nav.top.page, 'folder');
    await shot('dark_folder_deep');
    expect(await pop(), isTrue);
    expect(nav.top.arg, endsWith('testlib'));
    expect(await pop(), isTrue);
    expect(nav.top.arg, music);
    expect(await pop(), isTrue);
    expect(nav.top.page, 'folders');
    expect(await pop(), isTrue);
    expect(nav.top.page, 'library');
    say('Folders: Back went The Tidal Set → testlib → GleoTest → Folders → Library');

    // Text over bright covers: the artist line, the times and the title at 4.5:1 or more, in dark and light.
    final contrastAlbums = lib.albums.where((a) => ['White Cover', 'Cyan Cover', 'Yellow Cover'].contains(a.title)).toList();
    Future<double> contrastOf(Finder f) async {
      final ratio = tester.view.devicePixelRatio;
      final boundary = shotKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: ratio);
      final px = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
      final r = tester.getRect(f);
      final lum = <double>[];
      for (var y = (r.top * ratio).ceil(); y < (r.bottom * ratio).floor(); y++) {
        for (var x = (r.left * ratio).ceil(); x < (r.right * ratio).floor(); x++) {
          final i = (y * image.width + x) * 4;
          lum.add(Color.fromARGB(255, px.getUint8(i), px.getUint8(i + 1), px.getUint8(i + 2)).computeLuminance());
        }
      }
      image.dispose();
      lum.sort();
      // The background is most of the box; the text is the pixel furthest from it.
      final bg = lum[lum.length ~/ 2];
      final fg = (lum.last - bg).abs() > (bg - lum.first).abs() ? lum.last : lum.first;
      return (max(fg, bg) + 0.05) / (min(fg, bg) + 0.05);
    }

    for (final theme in ['dark', 'light']) {
      setAppearance(theme);
      for (final a in contrastAlbums) {
        await engine.playTracks(a.tracks);
        nav.setNowPlaying(true);
        await settle(2500); // the glow is drawn after the cover is read
        final name = '${theme}_np_${a.title.split(' ').first.toLowerCase()}';
        final artist = await contrastOf(find.byKey(const ValueKey('np.artist')));
        final title = await contrastOf(find.text(a.tracks.first.title).last); // (the mini player under it has it too)
        final time = await contrastOf(find.text(fmtTime(engine.duration)).last);
        await shot(name);
        say('Contrast $name (${C.isLight ? 'light' : 'dark'}): artist line ${artist.toStringAsFixed(2)}, '
            'title ${title.toStringAsFixed(2)}, time ${time.toStringAsFixed(2)}');
        for (final (what, c) in [('artist', artist), ('title', title), ('time', time)]) {
          expect(c, greaterThanOrEqualTo(4.5), reason: '$name $what');
        }
        nav.setNowPlaying(false);
      }
    }
    if (contrastAlbums.isEmpty) say('Contrast: no White / Cyan / Yellow albums pushed, skipped');
    setAppearance('dark');
    await engine.playTracks(deep.tracks);
    await settle();

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
