// 0.4 playback features through the real libmpv (null audio output): CUE tracks, crossfade,
// trim silence and resuming long files. The music is generated here (quiet test tones, never played aloud).
@Tags(['mpv'])
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart' hide Track;
import 'package:gleo/audio/engine.dart';
import 'package:gleo/library/library.dart';
import 'package:gleo/library/models.dart';
import 'package:path/path.dart' as p;

import 'mpv_harness.dart' show dll, waitFor, wait;

/// Only the DLL is needed: the music is made here.
final String? noMpv = File(dll).existsSync() ? null : 'needs libmpv-2.dll: run flutter build windows first';

/// A mono 44.1 kHz 16-bit WAV of [seconds], the sample at time t from [f] (-1..1).
void writeWav(String path, double seconds, double Function(double t) f) {
  const rate = 44100;
  final n = (seconds * rate).round();
  final b = ByteData(44 + n * 2);
  void s(int at, String x) => b.buffer.asUint8List().setAll(at, ascii.encode(x));
  s(0, 'RIFF');
  b.setUint32(4, 36 + n * 2, Endian.little);
  s(8, 'WAVEfmt ');
  b
    ..setUint32(16, 16, Endian.little)
    ..setUint16(20, 1, Endian.little)
    ..setUint16(22, 1, Endian.little)
    ..setUint32(24, rate, Endian.little)
    ..setUint32(28, rate * 2, Endian.little)
    ..setUint16(32, 2, Endian.little)
    ..setUint16(34, 16, Endian.little);
  s(36, 'data');
  b.setUint32(40, n * 2, Endian.little);
  for (var i = 0; i < n; i++) {
    b.setInt16(44 + i * 2, (f(i / rate).clamp(-1.0, 1.0) * 32767).round(), Endian.little);
  }
  File(path)
    ..createSync(recursive: true)
    ..writeAsBytesSync(b.buffer.asUint8List());
}

double tone(double hz, double t) => 0.3 * sin(2 * pi * hz * t);

void main() {
  late Library lib;
  late Engine e;
  late Directory tmp;
  Track named(String title) => lib.tracks.firstWhere((t) => t.title == title);
  NativePlayer mpv(Player x) => x.platform as NativePlayer;

  setUpAll(() async {
    if (noMpv != null) return;
    initMediaKit(libmpv: dll);
    tmp = Directory.systemTemp.createTempSync('gleo_feat_mpv');
    final root = p.join(tmp.path, 'music');
    writeWav(p.join(root, 'Cue', 'Concert.wav'), 12, (t) => tone(t < 4 ? 440 : (t < 8 ? 660 : 880), t));
    File(p.join(root, 'Cue', 'Concert.cue')).writeAsStringSync(
      'PERFORMER "Band"\nTITLE "Concert"\nFILE "Concert.wav" WAVE\n'
      '  TRACK 01 AUDIO\n    TITLE "Part one"\n    INDEX 01 00:00:00\n'
      '  TRACK 02 AUDIO\n    TITLE "Part two"\n    INDEX 01 00:04:00\n'
      '  TRACK 03 AUDIO\n    TITLE "Part three"\n    INDEX 01 00:08:00\n',
    );
    writeWav(p.join(root, 'X', 'one.wav'), 6, (t) => tone(500, t));
    writeWav(p.join(root, 'Y', 'two.wav'), 6, (t) => tone(700, t));
    writeWav(p.join(root, 'Quiet', 'padded.wav'), 9, (t) => t >= 3 && t < 6 ? tone(600, t) : 0);
    writeWav(p.join(root, 'Long', 'long.wav'), 40, (t) => tone(300, t));
    lib = Library((Directory(p.join(tmp.path, 'data'))..createSync()).path)..load();
    lib.setSetting('folders', jsonEncode([root]));
    await lib.rescan();
    // A 40 s file the library thinks is 25 minutes long: long enough to be remembered.
    lib.db.execute('UPDATE tracks SET duration_ms = 1500000 WHERE title = ?', [named('long').title]);
    lib.load();
  });

  setUp(() async {
    if (noMpv != null) return;
    lib.setSetting('volume', '80');
    e = Engine(lib, silent: true);
    await e.init();
  });

  tearDown(() async {
    if (noMpv != null) return;
    await e.shutdown();
    lib.db.execute("DELETE FROM settings WHERE key IN ('queue', 'queue_pos', 'crossfade', 'trimSilence', 'resumeLong', 'resume')");
    lib.db.execute('DELETE FROM plays');
  });

  test('CUE tracks play as their own songs: times, seek, gapless hand-over (never crossfaded), plays', () async {
    final album = lib.albums.firstWhere((a) => a.title == 'Concert').tracks;
    expect([for (final t in album) (t.title, t.startMs, t.durationMs)], [
      ('Part one', 0, 4000),
      ('Part two', 4000, 4000),
      ('Part three', 8000, 4000),
    ]);
    e.setPlayback(crossfade: 3); // neighbours on one album: never crossfaded
    final first = e.player;
    await e.playTracks(album);
    await waitFor(() => e.current?.title == 'Part two', timeout: const Duration(seconds: 8));
    expect(e.current?.title, 'Part two');
    expect(identical(e.player, first), isTrue, reason: 'no crossfade inside an album');
    expect(e.duration, const Duration(seconds: 4));
    await waitFor(() => e.position.value > const Duration(milliseconds: 200));
    expect(e.position.value, lessThan(const Duration(seconds: 2)), reason: "the track's own clock, not the file's");
    await e.seek(const Duration(seconds: 1));
    await wait(400);
    final filePos = double.parse(await mpv(e.player).getProperty('time-pos'));
    expect(filePos, closeTo(5.3, 0.5));
    expect(e.position.value.inMilliseconds, closeTo(1300, 500));
    await waitFor(() => e.current?.title == 'Part three', timeout: const Duration(seconds: 6));
    expect(e.current?.title, 'Part three');
    final played = lib.playStats();
    expect(played.keys, contains(album[0].id), reason: 'each CUE track counts its own plays');
  }, skip: noMpv, timeout: const Timeout(Duration(seconds: 60)));

  test('crossfade: the next song starts on the other player while this one fades out, then stops', () async {
    e.setPlayback(crossfade: 2);
    final first = e.player;
    await e.playTracks([named('one'), named('two')]);
    await waitFor(() => e.current?.title == 'two', timeout: const Duration(seconds: 8));
    expect(e.current?.title, 'two');
    expect(identical(e.player, first), isFalse, reason: 'the second player took over');
    await wait(500);
    final oldVol = double.parse(await mpv(first).getProperty('volume'));
    final newVol = double.parse(await mpv(e.player).getProperty('volume'));
    expect(oldVol, inExclusiveRange(0, 80), reason: 'the old song is fading out');
    expect(newVol, inExclusiveRange(0, 80), reason: 'the new song is fading in');
    expect(e.position.value, lessThan(const Duration(seconds: 2)));
    await wait(2000);
    expect(await mpv(first).getProperty('idle-active'), 'yes', reason: 'the old player stopped');
    expect(double.parse(await mpv(e.player).getProperty('volume')), 80);
  }, skip: noMpv, timeout: const Timeout(Duration(seconds: 60)));

  test('trim silence: 3 s of silence at each end is skipped', () async {
    e.setPlayback(trimSilence: true);
    final sw = Stopwatch()..start();
    await e.playTracks([named('padded'), named('one')]);
    await waitFor(() => e.playing && e.position.value > Duration.zero);
    expect(e.position.value, greaterThan(const Duration(milliseconds: 2400)), reason: 'started after the silence');
    await waitFor(() => e.current?.title == 'one', timeout: const Duration(seconds: 9));
    expect(e.current?.title, 'one');
    expect(sw.elapsed, lessThan(const Duration(seconds: 6)), reason: 'the 3 s of silence at the end were skipped too');
  }, skip: noMpv, timeout: const Timeout(Duration(seconds: 60)));

  test('resume: a long file starts where it was left, with a toast that offers Start over', () async {
    e.setPlayback(resumeLong: true);
    final long = named('long');
    await e.playTracks([long]);
    await waitFor(() => e.playing && e.position.value > const Duration(milliseconds: 300));
    await e.seek(const Duration(seconds: 35));
    await wait(300);
    await e.playTracks([named('one')]); // leaving it remembers the place
    final resumed = e.resumed.first;
    await e.playTracks([long]);
    expect((await resumed.timeout(const Duration(seconds: 5))).inSeconds, 35);
    await waitFor(() => e.playing && e.position.value > const Duration(milliseconds: 35300)); // mpv's own clock, not the start it was given
    expect(e.position.value.inSeconds, inInclusiveRange(35, 37));
    await e.seek(Duration.zero); // Start over
    await wait(300);
    expect(e.position.value, lessThan(const Duration(seconds: 2)));
  }, skip: noMpv, timeout: const Timeout(Duration(seconds: 60)));

  tearDownAll(() {
    if (noMpv == null) {
      lib.db.close();
      tmp.deleteSync(recursive: true);
    }
  });
}
