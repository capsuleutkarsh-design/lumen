// Checks Gleo's own libmpv.so on Android (an emulator or phone): a FLAC plays through each audio
// output with the Sound page's filters (EQ + bs2b crossfeed) and soxr resampling, with no mpv error.
// Prints one GLEO_CHECK line per output to logcat. Run:
//   flutter build apk --debug -t tool/android_engine_check.dart
//   adb install -r build/app/outputs/flutter-apk/app-debug.apk
//   adb shell "cat /sdcard/Music/GleoTest/test.flac | run-as com.capsuleutkarsh.gleo sh -c 'cat > files/test.flac'"
//   adb shell am start -n com.capsuleutkarsh.gleo/.MainActivity; adb logcat -s flutter
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:media_kit/media_kit.dart';
import 'package:path_provider/path_provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  final flac = '${(await getApplicationSupportDirectory()).path}/test.flac';
  for (final ao in ['audiotrack', 'aaudio', 'opensles']) {
    final player = Player(configuration: const PlayerConfiguration(logLevel: MPVLogLevel.warn));
    final mpv = player.platform as NativePlayer;
    final logs = <String>[];
    player.stream.log.listen((l) => logs.add('${l.level} ${l.prefix}: ${l.text.trim()}'));
    await mpv.setProperty('ao', ao);
    await mpv.setProperty('cache-on-disk', 'no'); // media_kit's default has no cache dir on Android
    await player.setVolume(0);
    await mpv.setProperty('audio-samplerate', '96000'); // makes mpv resample, through soxr:
    await mpv.setProperty('audio-swresample-o', 'resampler=soxr,precision=28,dither_method=triangular');
    await mpv.setProperty('af', 'lavfi=[equalizer=f=1000:width_type=o:width=1:g=-3],lavfi=[bs2b=profile=cmoy]');
    await player.open(Media(flac));
    Future<double> pos() async => double.tryParse(await mpv.getProperty('time-pos')) ?? -1;
    final sw = Stopwatch()..start();
    while (await pos() < 1.5 && sw.elapsed < const Duration(seconds: 10)) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    final current = await mpv.getProperty('current-ao');
    final rate = await mpv.getProperty('audio-out-params/samplerate');
    // media_kit sets `osc`, a Lua script option; the engine has no Lua, so that one error is expected.
    final errors = logs.where((l) => (l.startsWith('error') || l.startsWith('fatal')) && !l.contains('(osc,'));
    // AudioTrack may open the track at the source rate instead of 96 kHz, so the rate is only reported.
    final ok = await pos() >= 1.5 && current == ao && errors.isEmpty;
    debugPrint('GLEO_CHECK ao=$ao ${ok ? 'PASS' : 'FAIL'} rate=$rate pos=${await pos()} current-ao=$current '
        'out=${await mpv.getProperty('audio-out-params')} af=${await mpv.getProperty('af')} logs=$logs');
    await player.dispose();
  }
  final p = Player();
  final mpv = p.platform as NativePlayer;
  debugPrint('GLEO_CHECK version ${await mpv.getProperty('mpv-version')} '
      'FFmpeg ${await mpv.getProperty('ffmpeg-version')}');
  await p.dispose();
  debugPrint('GLEO_CHECK done');
  exit(0);
}
