// Wave 2 "extras": smart playlists, statistics, hiding duplicates, the light
// theme's contrast and the accent taken from cover art.
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gleo/library/library.dart';
import 'package:gleo/library/models.dart';
import 'package:gleo/library/scanner.dart';
import 'package:gleo/library/smart.dart';
import 'package:gleo/library/stats.dart';
import 'package:gleo/library/suggestions.dart' show PlayStat;
import 'package:gleo/ui/art_accent.dart';
import 'package:gleo/ui/theme.dart';
import 'package:path/path.dart' as p;

import 'scanner_test.dart' show writeFlac;

double contrast(Color a, Color b) {
  final (x, y) = (a.computeLuminance(), b.computeLuminance());
  return (max(x, y) + 0.05) / (min(x, y) + 0.05);
}

void main() {
  final now = DateTime(2026, 10, 14, 12);
  Track t(
    int id, {
    String artist = 'Ana',
    String? genre,
    int? year,
    int added = 0,
    String codec = 'FLAC',
    int rate = 44100,
    int bits = 16,
  }) => Track(
    id: id,
    title: 'Song $id',
    artist: artist,
    genre: genre,
    year: year,
    addedAt: added,
    codec: codec,
    sampleRate: rate,
    bitDepth: bits,
  );

  group('smart playlists', () {
    final day = now.millisecondsSinceEpoch - 86400000;
    final tracks = [
      t(1, genre: 'Jazz; Soul', year: 1995, added: day * 1),
      t(2, artist: 'Bo Diddley', genre: 'Rock', year: 1999, added: now.millisecondsSinceEpoch - 40 * 86400000),
      t(3, genre: 'jazz', year: 2005, codec: 'MP3', rate: 44100, bits: 0),
      t(4, artist: 'Cy', year: 1990, rate: 96000, bits: 24),
    ];
    final c = SmartContext({1: PlayStat(5), 2: PlayStat(1), 4: PlayStat(0, 3)}, {3}, now);
    List<int> ids(SmartPlaylist s) => [for (final x in s.evaluate(tracks, c)) x.id];

    test('each rule', () {
      List<int> one(SmartRule r) => ids(SmartPlaylist(0, 'x', rules: [r], sort: 'title'));
      expect(one(const SmartRule('genre', 'JAZZ')), [1, 3]);
      expect(one(const SmartRule('year', 1990, 1999)), [1, 2, 4]);
      expect(one(const SmartRule('added', 30)), [1]);
      expect(one(const SmartRule('plays', 1)), [1]);
      expect(one(const SmartRule('never')), [3, 4]); // skips are not plays
      expect(one(const SmartRule('fav')), [3]);
      expect(one(const SmartRule('format', 'flac')), [1, 2, 4]);
      expect(one(const SmartRule('rate', 96000)), [4]);
      expect(one(const SmartRule('bits', 24)), [4]);
      expect(one(const SmartRule('artist', 'diddley')), [2]);
    });

    test('match all / any, sort, limit, and the JSON round trip', () {
      final all = SmartPlaylist(9, 'x', rules: const [SmartRule('genre', 'jazz'), SmartRule('format', 'FLAC')]);
      expect(ids(all), [1]);
      final any = SmartPlaylist(9, 'x', rules: all.rules, any: true, sort: 'plays', limit: 3);
      expect(ids(any), hasLength(3)); // all four match; cut to 3
      expect(ids(any).take(2), [1, 2]); // 5 plays, then 1
      final back = SmartPlaylist.fromRow(9, 'x', any.rulesJson);
      expect([back.any, back.sort, back.limit, back.rules.length], [true, 'plays', 3, 2]);
      expect(ids(back), ids(any));
      expect(SmartPlaylist.fromRow(1, 'broken', '{nope').evaluate(tracks, c), isEmpty);
      expect(SmartPlaylist(1, 'empty').evaluate(tracks, c), isEmpty);
    });
  });

  group('library', () {
    late Directory tmp;
    late Library lib;
    late String song1, song2;
    setUp(() {
      tmp = Directory.systemTemp.createTempSync('mp_extras');
      song1 = p.join(tmp.path, 'music', 'A', '01.flac');
      song2 = p.join(tmp.path, 'music', 'B', '01.flac');
      writeFlac(song1, {'TITLE': 'Same', 'ARTIST': 'Ana', 'ALBUM': 'A'});
      writeFlac(song2, {'TITLE': 'Same', 'ARTIST': 'Ana', 'ALBUM': 'B'});
      lib = Library((Directory(p.join(tmp.path, 'data'))..createSync()).path);
      scan(lib.dbPath, lib.coverDir, [p.join(tmp.path, 'music')]);
      lib.load();
    });
    tearDown(() {
      lib.db.close();
      tmp.deleteSync(recursive: true);
    });

    test('the four ready-made smart playlists exist and evaluate', () {
      expect([for (final s in lib.smartPlaylists) s.name], ['Recently added', 'Most played', 'Never played', 'Hi-Res']);
      final never = lib.smartPlaylists.firstWhere((s) => s.name == 'Never played');
      expect(lib.smartTracks(never), hasLength(2));
      lib.recordPlay(lib.tracks.first.id, skipped: false);
      expect(lib.smartTracks(never), hasLength(1)); // live: the next evaluation sees the play
      final id = lib.saveSmart(SmartPlaylist(0, 'Mine', rules: const [SmartRule('artist', 'ana')]));
      expect(lib.smartTracks(lib.smartPlaylist(id)!), hasLength(2));
      lib.deleteSmart(id);
      expect(lib.smartPlaylist(id), isNull);
    });

    test('"Hide from library" never touches the files', () {
      final before = {
        for (final f in [song1, song2]) f: (File(f).readAsBytesSync(), File(f).lastModifiedSync()),
      };
      final dups = lib.duplicates();
      expect(dups.single, hasLength(2));
      final hide = dups.single.last.id;
      lib.setHidden([hide], true);
      expect(lib.tracks.map((x) => x.id), isNot(contains(hide)));
      expect(lib.duplicates(), isEmpty);
      expect(lib.hiddenIds, [hide]);
      // A rescan keeps it hidden, and both files are exactly as they were.
      scan(lib.dbPath, lib.coverDir, [p.join(tmp.path, 'music')]);
      lib.load();
      expect(lib.tracks.map((x) => x.id), isNot(contains(hide)));
      for (final e in before.entries) {
        expect(File(e.key).existsSync(), isTrue);
        expect(File(e.key).readAsBytesSync(), e.value.$1);
        expect(File(e.key).lastModifiedSync(), e.value.$2);
      }
      lib.setHidden([hide], false);
      expect(lib.tracks, hasLength(2));
    });

    test('statistics add up plays per day, week and month, and the top lists', () {
      final a = lib.tracks.first, b = lib.tracks.last;
      final at = DateTime(2026, 10, 14, 9);
      for (final (id, d) in [(a.id, 0), (a.id, 0), (b.id, 1), (a.id, 9)]) {
        lib.recordPlay(id, skipped: false, at: at.subtract(Duration(days: d)));
      }
      lib.recordPlay(b.id, skipped: true, at: at); // skips are left out
      final rows = lib.playsSince(DateTime(2026));
      expect(rows, hasLength(4));
      final week = listenStats(rows, lib.byId, DateTime(2026, 10, 8), DateTime(2026, 10, 15), Bucket.day);
      expect(week.buckets, hasLength(7));
      expect(week.plays, 3);
      expect(week.buckets.last.$2, Duration(milliseconds: a.durationMs * 2));
      expect(week.buckets[5].$2, Duration(milliseconds: b.durationMs));
      expect(week.songs.first, (a.id, 2));
      expect(week.artists.single, ('Ana', 3));
      expect(week.albums, hasLength(2));
      final weeks = listenStats(rows, lib.byId, DateTime(2026, 9, 1), DateTime(2026, 10, 15), Bucket.week);
      expect(weeks.buckets.first.$1, DateTime(2026, 8, 31)); // a Monday
      expect(weeks.plays, 4);
      expect(bucketStart(DateTime(2026, 10, 14, 23), Bucket.month), DateTime(2026, 10));
      expect(formatCounts(lib.tracks), [('FLAC', 2)]);
      expect(lib.librarySize, File(song1).lengthSync() + File(song2).lengthSync());
      expect(fmtBytes(1536), '1.5 KB');
    });
  });

  test('light and dark: text, dim, faint and the accent are AA (4.5:1) on every surface', () {
    for (final pal in [Palette.dark, Palette.light]) {
      for (final bg in [pal.bg, pal.raised1, pal.raised2, pal.raised3]) {
        for (final fg in [pal.text, pal.dim, pal.faint, pal.accent]) {
          expect(contrast(fg, bg), greaterThanOrEqualTo(4.5), reason: '${pal.brightness}: $fg on $bg');
        }
      }
      expect(contrast(pal.onLight, pal.text), greaterThanOrEqualTo(4.5), reason: 'primary button label');
    }
  });

  group('accent from cover art', () {
    List<int> fill(Color c, [int n = 64 * 64]) {
      final px = [(c.r * 255).round(), (c.g * 255).round(), (c.b * 255).round(), 255];
      return [for (var i = 0; i < n; i++) ...px];
    }

    test('a colourful cover gives its colour', () {
      final c = pickAccent(fill(const Color(0xFF2E86DE)), Palette.dark.bg);
      expect(c, isNotNull);
      expect(HSLColor.fromColor(c!).hue, closeTo(HSLColor.fromColor(const Color(0xFF2E86DE)).hue, 8));
    });

    test('the dominant colour wins over a muddy average', () {
      // 70 % blue, 30 % orange: the average would be grey-ish; the accent stays blue.
      final px = [...fill(const Color(0xFF1E6FD9), 70), ...fill(const Color(0xFFE8833A), 30)];
      final c = pickAccent(px, Palette.dark.bg)!;
      expect(HSLColor.fromColor(c).hue, inInclusiveRange(200, 225));
    });

    test('grey, too dark or too light falls back to gold (null)', () {
      expect(pickAccent(fill(const Color(0xFF808080)), Palette.dark.bg), isNull); // grey
      expect(pickAccent(fill(const Color(0xFF1A0505)), Palette.dark.bg), isNull); // too dark on black
      expect(pickAccent(fill(const Color(0xFFFFF4F0)), Palette.dark.bg), isNull); // too light (like the bar)
      expect(pickAccent(fill(const Color(0xFFFFE066)), Palette.light.bg), isNull); // pale yellow on paper
      expect(pickAccent(const [], Palette.dark.bg), isNull);
    });
  });
}
