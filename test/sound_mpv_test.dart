// The Sound settings against Gleo's real engine (libmpv-2.dll) on mpv's null output:
// nothing is ever audible and no device is opened, so "exclusive mode" here is simulated.
// Proves: every preset chain loads, EQ on/off keeps playing, the bit-perfect path stays
// empty, live slider changes are filter commands, and measured levels (ebur128) show the
// EQ and the limiter do what they say. Needs `flutter build windows --release` (skipped otherwise).
// Test tones: 1 kHz sines written here, or ffmpeg-made ones in MP_TONES (tone_1k_m20.wav, tone_1k_0dbfs.wav).
@Tags(['mpv']) // run one file at a time: see dart_test.yaml
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart' hide Track;
import 'package:gleo/audio/engine.dart';
import 'package:gleo/audio/sound.dart';
import 'package:gleo/audio/sound_control.dart';
import 'package:gleo/library/library.dart';
import 'package:gleo/library/models.dart';
import 'package:path/path.dart' as p;

final dll = p.join(Directory.current.path, 'build', 'windows', 'x64', 'runner', 'Release', 'libmpv-2.dll');

/// A 1 kHz stereo sine, 32-bit float WAV at 48 kHz.
void toneWav(String path, double amp, {int secs = 30}) {
  const rate = 48000;
  final frames = rate * secs;
  final b = ByteData(44 + frames * 8);
  void s(int o, String t) => t.codeUnits.asMap().forEach((i, c) => b.setUint8(o + i, c));
  s(0, 'RIFF');
  b.setUint32(4, 36 + frames * 8, Endian.little);
  s(8, 'WAVEfmt ');
  b
    ..setUint32(16, 16, Endian.little)
    ..setUint16(20, 3, Endian.little) // IEEE float
    ..setUint16(22, 2, Endian.little)
    ..setUint32(24, rate, Endian.little)
    ..setUint32(28, rate * 8, Endian.little)
    ..setUint16(32, 8, Endian.little)
    ..setUint16(34, 32, Endian.little);
  s(36, 'data');
  b.setUint32(40, frames * 8, Endian.little);
  for (var i = 0; i < frames; i++) {
    final v = amp * sin(2 * pi * 1000 * i / rate);
    b
      ..setFloat32(44 + i * 8, v, Endian.little)
      ..setFloat32(48 + i * 8, v, Endian.little);
  }
  File(path).writeAsBytesSync(b.buffer.asUint8List());
}

/// Every chain it builds ends in a loudness meter (labelled with the chain, so commands still reach the EQ).
class MeteredEngine extends Engine {
  MeteredEngine(super.lib) : super(silent: true, logLevel: MPVLogLevel.warn);
  @override
  Future<void> setAudioFilters(String chain) => super.setAudioFilters(chain.isEmpty ? '' : '$chain,ebur128=metadata=1:peak=sample');
}

late Library lib;
late Track quiet, loud;
final _open = <Engine>[];
final _sounds = <Sound>[];

Future<void> wait(int ms) => Future<void>.delayed(Duration(milliseconds: ms));

Future<(Engine, Sound, List<String>)> start(Track t, SoundSettings s) async {
  lib.setSetting('sound', jsonEncode(s.toJson()));
  lib.setSetting('volume', '0');
  final e = MeteredEngine(lib);
  final problems = <String>[];
  await e.init();
  _open.add(e);
  expect(await e.getOption('ao'), 'null', reason: 'never a real device');
  e.player.stream.log.listen((l) {
    if (l.text.toLowerCase().contains('filter')) problems.add('${l.prefix}: ${l.text}');
  });
  e.messages.listen(problems.add);
  final snd = Sound(lib, e);
  _sounds.add(snd);
  await snd.init();
  await e.playTracks([t]);
  await playing(e);
  return (e, snd, problems);
}

Future<void> playing(Engine e) async {
  final sw = Stopwatch()..start();
  while (!(e.playing && e.position.value > const Duration(milliseconds: 300))) {
    if (sw.elapsed > const Duration(seconds: 10)) fail('not playing');
    await wait(20);
  }
}

/// Lets a change apply (debounce + mpv), then the meter settle.
Future<void> settle(Sound snd, [int ms = 1200]) async {
  await wait(80);
  await snd.apply();
  await wait(ms);
}

/// (momentary loudness in LUFS, sample peak as a ratio) from the meter at the end of the chain.
Future<(double, double)> meter(Engine e) async {
  final j = jsonDecode(await e.getOption('af-metadata/gleo')) as Map<String, Object?>;
  return (double.parse(j['lavfi.r128.M']! as String), double.parse(j['lavfi.r128.sample_peak']! as String));
}

void main() {
  final skip = File(dll).existsSync() ? null : 'build the release first';
  setUpAll(() async {
    if (skip != null) return;
    initMediaKit(libmpv: dll);
    final data = Directory.systemTemp.createTempSync('gleo_sound_');
    final tones = Directory(p.join(data.path, 'tones'))..createSync();
    final given = Platform.environment['MP_TONES'];
    for (final (name, amp) in [('tone_1k_m20.wav', 0.1), ('tone_1k_0dbfs.wav', 1.0)]) {
      final from = given == null ? null : File(p.join(given, name));
      from != null && from.existsSync() ? from.copySync(p.join(tones.path, name)) : toneWav(p.join(tones.path, name), amp);
    }
    lib = Library(data.path)..load();
    lib.setSetting('folders', jsonEncode([tones.path]));
    await lib.rescan();
    quiet = lib.tracks.firstWhere((t) => t.path.endsWith('m20.wav'));
    loud = lib.tracks.firstWhere((t) => t.path.endsWith('0dbfs.wav'));
  });
  tearDown(() async {
    for (final s in _sounds) {
      s.dispose();
    }
    _sounds.clear();
    for (final e in _open) {
      await e.shutdown();
    }
    _open.clear();
  });

  test('every preset, the AutoEQ import, crossfeed, levelling and Late night load with no mpv error and keep playing', () async {
    final (e, snd, problems) = await start(quiet, SoundSettings());
    final autoEq = File('test/fixtures/autoeq_ParametricEQ.txt').readAsStringSync();
    final setups = <String, void Function(SoundSettings)>{
      for (final p in builtInPresets) p.name: (s) => s.eq = p.copy(),
      'AutoEQ': (s) => s.eq = parseEqText(autoEq).$1,
      'GraphicEQ': (s) => s.eq = parseEqText(File('test/fixtures/autoeq_GraphicEQ.txt').readAsStringSync()).$1,
      for (final c in Crossfeed.values) 'crossfeed ${c.name}': (s) => s.crossfeed = c,
      'every band type': (s) => s.eq = Eq(on: true, advanced: true, bands: [
        Band(BandType.highPass, 40, 0, 0.71),
        Band(BandType.lowShelf, 120, 4, 0.71),
        Band(BandType.peak, 900, -3, 2.5),
        Band(BandType.peak, 3200, 2.5, 1.2),
        Band(BandType.notch, 6000, 0, 8),
        Band(BandType.highShelf, 11000, -2, 0.71),
        Band(BandType.lowPass, 19000, 0, 0.71),
      ]),
      'levelling': (s) => s.levelling = true,
      'Best quality off': (s) => s.bestQuality = false,
    };
    for (final MapEntry(key: name, value: setup) in setups.entries) {
      snd.change(setup);
      await settle(snd, 300);
      final before = e.position.value;
      await wait(300);
      expect(problems, isEmpty, reason: name);
      expect(await e.getOption('af'), contains('gleo'), reason: name);
      expect(e.playing, isTrue, reason: name);
      expect(e.position.value, greaterThan(before), reason: '$name: still playing');
    }
  }, skip: skip, timeout: const Timeout(Duration(minutes: 3)));

  test('EQ on / off never stops playback', () async {
    final (e, snd, problems) = await start(quiet, SoundSettings()..eq = builtInPresets[5].copy());
    var last = e.position.value;
    for (var i = 0; i < 6; i++) {
      snd.change((s) => s.eq.on = !s.eq.on);
      await settle(snd, 400);
      expect(await e.getOption('af'), snd.s.eq.on ? contains('equalizer') : '');
      expect(e.playing, isTrue);
      expect(e.position.value, greaterThan(last));
      last = e.position.value;
    }
    expect(problems, isEmpty);
  }, skip: skip, timeout: const Timeout(Duration(minutes: 2)));

  test('bit-perfect path: everything off + exclusive (simulated) leaves the chain EMPTY and the badge verified', () async {
    final (e, snd, problems) = await start(quiet, SoundSettings()); // Best quality on, EQ off
    await e.setVolume(100); // the null output: still silent
    await e.setExclusive(true);
    await playing(e);
    await settle(snd, 600);
    expect(snd.chain, '');
    expect(await e.getOption('af'), '');
    expect(await e.getOption('replaygain'), 'no');
    expect(await e.getOption('audio-samplerate'), '0');
    expect('${e.outFormat} ${e.outRate}', '${e.srcFormat} ${e.srcRate}');
    expect(snd.path.why, isEmpty, reason: '${snd.path.why}');
    expect(snd.summary, startsWith('Bit-perfect ✓'));
    // Anything that changes the sound takes the badge away, and says why.
    snd.change((s) => s.eq = builtInPresets[1].copy());
    await settle(snd, 400);
    expect(snd.path.why, contains('EQ is on'));
    await e.setVolume(50);
    expect(snd.path.why, contains('volume is 50 %, not 100 %'));
    await e.setExclusive(false);
    expect(problems, isEmpty);
  }, skip: skip, timeout: const Timeout(Duration(minutes: 2)));

  test('measured: a +6 dB peak at 1 kHz raises a 1 kHz tone by 6 dB, sent live as a filter command', () async {
    final (e, snd, problems) = await start(quiet, SoundSettings()
      ..bestQuality = false // no automatic headroom: the boost is what we measure
      ..eq = Eq(on: true));
    await settle(snd);
    final (flat, _) = await meter(e);
    expect(flat, closeTo(-20, 0.3), reason: 'a -20 dBFS 1 kHz sine');
    final rebuiltAf = await e.getOption('af');
    snd.change((s) => s.eq.graphic[5] = 6); // the 1 kHz slider
    await settle(snd);
    final (boosted, _) = await meter(e);
    debugPrint('measured: flat ${flat.toStringAsFixed(2)} LUFS, +6 dB at 1 kHz ${boosted.toStringAsFixed(2)} LUFS (+${(boosted - flat).toStringAsFixed(2)} dB)');
    expect(boosted - flat, closeTo(6, 0.3));
    expect(await e.getOption('af'), rebuiltAf, reason: 'a command, not a rebuild: no gap');
    snd.change((s) => s.eq.graphic[5] = -9);
    await settle(snd);
    final cut = (await meter(e)).$1;
    debugPrint('measured: -9 dB at 1 kHz ${(cut - flat).toStringAsFixed(2)} dB');
    expect(cut - flat, closeTo(-9, 0.3));
    // Best quality on: automatic headroom takes the boost back off, so the tone stays at -20.
    snd.change((s) {
      s.eq.graphic[5] = 6;
      s.bestQuality = true;
    });
    await settle(snd);
    expect((await meter(e)).$1, closeTo(flat, 0.3));
    expect(problems, isEmpty);
  }, skip: skip, timeout: const Timeout(Duration(minutes: 2)));

  test('measured: the limiter keeps a +12 dB boosted full-scale tone under 0 dBFS', () async {
    final boost = Eq(on: true, graphic: [0, 0, 0, 0, 0, 12, 0, 0, 0, 0]);
    final (e, snd, problems) = await start(loud, SoundSettings()
      ..bestQuality = false
      ..eq = boost);
    await settle(snd);
    final (_, raw) = await meter(e);
    expect(raw, greaterThan(3.5), reason: 'without the limiter the peak is about 4 (+12 dB)');
    snd.change((s) => s.eq.limit = true); // the limiter alone (no headroom)
    await settle(snd);
    final (_, limited) = await meter(e);
    debugPrint('measured: +12 dB on a full-scale tone: peak ${raw.toStringAsFixed(3)} without the limiter, ${limited.toStringAsFixed(3)} with it');
    expect(limited, lessThan(0.975), reason: 'the limit is -0.3 dBFS = 0.966');
    expect(limited, greaterThan(0.9));
    snd.change((s) => s
      ..eq.limit = false
      ..bestQuality = true); // headroom + limiter
    await settle(snd);
    final both = (await meter(e)).$2;
    debugPrint('measured: with Best quality (headroom + limiter) peak ${both.toStringAsFixed(3)}');
    expect(both, lessThan(0.975));
    expect(problems, isEmpty);
  }, skip: skip, timeout: const Timeout(Duration(minutes: 2)));

  test('upsampling with soxr to 2x / 4x in exclusive mode (simulated on the null output)', () async {
    final (e, snd, problems) = await start(quiet, SoundSettings());
    await e.setExclusive(true);
    for (final (u, rate) in [(Upsample.x2, '96000'), (Upsample.x4, '192000'), (Upsample.off, '48000')]) {
      snd.change((s) => s.upsample = u);
      await settle(snd, 600);
      await playing(e);
      expect(await e.getOption('audio-out-params/samplerate'), rate, reason: u.name);
    }
    expect(await e.getOption('audio-swresample-o'), contains('resampler=soxr'));
    await e.setExclusive(false);
    expect(problems, isEmpty);
  }, skip: skip, timeout: const Timeout(Duration(minutes: 2)));

  test('per-device EQ: switches with the output device and says so', () async {
    final rock = builtInPresets.firstWhere((p) => p.name == 'Rock');
    final (e, snd, _) = await start(quiet, SoundSettings()..eq = rock.copy());
    final said = <String>[];
    e.messages.listen(said.add);
    snd.change((s) => s.perDevice = true);
    await e.setDevice('wasapi/{gleo-test-device}');
    await wait(100);
    expect(snd.s.eq.name, 'Rock', reason: 'a new device keeps the current EQ');
    snd.change((s) => s.eq = builtInPresets[1].copy()); // Bass boost, remembered for this device
    await e.setDevice('auto');
    await wait(100);
    expect(snd.s.eq.name, 'Rock');
    expect(said, contains('Using “Rock” EQ for System default'));
    await e.setDevice('wasapi/{gleo-test-device}');
    await wait(100);
    expect(snd.s.eq.name, 'Bass boost');
    await e.setDevice('auto');
  }, skip: skip, timeout: const Timeout(Duration(minutes: 2)));

  test('saved in the settings table and applied on start', () async {
    final (e, snd, _) = await start(quiet, SoundSettings());
    snd.change((s) => s
      ..eq = builtInPresets[3].copy()
      ..crossfeed = Crossfeed.medium
      ..replayGain = ReplayGain.album);
    await settle(snd, 100);
    snd.save();
    final chain = snd.chain;
    snd.dispose();
    _sounds.remove(snd);
    await e.shutdown();
    _open.remove(e);
    final (e2, snd2, _) = await start(quiet, SoundSettings.parse(lib.setting('sound')));
    expect(snd2.chain, chain);
    expect(await e2.getOption('af'), contains('bs2b'));
    expect(await e2.getOption('replaygain'), 'album');
  }, skip: skip, timeout: const Timeout(Duration(minutes: 2)));
}
