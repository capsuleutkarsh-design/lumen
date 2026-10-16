// Checks Gleo's own audio engine (libmpv-2.dll from github.com/capsuleutkarsh-design/lumen-audio-engine):
// the "best sound" filters and the soxr resampler load and process audio.
// Needs `flutter build windows --release` first (skipped otherwise). Silent: ao=null and volume 0.
@Tags(['mpv']) // run one file at a time: see dart_test.yaml
library;

import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:gleo/audio/engine.dart';

const dll = r'build\windows\x64\runner\Release\libmpv-2.dll';

/// A 3 s 44.1 kHz stereo 16-bit sine as a WAV file.
File sineWav(String path) {
  const rate = 44100, frames = rate * 3;
  final b = ByteData(44 + frames * 4);
  void s(int o, String t) => t.codeUnits.asMap().forEach((i, c) => b.setUint8(o + i, c));
  s(0, 'RIFF'); b.setUint32(4, 36 + frames * 4, Endian.little); s(8, 'WAVEfmt ');
  b..setUint32(16, 16, Endian.little)..setUint16(20, 1, Endian.little)..setUint16(22, 2, Endian.little)
   ..setUint32(24, rate, Endian.little)..setUint32(28, rate * 4, Endian.little)
   ..setUint16(32, 4, Endian.little)..setUint16(34, 16, Endian.little);
  s(36, 'data'); b.setUint32(40, frames * 4, Endian.little);
  for (var i = 0; i < frames; i++) {
    final v = (8000 * sin(2 * pi * 440 * i / rate)).round();
    b..setInt16(44 + i * 4, v, Endian.little)..setInt16(46 + i * 4, v, Endian.little);
  }
  return File(path)..writeAsBytesSync(b.buffer.asUint8List());
}

void main() {
  test('our engine: filters, bs2b and soxr work', () async {
    initMediaKit(libmpv: File(dll).absolute.path);
    final wav = sineWav('${Directory.systemTemp.createTempSync('gleo_engine').path}\\sine.wav');
    final player = Player(configuration: const PlayerConfiguration(logLevel: MPVLogLevel.warn));
    final mpv = player.platform as NativePlayer;
    final errors = <String>[];
    player.stream.log.listen((l) => errors.add('${l.prefix}: ${l.text}'));
    await mpv.setProperty('ao', 'null');
    await player.setVolume(0);
    await mpv.setProperty('audio-samplerate', '96000'); // makes mpv resample, through soxr:
    await mpv.setProperty('audio-swresample-o', 'resampler=soxr,precision=28');
    await player.open(Media(wav.path));

    Future<double> pos() async => double.tryParse(await mpv.getProperty('time-pos')) ?? -1;
    Future<void> plays() async {
      final start = await pos();
      final sw = Stopwatch()..start();
      while (await pos() < start + 0.2) {
        if (sw.elapsed > const Duration(seconds: 5)) fail('no playback after ${errors.join('\n')}');
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    }

    await plays();
    for (final af in [
      'lavfi=[equalizer=f=1000:width_type=o:width=1:g=-3]',
      'lavfi=[lowshelf=f=100:g=3,highshelf=f=8000:g=-2]',
      'lavfi=[crossfeed]',
      'lavfi=[bs2b=profile=cmoy]',
      'lavfi=[alimiter=limit=0.9]',
      'lavfi=[aresample=resampler=soxr:precision=28:osr=96000]',
      'lavfi=[firequalizer=gain_entry=\'entry(1000,-3)\']',
      '@m:lavfi=[ebur128=metadata=1]',
    ]) {
      errors.clear();
      await player.seek(Duration.zero);
      await mpv.setProperty('af', af);
      await plays();
      expect(errors, isEmpty, reason: af);
      expect(await mpv.getProperty('af'), isNotEmpty, reason: '$af was refused');
    }
    // The last filter really processed the audio: it measured its loudness.
    expect(await mpv.getProperty('af-metadata/m'), contains('lavfi.r128.M'));
    expect(await mpv.getProperty('audio-out-params/samplerate'), '96000');
    await player.dispose();
  }, skip: File(dll).existsSync() ? false : 'build the release first', timeout: const Timeout(Duration(minutes: 2)));
}
