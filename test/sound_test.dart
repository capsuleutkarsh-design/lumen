// The Sound page's pure parts: biquad maths, headroom, the filter chain, live
// commands, the signal path / bit-perfect check, the importers and presets.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:music_player/audio/sound.dart';

const fs = 48000.0;

SoundSettings eqOn(List<double> g, {bool best = true}) => SoundSettings()
  ..bestQuality = best
  ..eq = Eq(on: true, graphic: g);

const playing = SourceInfo(badge: 'FLAC 16/44.1', format: 's16', rate: 44100, bits: 16, channels: 2);

/// A ParametricEQ.txt in AutoEQ's exact layout (values made up for the test).
final autoEq = File('test/fixtures/autoeq_ParametricEQ.txt').readAsStringSync();

void main() {
  group('biquad maths (same formulas as FFmpeg)', () {
    test('a +6 dB peak gives +6 dB at fc and nothing far away', () {
      final b = Band(BandType.peak, 1000, 6, 1.41);
      expect(bandDb(b, 1000, fs), closeTo(6, 0.01));
      expect(bandDb(b, 20, fs), closeTo(0, 0.05));
      expect(bandDb(b, 18000, fs), closeTo(0, 0.1));
      expect(bandDb(Band(BandType.peak, 1000, -9, 2), 1000, fs), closeTo(-9, 0.01));
    });
    test('shelves: full gain far out, half the gain (in dB) at fc', () {
      expect(bandDb(Band(BandType.lowShelf, 200, 6, 0.71), 20, fs), closeTo(6, 0.1));
      expect(bandDb(Band(BandType.lowShelf, 200, 6, 0.71), 200, fs), closeTo(3, 0.05));
      expect(bandDb(Band(BandType.lowShelf, 200, 6, 0.71), 10000, fs), closeTo(0, 0.05));
      expect(bandDb(Band(BandType.highShelf, 5000, -4, 0.71), 20000, fs), closeTo(-4, 0.2));
      expect(bandDb(Band(BandType.highShelf, 5000, -4, 0.71), 5000, fs), closeTo(-2, 0.05));
    });
    test('high-pass / low-pass are -3 dB at fc with Q 0.707, notch removes fc', () {
      expect(bandDb(Band(BandType.highPass, 100, 0, 0.7071), 100, fs), closeTo(-3.01, 0.02));
      expect(bandDb(Band(BandType.highPass, 100, 0, 0.7071), 25, fs), lessThan(-20));
      expect(bandDb(Band(BandType.highPass, 100, 0, 0.7071), 5000, fs), closeTo(0, 0.01));
      expect(bandDb(Band(BandType.lowPass, 8000, 0, 0.7071), 8000, fs), closeTo(-3.01, 0.02));
      expect(bandDb(Band(BandType.notch, 1000, 0, 2), 1000, fs), lessThan(-60));
      expect(bandDb(Band(BandType.notch, 1000, 0, 2), 100, fs), closeTo(0, 0.1));
    });
    test('the whole EQ adds preamp, bands and an imported curve', () {
      final eq = Eq(on: true, advanced: true, preamp: -2, bands: [Band(BandType.peak, 1000, 6, 1)], curve: [(500, 1), (2000, 3)]);
      expect(eqDb(eq, 1000, fs), closeTo(-2 + 6 + (1 + 2 * 500 / 1500), 0.01));
      expect(curveDb(eq.curve, 20), 1);
      expect(curveDb(eq.curve, 20000), 3);
    });
  });

  group('headroom', () {
    test('a flat or cutting EQ needs none', () {
      expect(headroomDb(Eq(on: true), fs), 0);
      expect(headroomDb(Eq(on: true, graphic: [-3, -3, 0, 0, 0, 0, 0, 0, 0, -6]), fs), 0);
      expect(headroomDb(Eq(graphic: [6, 0, 0, 0, 0, 0, 0, 0, 0, 0]), fs), 0, reason: 'EQ off');
    });
    test('equals the highest boost, including where bands overlap', () {
      expect(headroomDb(Eq(on: true, advanced: true, bands: [Band(BandType.peak, 1000, 6, 1.41)]), fs), closeTo(6, 0.01));
      final two = Eq(on: true, advanced: true, bands: [Band(BandType.peak, 1000, 6, 1), Band(BandType.peak, 1300, 6, 1)]);
      final h = headroomDb(two, fs);
      expect(h, greaterThan(9), reason: 'two overlapping +6 dB bands add up');
      for (final f in freqGrid(2000)) {
        expect(eqDb(two, f, fs), lessThanOrEqualTo(h + 0.01));
      }
    });
    test('the preamp counts: +6 dB boost with -6 dB preamp needs none', () {
      expect(headroomDb(Eq(on: true, preamp: -6, advanced: true, bands: [Band(BandType.peak, 1000, 6, 1.41)]), fs), closeTo(0, 0.01));
      expect(headroomDb(Eq(on: true, preamp: -2, advanced: true, bands: [Band(BandType.peak, 1000, 6, 1.41)]), fs), closeTo(4, 0.01));
    });
  });

  group('buildAudioChain', () {
    test('defaults: no filters (the clean path), soxr for any resampling', () {
      final c = buildAudioChain(SoundSettings(), const DeviceInfo(), playing);
      expect(c.chain, '');
      expect(c.options['audio-swresample-o'], 'resampler=soxr,precision=28,dither_method=triangular');
      expect(c.options['audio-samplerate'], '0');
      expect(c.options['replaygain'], 'no');
      expect(c.options['audio-buffer'], '0.2');
    });
    test('exclusive with everything off: empty chain and neutral options', () {
      final s = SoundSettings()..bestQuality = false;
      final c = buildAudioChain(s, const DeviceInfo(exclusive: true), playing);
      expect(c.chain, '');
      expect(c.options, {
        'audio-swresample-o': '',
        'audio-samplerate': '0',
        'audio-buffer': '0.2',
        'replaygain': 'no',
        'replaygain-preamp': '0',
        'replaygain-clip': 'yes',
        'replaygain-fallback': '0',
      });
    });
    test('graphic EQ: float, preamp with automatic headroom, all 10 bands, limiter last', () {
      final c = buildAudioChain(eqOn([0, 0, 0, 0, 0, 6, 0, 0, 0, 0]), const DeviceInfo(), playing).chain;
      final f = c.split(',');
      expect(f.first, 'aformat=sample_fmts=fltp');
      expect(f[1], 'volume@pre=volume=-6dB');
      expect(f[7], 'equalizer@b5=f=1000:t=q:w=1.41:g=6');
      expect(f.where((x) => x.startsWith('equalizer@')).length, 10, reason: 'flat bands stay, so drags are commands');
      expect(f.last, limiter);
    });
    test('Best quality off: no headroom, no limiter; a preset can still ask for the limiter', () {
      final c = buildAudioChain(eqOn([0, 0, 0, 0, 0, 6, 0, 0, 0, 0], best: false), const DeviceInfo(), playing).chain;
      expect(c, contains('volume@pre=volume=0dB'));
      expect(c, isNot(contains('alimiter')));
      final s = eqOn([0, 0, 0, 0, 0, 6, 0, 0, 0, 0], best: false)..eq.limit = true;
      expect(buildAudioChain(s, const DeviceInfo(), playing).chain, endsWith(limiter));
    });
    test('advanced bands map to the right FFmpeg filters; a band above Nyquist is left out', () {
      final s = SoundSettings()
        ..eq = Eq(
          on: true,
          advanced: true,
          bands: [
            Band(BandType.peak, 105, -2.3, 0.7),
            Band(BandType.lowShelf, 80, 3, 0.71),
            Band(BandType.highShelf, 9000, -2, 0.71),
            Band(BandType.lowPass, 18000, 0, 0.71),
            Band(BandType.highPass, 30, 0, 0.71),
            Band(BandType.notch, 60, 0, 10),
            Band(BandType.peak, 23000, 3, 1),
          ],
        );
      final c = buildAudioChain(s, const DeviceInfo(), playing).chain;
      for (final x in [
        'equalizer@b0=f=105:t=q:w=0.7:g=-2.3',
        'lowshelf@b1=f=80:t=q:w=0.71:g=3',
        'highshelf@b2=f=9000:t=q:w=0.71:g=-2',
        'lowpass@b3=f=18000:t=q:w=0.71',
        'highpass@b4=f=30:t=q:w=0.71',
      ]) {
        expect(c, contains(x));
      }
      // The notch: FFmpeg's generic biquad, with exactly the coefficients the curve is drawn from.
      final notch = c.split(',').firstWhere((x) => x.startsWith('biquad@b5='));
      final k = {for (final kv in notch.substring(10).split(':')) kv.split('=')[0]: double.parse(kv.split('=')[1])};
      expect([k['b0'], k['b1'], k['b2'], k['a0'], k['a1'], k['a2']], biquad(Band(BandType.notch, 60, 0, 10), 44100));
      expect(c, isNot(contains('@b6')), reason: '23 kHz is above Nyquist at 44.1 kHz');
      expect(buildAudioChain(s, const DeviceInfo(), const SourceInfo(rate: 96000)).chain, contains('equalizer@b6=f=23000'));
    });
    test('an imported GraphicEQ curve plays through firequalizer', () {
      final s = SoundSettings()..eq = Eq(on: true, advanced: true, curve: [(20, -1.5), (1000, 0), (20000, -3.25)]);
      expect(
        buildAudioChain(s, const DeviceInfo(), playing).chain,
        contains("firequalizer@fir=gain_entry='entry(20,-1.5);entry(1000,0);entry(20000,-3.25)'"),
      );
    });
    test('crossfeed: Light / Medium / Strong are bs2b jmeier / cmoy / default', () {
      for (final (c, p) in [(Crossfeed.light, 'jmeier'), (Crossfeed.medium, 'cmoy'), (Crossfeed.strong, 'default')]) {
        expect(buildAudioChain(SoundSettings()..crossfeed = c, const DeviceInfo(), playing).chain, contains('bs2b@xf=profile=$p'));
      }
    });
    test('levelling only for files without ReplayGain tags; Late night adds the compressor', () {
      final s = SoundSettings()..levelling = true;
      expect(buildAudioChain(s, const DeviceInfo(), playing).chain, contains('dynaudnorm@lev'));
      expect(buildAudioChain(s, const DeviceInfo(), const SourceInfo(rate: 44100, rg: (-6, 0.9, null, null))).chain, '');
      final night = SoundSettings()..eq = builtInPresets.firstWhere((p) => p.name == 'Late night').copy();
      expect(buildAudioChain(night, const DeviceInfo(), playing).chain, contains('acompressor@night'));
    });
    test('everything at once, in order', () {
      final s = SoundSettings()
        ..levelling = true
        ..crossfeed = Crossfeed.medium
        ..eq = (builtInPresets.firstWhere((p) => p.name == 'Late night').copy())
        ..replayGain = ReplayGain.auto
        ..largeBuffer = true
        ..upsample = Upsample.x4;
      final c = buildAudioChain(s, const DeviceInfo(exclusive: true), playing);
      final names = [for (final f in c.chain.split(',')) f.split('=').first];
      expect(names.first, 'aformat');
      expect(names.sublist(1, 4), ['dynaudnorm@lev', 'bs2b@xf', 'volume@pre']);
      expect(names.sublist(names.length - 2), ['acompressor@night', 'alimiter@lim']);
      expect(c.options['audio-samplerate'], '176400');
      expect(c.options['audio-buffer'], '1.0');
      expect(c.options['replaygain'], 'track');
    });
    test('upsampling: only in exclusive mode, integer multiples, never down', () {
      final s = SoundSettings()..upsample = Upsample.x2;
      expect(buildAudioChain(s, const DeviceInfo(), playing).options['audio-samplerate'], '0', reason: 'shared: Windows sets the rate');
      expect(upsampleRate(Upsample.x2, 44100), 88200);
      expect(upsampleRate(Upsample.x2, 48000), 96000);
      expect(upsampleRate(Upsample.x4, 44100), 176400);
      expect(upsampleRate(Upsample.x4, 48000), 192000);
      expect(upsampleRate(Upsample.max, 44100), 352800);
      expect(upsampleRate(Upsample.max, 96000), 384000);
      expect(upsampleRate(Upsample.x2, 96000), 0);
      expect(upsampleRate(Upsample.x4, 192000), 0);
      expect(upsampleRate(Upsample.off, 44100), 0);
    });
    test('every built-in preset builds a finite chain', () {
      for (final p in builtInPresets) {
        final c = buildAudioChain(SoundSettings()..eq = p.copy(), const DeviceInfo(), playing).chain;
        expect(c, isNot(anyOf(contains('NaN'), contains('Infinity'))), reason: p.name);
        expect(c, endsWith(limiter), reason: p.name);
      }
    });
  });

  group('ReplayGain', () {
    test('modes: Auto is album for an album in order, track when shuffled', () {
      final s = SoundSettings()..replayGain = ReplayGain.auto;
      expect(rgMode(s, const SourceInfo(albumInOrder: true)), 'album');
      expect(rgMode(s, const SourceInfo()), 'track');
      expect(rgMode(SoundSettings()..replayGain = ReplayGain.album, const SourceInfo()), 'album');
    });
    test('the gain in use: tag + preamp, lowered so the peak stays under full scale', () {
      const src = SourceInfo(rg: (-6, 0.5, -4, 0.9), albumInOrder: true);
      final s = SoundSettings()..replayGain = ReplayGain.track;
      expect(rgGainDb(s, src), -6);
      expect(rgGainDb(s..rgPreamp = 14, src), closeTo(6.02, 0.01), reason: '-6 + 14 = +8 would clip a 0.5 peak: lowered to +6.02');
      expect(rgGainDb(s..replayGain = ReplayGain.album, src), closeTo(0.92, 0.01), reason: 'album: -4 + 14, peak 0.9');
      expect(rgGainDb(s..rgClip = false, src), 10);
      expect(rgGainDb(SoundSettings()..replayGain = ReplayGain.track, const SourceInfo()), isNull, reason: 'no tags');
      expect(rgGainDb(SoundSettings(), src), isNull, reason: 'off');
    });
  });

  group('live commands (no rebuild while dragging)', () {
    test('a gain change becomes commands for the band and the preamp', () {
      final a = buildAudioChain(eqOn(List.filled(10, 0)), const DeviceInfo(), playing).chain;
      final b = buildAudioChain(eqOn([0, 0, 3, 0, 0, 0, 0, 0, 0, 0]), const DeviceInfo(), playing).chain;
      expect(liveCommands(a, b), [
        ['volume', '-3dB', 'volume@pre'],
        ['g', '3', 'equalizer@b2'],
      ]);
      expect(liveCommands(a, a), isEmpty);
    });
    test('a new filter, a type change or an empty chain needs a rebuild', () {
      final a = buildAudioChain(eqOn(List.filled(10, 0)), const DeviceInfo(), playing).chain;
      expect(liveCommands('', a), isNull);
      expect(liveCommands(a, ''), isNull);
      expect(liveCommands(a, buildAudioChain(eqOn(List.filled(10, 0))..crossfeed = Crossfeed.light, const DeviceInfo(), playing).chain), isNull);
      expect(liveCommands('equalizer@b0=f=1:t=q:w=1:g=1', 'lowshelf@b0=f=1:t=q:w=1:g=1'), isNull);
      expect(liveCommands('bs2b@xf=profile=cmoy', 'bs2b@xf=profile=jmeier'), isNull, reason: 'not a live option');
    });
    test('commas inside the firequalizer curve do not split it', () {
      const x = "aformat=sample_fmts=fltp,firequalizer@fir=gain_entry='entry(20,1);entry(30,2)',volume@pre=volume=0dB";
      expect(liveCommands(x, x.replaceFirst('volume=0dB', 'volume=-1dB')), [
        ['volume', '-1dB', 'volume@pre'],
      ]);
    });
  });

  group('signal path and bit-perfect', () {
    test('shared mode with EQ: every step, and why it is not bit-perfect', () {
      final s = eqOn([2, 2, 0, 0, 1, 0, 0, 0, 1, 1]);
      const d = DeviceInfo(name: 'Speakers (Realtek)', outFormat: 'float', outRate: 48000, outChannels: 2);
      const src = SourceInfo(badge: 'FLAC 24/96', format: 's32', rate: 96000, bits: 24, channels: 2);
      final x = signalPath(s, d, src);
      expect(x.steps, ['FLAC 24/96', 'EQ (5 bands)', 'Limiter', 'soxr', '48 kHz 32-bit float', 'Speakers (Realtek)']);
      expect(x.why, ['shared mode: Windows mixes the sound', 'EQ is on', 'resampled 96 kHz → 48 kHz', 'converted 32-bit → 32-bit float']);
    });
    test('exclusive, volume 100, nothing on, same format: bit-perfect', () {
      const d = DeviceInfo(name: 'DAC', exclusive: true, outFormat: 's16', outRate: 44100, outChannels: 2);
      final x = signalPath(SoundSettings(), d, playing);
      expect(x.why, isEmpty);
      expect(x.steps, ['FLAC 16/44.1', '44.1 kHz 16-bit', 'DAC (exclusive)']);
    });
    test('each reason on its own', () {
      const d = DeviceInfo(name: 'DAC', exclusive: true, outFormat: 's16', outRate: 44100, outChannels: 2);
      List<String> why(SoundSettings s, [DeviceInfo dev = d, SourceInfo src = playing]) => signalPath(s, dev, src).why;
      expect(why(SoundSettings(), const DeviceInfo(name: 'DAC', exclusive: true, volume: 90, outFormat: 's16', outRate: 44100)), ['volume is 90 %, not 100 %']);
      expect(why(SoundSettings(), const DeviceInfo(name: 'DAC', exclusive: true, muted: true, outFormat: 's16', outRate: 44100)), ['muted']);
      expect(why(SoundSettings()..crossfeed = Crossfeed.light), ['crossfeed is on']);
      expect(why(SoundSettings()..levelling = true), ['volume levelling is on']);
      final rg = SoundSettings()..replayGain = ReplayGain.track;
      expect(why(rg, d, const SourceInfo(badge: 'x', format: 's16', rate: 44100, bits: 16, rg: (-3.2, 0.5, null, null))), ['ReplayGain changes the level by −3.2 dB']);
      expect(why(rg), isEmpty, reason: 'ReplayGain on, but this file has no tags: nothing changes');
      expect(why(SoundSettings(), const DeviceInfo(exclusive: true)), ['nothing is playing']);
      expect(why(SoundSettings(), const DeviceInfo(exclusive: true, outFormat: 's16', outRate: 44100, outChannels: 2), const SourceInfo(format: 's16', rate: 44100, channels: 6)), [
        'channels changed 6 → 2',
      ]);
    });
    test('the same samples: equal, or padded into a wider integer format', () {
      expect(sameSamples('s16', 16, 's16'), isTrue);
      expect(sameSamples('s16p', 16, 's16'), isTrue);
      expect(sameSamples('s32', 24, 's24'), isTrue);
      expect(sameSamples('s16', 16, 's32'), isTrue);
      expect(sameSamples('s32', 32, 's24'), isFalse);
      expect(sameSamples('s32', 24, 's16'), isFalse);
      expect(sameSamples('floatp', 0, 'float'), isTrue);
      expect(sameSamples('float', 0, 's32'), isFalse);
      expect(sameSamples('s16', 16, 'float'), isFalse);
    });
    test('format names', () {
      expect(friendlyFormat('s32 96000 Hz'), '32-bit · 96 kHz');
      expect(friendlyFormat('float 44100 Hz'), '32-bit float · 44.1 kHz');
      expect(formatName('doublep'), '64-bit float');
    });
  });

  group('AutoEQ / Equalizer APO import', () {
    test('ParametricEQ.txt: preamp, shelves and peaks', () {
      final (eq, skipped) = parseEqText(autoEq);
      expect(skipped, 0);
      expect(eq.on && eq.advanced, isTrue);
      expect(eq.preamp, -6.2);
      expect(eq.bands.length, 10);
      expect([eq.bands.first.type, eq.bands.first.freq, eq.bands.first.gain, eq.bands.first.q], [BandType.lowShelf, 105, 5.5, 0.7]);
      expect([eq.bands[1].type, eq.bands[1].freq, eq.bands[1].gain, eq.bands[1].q], [BandType.peak, 179, -2.3, 0.43]);
      expect(eq.bands.last.type, BandType.highShelf);
      expect(headroomDb(eq, fs), lessThan(0.5), reason: "AutoEQ's own preamp already leaves the headroom");
    });
    test('Equalizer APO variants: OFF lines, LS/HS/LP/HP/NO, BW Oct, comments, unknown filters', () {
      final (eq, skipped) = parseEqText('''# my config
Device: Speakers
Preamp: -3 dB
Preamp: -1.5 dB
Filter 1: ON PK Fc 1000 Hz Gain 3 dB BW Oct 1.0
Filter 2: OFF PK Fc 2000 Hz Gain 9 dB Q 1
Filter 3: ON LS 12dB Fc 100 Hz Gain 2 dB
Filter 4: ON HP Fc 30 Hz
Filter 5: ON LPQ Fc 18000 Hz Q 0.5
Filter 6: ON NO Fc 50 Hz
Filter 7: ON BP Fc 300 Hz
Filter: ON HSC Fc 8000 Hz Gain -2.0 dB Q 0.71
something odd''');
      expect(eq.preamp, -4.5);
      expect([for (final b in eq.bands) b.type], [
        BandType.peak,
        BandType.lowShelf,
        BandType.highPass,
        BandType.lowPass,
        BandType.notch,
        BandType.highShelf,
      ]);
      expect(eq.bands.first.q, closeTo(1.414, 0.001), reason: 'one octave');
      expect(eq.bands[3].q, 0.5);
      expect(skipped, 2, reason: 'the band-pass line and the odd line');
    });
    test('GraphicEQ.txt (AutoEQ layout): about 127 points', () {
      final (eq, skipped) = parseEqText(File('test/fixtures/autoeq_GraphicEQ.txt').readAsStringSync());
      expect(skipped, 0);
      expect(eq.curve.length, greaterThan(100));
      expect(eq.curve.first.$1, 20);
      // FFmpeg takes about 100 entries: the chain gets 96, following the same curve.
      final c = buildAudioChain(SoundSettings()..eq = eq, const DeviceInfo(), playing).chain;
      expect('entry('.allMatches(c).length, maxPoints);
      for (final (f, g) in curvePoints(eq.curve)) {
        expect(g, closeTo(curveDb(eq.curve, f), 0.01));
      }
    });
    test('GraphicEQ: a curve, sorted', () {
      final (eq, _) = parseEqText('GraphicEQ: 20 -3.4; 21 -3.4; 22 -3.5; 1000 0.0; 500 1.2; 19871 -8.1');
      expect(eq.curve, [(20.0, -3.4), (21.0, -3.4), (22.0, -3.5), (500.0, 1.2), (1000.0, 0.0), (19871.0, -8.1)]);
      expect(eq.bands, isEmpty);
    });
    test('nothing usable is an error', () {
      expect(() => parseEqText('hello'), throwsFormatException);
      expect(() => parseEqText('Preamp: -6 dB'), throwsFormatException);
      expect(() => parseEqText(''), throwsFormatException);
    });
  });

  group('presets and saving', () {
    test('settings round-trip through JSON, with user and per-device presets', () {
      final s = SoundSettings()
        ..bestQuality = false
        ..upsample = Upsample.max
        ..largeBuffer = true
        ..eq = parseEqText(autoEq).$1
        ..crossfeed = Crossfeed.strong
        ..replayGain = ReplayGain.album
        ..rgPreamp = -2.5
        ..rgClip = false
        ..levelling = true
        ..perDevice = true
        ..deviceEq = {'wasapi/{x}': builtInPresets[4].copy()}
        ..presets = [parseEqText('GraphicEQ: 20 1; 20000 -1').$1..name = 'Curve'];
      final back = SoundSettings.parse(jsonEncode(s.toJson()));
      expect(jsonEncode(back.toJson()), jsonEncode(s.toJson()));
    });
    test('missing or broken settings give the defaults', () {
      expect(jsonEncode(SoundSettings.parse(null).toJson()), jsonEncode(SoundSettings().toJson()));
      expect(jsonEncode(SoundSettings.parse('{oops').toJson()), jsonEncode(SoundSettings().toJson()));
      final old = SoundSettings.parse('{"crossfeed":"light","eq":{"graphic":[1,2]}}');
      expect(old.crossfeed, Crossfeed.light);
      expect(old.bestQuality, isTrue);
      expect(old.eq.graphic, [1, 2, 0, 0, 0, 0, 0, 0, 0, 0]);
    });
    test('export / import: a file of presets, or one preset', () {
      final mine = [builtInPresets[5].copy()..name = 'My rock', parseEqText(autoEq).$1];
      final back = importPresets(exportPresets(mine));
      expect([for (final p in back) jsonEncode(p.toJson())], [for (final p in mine) jsonEncode(p.toJson())]);
      expect(importPresets(jsonEncode(mine.first.toJson())).single.name, 'My rock');
      expect(() => importPresets('[1]'), throwsA(anything));
    });
    test('built-in presets: the list the owner asked for', () {
      expect([for (final p in builtInPresets) p.name], [
        'Flat',
        'Bass boost',
        'Bass reducer',
        'Treble boost',
        'Vocal',
        'Rock',
        'Pop',
        'Jazz',
        'Classical',
        'Electronic',
        'Hip-hop',
        'Acoustic',
        'Piano',
        'Podcast / Spoken',
        'Loudness',
        'Late night',
        'Small speakers',
      ]);
      final small = builtInPresets.last;
      expect(small.bands.first.type, BandType.highPass);
      expect(small.bands.first.freq, 100);
      expect(small.limit, isTrue);
    });
  });
}
