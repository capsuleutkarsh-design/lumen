// 0.4 features without mpv: CUE sheets, crossfade and trim rules, long-file places, ratings.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gleo/audio/engine.dart';
import 'package:gleo/library/backup.dart';
import 'package:gleo/library/cue.dart';
import 'package:gleo/library/db.dart';
import 'package:gleo/library/library.dart';
import 'package:gleo/library/lrclib.dart';
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

  group('backup', () {
    late Directory tmp;
    setUp(() => tmp = Directory.systemTemp.createTempSync('gleo_backup'));
    tearDown(() => tmp.deleteSync(recursive: true));

    /// A library in [name] with songs at their own paths: (title, artist, album, seconds, file name).
    Library make(String name, List<(String, String, String, int, String)> songs) {
      final root = p.join(tmp.path, name, 'music');
      for (final (title, artist, album, secs, file) in songs) {
        writeFlac(p.join(root, artist, album, file), {'TITLE': title, 'ARTIST': artist, 'ALBUM': album}, seconds: secs);
      }
      final data = Directory(p.join(tmp.path, name, 'data'))..createSync(recursive: true);
      scan(p.join(data.path, 'library.db'), p.join(data.path, 'covers'), [root]);
      return Library(data.path)..load();
    }

    test('Windows to phone: songs found by tags and length; a summary first; then everything is replaced', () {
      final pc = make('pc', [
        ('Blue Hour', 'Ana', 'Night', 200, '01 Blue Hour.flac'),
        ("Don't Stop!", 'Bo & Co', 'Go', 180, '02.flac'),
        ('Gone', 'Cy', 'Away', 150, 'gone.flac'),
      ]);
      Track pcSong(String title) => pc.tracks.firstWhere((t) => t.title == title);
      pc.toggleFavourite(pcSong('Blue Hour').id);
      pc.setRating([pcSong("Don't Stop!").id], 5);
      pc.recordPlay(pcSong('Blue Hour').id, skipped: false);
      pc.recordPlay(pcSong('Blue Hour').id, skipped: true);
      pc.createPlaylist('Mix', [pcSong("Don't Stop!").id, pcSong('Gone').id, pcSong('Blue Hour').id]);
      pc.saveSmart(SmartPlaylist(0, 'Five stars', rules: const [SmartRule('rating', 5)]));
      pc.setCoverChoice(pcSong('Blue Hour').albumKey, 'original');
      pc.setSetting('appearance', 'light');
      pc.setSetting('audio_device', 'wasapi/{dac}');
      final text = makeBackup(pc, app: '0.4.0', platform: 'windows');
      pc.db.close();

      // The phone: other paths and file names, a slightly different length, one song missing, its own playlist.
      final phone = make('phone', [
        ('Blue Hour', 'Ana', 'Night', 201, 'Blue Hour.flac'),
        ('Dont Stop', 'Bo & Co', 'Go', 180, 'x.flac'),
        ('Other', 'Dee', 'Else', 100, 'o.flac'),
      ]);
      phone.createPlaylist('Old', [phone.tracks.first.id]);
      final folders = phone.setting('folders');
      final plan = planRestore(phone, text);
      expect([plan.total, plan.matched, plan.count('playlists'), plan.count('smart')], [3, 2, 1, 5]);
      applyRestore(phone, plan);
      Track song(String title) => phone.tracks.firstWhere((t) => t.title == title);
      expect(phone.favourites, {song('Blue Hour').id});
      expect(phone.ratings, {song('Dont Stop').id: 5});
      expect(phone.playStats()[song('Blue Hour').id]?.plays, 1);
      expect(phone.playlists.map((pl) => pl.name), ['Mix']); // "Old" is replaced
      expect(phone.playlists.single.trackIds, [song('Dont Stop').id, song('Blue Hour').id]); // the missing song is left out
      expect(phone.smartPlaylists.map((s) => s.name), contains('Five stars'));
      expect(phone.coverChoices.values, ['original']);
      expect(phone.setting('appearance'), 'light');
      expect(phone.setting('audio_device'), isNull, reason: "the PC's device is not the phone's");
      expect(phone.setting('folders'), folders);
      expect(() => planRestore(phone, '{"hello": 1}'), throwsFormatException);
      expect(() => planRestore(phone, 'not json'), throwsFormatException);
      phone.db.close();
    });
  });

  group('LRCLIB answers (fixtures, no network)', () {
    String fixture(String name) => File('test/fixtures/$name').readAsStringSync();
    test('get: the synced lyrics, which parse with their times', () {
      final text = lrclibPick(fixture('lrclib_get.json'), 200)!;
      expect(text, startsWith('[00:12.30] First line'));
      expect(parseLyrics(text).lines.first, (const Duration(milliseconds: 12300), 'First line'));
      expect(lrclibPick(fixture('lrclib_get.json'), 230), isNull, reason: 'more than 2 s longer: another recording');
    });
    test('search: synced first, within 2 s; instrumental and empty answers give nothing', () {
      expect(lrclibPick(fixture('lrclib_search.json'), 200), '[00:02.00] Synced one');
      expect(lrclibPick(fixture('lrclib_search.json'), 260), '[00:01.00] Live version');
      expect(lrclibPick('[]', 200), isNull);
      expect(lrclibPick('{"instrumental": true, "duration": 200}', 200), isNull);
      expect(lrclibPick('{"plainLyrics": "  ", "syncedLyrics": "", "duration": 200}', 200), isNull);
    });
    test('kept lyrics are read before asking (nothing is sent)', () async {
      final tmp = Directory.systemTemp.createTempSync('gleo_lrc');
      addTearDown(() => tmp.deleteSync(recursive: true));
      final t = Track(id: 9, title: 'Blue Hour', artist: 'Ana', durationMs: 200000);
      File(savedLyrics(tmp.path, 9))
        ..createSync(recursive: true)
        ..writeAsStringSync('[00:01.00] Kept');
      expect(await lrclibLyrics(t, tmp.path, 'Gleo/test'), '[00:01.00] Kept');
      expect(loadLyrics(null, null, saved: savedLyrics(tmp.path, 9))?.synced, isTrue);
    });
  });

  test('duplicates: Hide only sets a flag; hidden copies stay hidden after a rescan and are out of suggestions and shuffle', () {
    final tmp = Directory.systemTemp.createTempSync('gleo_dup');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final root = p.join(tmp.path, 'music');
    final a = p.join(root, 'A', '01.flac'), b = p.join(root, 'B', '01.flac');
    for (final f in [a, b]) {
      writeFlac(f, {'TITLE': 'Same', 'ARTIST': 'Ana', 'ALBUM': p.basename(p.dirname(f))});
    }
    final data = p.join(tmp.path, 'data');
    Directory(data).createSync();
    scan(p.join(data, 'library.db'), p.join(data, 'covers'), [root]);
    final lib = Library(data)..load();
    final copy = lib.duplicates().single.last;
    lib.setHidden([copy.id], true);
    expect(File(copy.path).existsSync(), isTrue);
    writeFlac(copy.path, {'TITLE': 'Same', 'ARTIST': 'Ana', 'ALBUM': 'B'}, seconds: 61); // changed on disk: read again
    scan(p.join(data, 'library.db'), p.join(data, 'covers'), [root]);
    lib.load();
    expect(lib.hiddenIds, [copy.id]);
    expect(lib.tracks.map((t) => t.id), isNot(contains(copy.id)));
    final h = lib.home;
    expect([...h.mostPlayed, ...h.notLately, ...h.because].map((x) => x.item.id), isNot(contains(copy.id)));
    expect(h.recentlyAdded.expand((x) => x.item.tracks).map((t) => t.id), isNot(contains(copy.id)));
    lib.db.close();
  });

  test('best copy: more bits × rate, then the higher bitrate', () {
    final mp3 = Track(id: 1, title: 'a', codec: 'MP3', bitDepth: 0, bitrate: 320);
    final cd = Track(id: 2, title: 'a', bitDepth: 16, sampleRate: 44100);
    final hi = Track(id: 3, title: 'a', bitDepth: 24, sampleRate: 96000);
    expect(bestCopy([mp3, cd, hi]).id, 3);
    expect(bestCopy([mp3, cd]).id, 2);
  });
}
