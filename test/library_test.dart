import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:music_player/library/library.dart';
import 'package:music_player/library/suggestions.dart';
import 'package:path/path.dart' as p;

import 'scanner_test.dart' show writeFlac;

void main() {
  late Directory tmp;
  late Library lib;
  late String music;
  setUp(() {
    tmp = Directory.systemTemp.createTempSync('mp_lib');
    music = p.join(tmp.path, 'music');
    lib = Library((Directory(p.join(tmp.path, 'data'))..createSync()).path);
    lib.setSetting('folders', '["${music.replaceAll(r'\', r'\\')}"]');
  });
  tearDown(() {
    lib.db.close();
    tmp.deleteSync(recursive: true);
  });

  void song(String rel, Map<String, String> tags, {int seconds = 60}) => writeFlac(p.join(music, rel), tags, seconds: seconds);

  test('W1 + multi-artist: artist pages show every credited artist; bands stay whole', () async {
    song('Ana/Blue/01.flac', {'TITLE': 'One', 'ARTIST': 'Ana', 'ALBUM': 'Blue'});
    song('Ana/Blue/02.flac', {'TITLE': 'Two', 'ARTIST': 'Ana feat. Bo', 'ALBUM': 'Blue'});
    song('Ana/Blue/03.flac', {'TITLE': 'Three', 'ARTIST': 'Ana & Cy', 'ALBUM': 'Blue'});
    song('Cy/Solo/01.flac', {'TITLE': 'Alone', 'ARTIST': 'Cy', 'ALBUM': 'Solo'});
    song('SG/Bridge/01.flac', {'TITLE': 'Water', 'ARTIST': 'Simon & Garfunkel', 'ALBUM': 'Bridge'});
    song('Mix/01.flac', {'TITLE': 'Duet', 'ARTIST': 'Dee & Eve', 'ARTISTS': 'Dee & Eve\u0000Fay', 'ALBUM': 'Mix', 'COMPILATION': '1'});
    await lib.rescan();
    expect(lib.albumByKey.values.firstWhere((a) => a.title == 'Blue').artist, 'Ana'); // not Various Artists
    expect(
      [for (final t in lib.albums.firstWhere((a) => a.title == 'Blue').tracks) t.artists],
      [
        ['Ana'],
        ['Ana', 'Bo'],
        ['Ana', 'Cy'],
      ],
    );
    expect(lib.artistNamed('Bo')!.appearsOn.single.title, 'Two');
    expect([for (final t in lib.artistNamed('Cy')!.appearsOn) t.title], ['Three']);
    expect(lib.artistNamed('Cy')!.albums.single.title, 'Solo');
    expect(lib.artistNamed('Simon & Garfunkel')!.albums.single.title, 'Bridge');
    expect(lib.artistNamed('Simon'), isNull);
    expect([lib.artistNamed('Dee & Eve')?.appearsOn.single.title, lib.artistNamed('Fay')?.appearsOn.single.title], ['Duet', 'Duet']);
    expect(lib.artistNamed('Ana feat. Bo')!.name, 'Ana'); // "Go to artist" from a credit
    expect(lib.artistNamed('Ana, Cy')!.name, 'Ana');
  });

  test('genres, years, composers by work, sort names, duplicates', () async {
    song('A/01.flac', {
      'TITLE': 'Kyrie',
      'ARTIST': 'Choir',
      'ALBUM': 'Mass',
      'GENRE': 'Classical; Choral',
      'DATE': '1990',
      'COMPOSER': 'Bach',
      'WORK': 'Mass in B minor',
      'MOVEMENT': '1',
      'ALBUMSORT': 'B Mass',
    });
    song('A/02.flac', {
      'TITLE': 'Gloria',
      'ARTIST': 'Choir',
      'ALBUM': 'Mass',
      'GENRE': 'classical',
      'DATE': '1990',
      'COMPOSER': 'Bach',
      'WORK': 'Mass in B minor',
      'MOVEMENT': '2',
    });
    song('B/01.flac', {'TITLE': 'Air', 'ARTIST': 'Band', 'ALBUM': 'A Suite', 'GENRE': 'Rock/Pop', 'DATE': '2001', 'COMPOSER': 'Bach'});
    song('C/01.flac', {'TITLE': 'Air!', 'ARTIST': 'band', 'ALBUM': 'Copy', 'DATE': '2001'}, seconds: 61);
    song('C/02.flac', {'TITLE': 'Air', 'ARTIST': 'Band', 'ALBUM': 'Copy'}, seconds: 300);
    await lib.rescan();
    expect(lib.genres.keys, ['Choral', 'Classical', 'Pop', 'Rock']);
    expect(lib.genres['Classical']!.length, 2);
    expect([for (final a in lib.genreAlbums('Rock')) a.title], ['A Suite']);
    expect(lib.years.keys, [2001, 1990]);
    expect(lib.composers.keys, ['Bach']);
    final works = lib.works('Bach');
    expect([for (final t in works['Mass in B minor']!) t.title], ['Kyrie', 'Gloria']);
    expect(works.keys, containsAll(['Mass in B minor', 'A Suite']));
    expect([for (final a in lib.albums) a.title], ['A Suite', 'Mass', 'Copy']); // "Mass" sorts as "B Mass"
    expect(
      [for (final g in lib.duplicates()) g.map((t) => t.album).toSet()],
      [
        {'A Suite', 'Copy'},
      ],
    );
  });

  test('P3: Home stats come from SQL and match the events', () async {
    song('A/01.flac', {'TITLE': 'One', 'ARTIST': 'Ana', 'ALBUM': 'Blue'});
    song('A/02.flac', {'TITLE': 'Two', 'ARTIST': 'Ana', 'ALBUM': 'Blue'});
    await lib.rescan();
    final [a, b] = [for (final t in lib.tracks) t.id];
    final at = DateTime(2026, 1, 1);
    lib.recordPlay(a, skipped: false, at: at);
    lib.recordPlay(a, skipped: false, at: at.add(const Duration(days: 1)));
    lib.recordPlay(a, skipped: true, at: at.add(const Duration(days: 2)));
    lib.recordPlay(b, skipped: true, at: at);
    final s = lib.playStats();
    final e = statsFrom([
      PlayEvent(a, at, false),
      PlayEvent(a, at.add(const Duration(days: 1)), false),
      PlayEvent(a, at.add(const Duration(days: 2)), true),
      PlayEvent(b, at, true),
    ]);
    for (final id in [a, b]) {
      expect([s[id]!.plays, s[id]!.skips, s[id]!.last], [e[id]!.plays, e[id]!.skips, e[id]!.last]);
    }
    expect(lib.home.mostPlayed.single.item.id, a);
  });

  test('a first scan shows tracks while it runs', () async {
    for (var i = 0; i < 700; i++) {
      song('A${i ~/ 100}/$i.flac', {'TITLE': 'T$i', 'ARTIST': 'Ana', 'ALBUM': 'Album ${i ~/ 100}'});
    }
    final seen = <int>[];
    lib.addListener(() {
      if (lib.scan.value != null) seen.add(lib.tracks.length);
    });
    await lib.rescan();
    expect(seen, isNotEmpty);
    expect(seen.first, inExclusiveRange(0, 700));
    expect(lib.albums.length, 7); // grouped (provisionally) as they appear, then for good
    expect(lib.tracks.length, 700);
  }, timeout: const Timeout(Duration(minutes: 2)));
}
