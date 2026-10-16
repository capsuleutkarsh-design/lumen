// 0.4 features without mpv: CUE sheets, crossfade and trim rules, long-file places, ratings.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gleo/audio/engine.dart';
import 'package:gleo/library/cue.dart';
import 'package:gleo/library/db.dart';
import 'package:gleo/library/library.dart';
import 'package:gleo/library/lyrics.dart';
import 'package:gleo/library/models.dart';
import 'package:gleo/library/scanner.dart';
import 'package:gleo/library/smart.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

import 'scanner_test.dart' show writeFlac;

const sheet = '''﻿REM GENRE "Progressive Rock"
REM DATE 1999 / 2003 remaster
PERFORMER "The Band"
TITLE "Live at Home"
FILE "Live at Home.wav" WAVE
  TRACK 01 AUDIO
    TITLE "Opening"
    INDEX 01 00:00:00
  TRACK 02 AUDIO
    TITLE "Second Song"
    PERFORMER "The Band feat. Guest"
    INDEX 00 04:58:20
    INDEX 01 05:00:37
  TRACK 03 AUDIO
    TITLE "Encore"
    INDEX 01 09:30:00
''';

void main() {
  group('CUE sheets', () {
    test('tracks, index times (75 frames a second), album tags', () {
      final cue = parseCue(sheet);
      expect([cue.title, cue.performer, cue.genre, cue.year], ['Live at Home', 'The Band', 'Progressive Rock', 1999]);
      expect([for (final t in cue.tracks) (t.no, t.title, t.startMs)], [
        (1, 'Opening', 0),
        (2, 'Second Song', 300493), // 05:00:37 = 300 s + 37/75 s; INDEX 00 (the pregap) is not the start
        (3, 'Encore', 570000),
      ]);
      expect(cue.tracks[1].performer, 'The Band feat. Guest');
      expect(cue.tracks[0].performer, isNull);
    });

    test('a sheet written for the .wav still splits the .flac; a one-track sheet splits nothing', () {
      final cue = parseCue(sheet);
      expect(cue.tracksOf('Live at Home.wav'), hasLength(3));
      expect(cue.tracksOf('live at home.FLAC'), hasLength(3));
      expect(cue.tracksOf('Other.flac'), isEmpty);
      expect(parseCue('FILE "a.flac" WAVE\nTRACK 01 AUDIO\nINDEX 01 00:00:00').tracksOf('a.flac'), isEmpty);
    });

    test('Windows-1252 sheets (no BOM, not UTF-8) read right', () {
      final bytes = [...latin1.encode('TITLE "Caf'), 0xE9, ...latin1.encode(' '), 0x96, ...latin1.encode(' 50'), 0x80, 0x22];
      expect(parseCue(decodeText(bytes)).title, 'Café – 50€');
      expect(parseCue(decodeText(utf8.encode('TITLE "Café – 50€"'))).title, 'Café – 50€');
    });

    test('the scanner lists a big file with a .cue as its tracks, and the file itself once the sheet goes', () {
      final tmp = Directory.systemTemp.createTempSync('gleo_cue');
      addTearDown(() => tmp.deleteSync(recursive: true));
      final root = p.join(tmp.path, 'lib'), dir = p.join(root, 'Live');
      final flac = p.join(dir, 'Live at Home.flac'), cueFile = File(p.join(dir, 'Live at Home.cue'));
      writeFlac(flac, {'TITLE': 'Whole file', 'ARTIST': 'Tagged'}, seconds: 720);
      cueFile.writeAsStringSync(sheet);
      final db = p.join(tmp.path, 'library.db'), covers = p.join(tmp.path, 'covers');
      expect(scan(db, covers, [root]).added, 3);
      final lib = Library(tmp.path)..load();
      expect([for (final t in lib.tracks) (t.title, t.startMs, t.durationMs, t.trackNo)], [
        ('Opening', 0, 300493, 1),
        ('Second Song', 300493, 269507, 2),
        ('Encore', 570000, 150000, 3), // to the file's end (12 min)
      ]);
      final t = lib.tracks[1];
      expect([t.path, t.artist, t.albumArtist, t.album, t.year, t.genre], [
        flac,
        'The Band feat. Guest',
        'The Band',
        'Live at Home',
        1999,
        'Progressive Rock',
      ]);
      expect(t.badge, endsWith(' · CUE'));
      expect(lib.albums.single.tracks, hasLength(3));
      lib.recordPlay(t.id, skipped: false); // plays are per track
      expect(lib.playStats().keys, [t.id]);
      lib.db.close();

      expect(scan(db, covers, [root]).unchanged, 3);
      cueFile.deleteSync();
      final r = scan(db, covers, [root]);
      expect([r.added, r.removed], [1, 3]);
      final again = Library(tmp.path)..load();
      expect([for (final t in again.tracks) (t.title, t.startMs, t.path)], [('Whole file', null, flac)]);
      again.db.close();
    });
  });

  group('crossfade', () {
    Track t(int id, String album, int? no, {int disc = 1}) => Track(id: id, title: '$id', album: album, trackNo: no, discNo: disc);
    test('never between neighbouring tracks of one album (gapless, CUE); otherwise yes', () {
      expect(crossfades(t(1, 'A', 1), t(2, 'A', 2)), isFalse);
      expect(crossfades(t(1, 'A', 9), t(2, 'A', 1, disc: 2)), isFalse); // next disc
      expect(crossfades(t(1, 'A', null), t(2, 'A', null)), isFalse); // untagged: assume gapless
      expect(crossfades(t(1, 'A', 1), t(2, 'A', 5)), isTrue); // shuffled within the album
      expect(crossfades(t(1, 'A', 1), t(2, 'B', 2)), isTrue);
      expect(crossfades(t(1, 'A', 3), t(2, 'A', 3)), isTrue); // repeat one
    });
  });

  test('long files: a place is kept only in files over 20 minutes, away from the start and end', () {
    const m = Duration(minutes: 1);
    expect(resumePoint(m * 19, m * 5), isNull);
    expect(resumePoint(m * 60, const Duration(seconds: 20)), isNull);
    expect(resumePoint(m * 60, m * 23 + const Duration(seconds: 10)), m * 23 + const Duration(seconds: 10));
    expect(resumePoint(m * 60, m * 60 - const Duration(seconds: 10)), isNull);
  });

  group('trim silence', () {
    List<double> run(int quiet, int loud, {bool quietFirst = true}) => [
      ...List.filled(quietFirst ? quiet : loud, quietFirst ? -120.0 : -20.0),
      ...List.filled(quietFirst ? loud : quiet, quietFirst ? -20.0 : -120.0),
    ];
    const len = Duration(seconds: 200);
    test('cuts near-digital silence over a second, keeping a little', () {
      final (lead, end) = silenceTrim(run(30, 270), run(40, 260, quietFirst: false), len);
      expect(lead, const Duration(milliseconds: 2750));
      expect(end, const Duration(milliseconds: 196250)); // the last loud window ends 4 s before the end
    });
    test('a quiet intro (peaks above -60 dBFS) and short or no silence stay', () {
      expect(silenceTrim(List.filled(300, -45.0), List.filled(300, -50.0), len), (Duration.zero, null));
      expect(silenceTrim(run(8, 292), run(8, 292, quietFirst: false), len), (Duration.zero, null));
      expect(silenceTrim(List.filled(300, -150.0), List.filled(300, -150.0), len), (Duration.zero, null)); // all silent: leave it
    });
  });

  group('ratings', () {
    late Directory tmp;
    setUp(() => tmp = Directory.systemTemp.createTempSync('gleo_rating'));
    tearDown(() => tmp.deleteSync(recursive: true));

    test('a 0.3 database gains ratings (none yet); they live in the database only', () {
      final path = p.join(tmp.path, 'library.db');
      final old = sqlite3.open(path);
      for (var v = 0; v < 4; v++) {
        old.execute(migrations[v]);
      }
      old.execute('PRAGMA user_version = 4');
      old.execute(
        "INSERT INTO tracks(id, path, root, folder, mtime, size, title, album, duration_ms, codec, sample_rate, bit_depth, channels, bitrate, added_at) "
        "VALUES(3, 'x.flac', '', '', 1, 1, 'Song', 'Blue', 1, 'FLAC', 44100, 16, 2, 0, 0)",
      );
      old.close();
      final lib = Library(tmp.path)..load();
      expect(lib.db.select('PRAGMA user_version').single.values.first, 5);
      expect(lib.rating(3), 0);
      lib.setRating([3], 4);
      lib.load();
      expect(lib.ratings, {3: 4});
      final s = SmartPlaylist(0, 'Good', rules: const [SmartRule('rating', 4)]);
      expect(lib.smartTracks(s).map((t) => t.id), [3]);
      expect(SmartPlaylist(0, 'Best', rules: const [SmartRule('rating', 5)]).evaluate(lib.tracks, SmartContext({}, {}, DateTime(2026), lib.ratings)), isEmpty);
      lib.setRating([3], 0);
      expect(lib.ratings, isEmpty);
      lib.db.close();
    });
  });

  test('best copy: more bits × rate, then the higher bitrate', () {
    final mp3 = Track(id: 1, title: 'a', codec: 'MP3', bitDepth: 0, bitrate: 320);
    final cd = Track(id: 2, title: 'a', bitDepth: 16, sampleRate: 44100);
    final hi = Track(id: 3, title: 'a', bitDepth: 24, sampleRate: 96000);
    expect(bestCopy([mp3, cd, hi]).id, 3);
    expect(bestCopy([mp3, cd]).id, 2);
  });
}
