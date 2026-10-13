import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:music_player/library/db.dart';
import 'package:music_player/library/models.dart';
import 'package:music_player/library/scanner.dart';
import 'package:path/path.dart' as p;

/// A header-only FLAC file (STREAMINFO + Vorbis comments): enough for the tag reader.
void writeFlac(String path, Map<String, String> tags, {int seconds = 60}) {
  final info = ByteData(34)
    ..setUint16(0, 4096)
    ..setUint16(2, 4096);
  final rate = 44100, samples = rate * seconds;
  info.setUint64(10, (rate << 44) | (1 << 41) | (15 << 36) | samples); // stereo, 16-bit
  final vc = BytesBuilder();
  void u32le(int v) => vc.add((ByteData(4)..setUint32(0, v, Endian.little)).buffer.asUint8List());
  u32le(0);
  u32le(tags.length);
  for (final e in tags.entries) {
    final s = utf8.encode('${e.key}=${e.value}');
    u32le(s.length);
    vc.add(s);
  }
  final body = vc.toBytes();
  final out = BytesBuilder()
    ..add(ascii.encode('fLaC'))
    ..add([0, 0, 0, 34])
    ..add(info.buffer.asUint8List())
    ..add([0x84, body.length >> 16, (body.length >> 8) & 0xFF, body.length & 0xFF])
    ..add(body);
  File(path)
    ..createSync(recursive: true)
    ..writeAsBytesSync(out.toBytes());
}

void main() {
  late Directory tmp;
  late String lib, dbPath, covers;
  setUp(() {
    tmp = Directory.systemTemp.createTempSync('mp_scan');
    lib = p.join(tmp.path, 'lib');
    dbPath = p.join(tmp.path, 'library.db');
    covers = p.join(tmp.path, 'covers');
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  test('rescan reads only new or changed files and removes missing ones', () {
    for (var i = 1; i <= 3; i++) {
      writeFlac(p.join(lib, 'A', '0$i.flac'), {'TITLE': 'T$i', 'ARTIST': 'Ana', 'ALBUM': 'Blue', 'TRACKNUMBER': '$i'});
    }
    var r = scan(dbPath, covers, [lib]);
    expect([r.added, r.updated, r.removed, r.unchanged], [3, 0, 0, 0]);

    r = scan(dbPath, covers, [lib]);
    expect([r.added, r.updated, r.removed, r.unchanged], [0, 0, 0, 3]);

    // Change one (new tags, newer time), add one, delete one.
    final changed = File(p.join(lib, 'A', '01.flac'));
    writeFlac(changed.path, {'TITLE': 'Renamed', 'ARTIST': 'Ana', 'ALBUM': 'Blue', 'TRACKNUMBER': '1'}, seconds: 61);
    changed.setLastModifiedSync(DateTime.now().add(const Duration(minutes: 1)));
    writeFlac(p.join(lib, 'A', '04.flac'), {'TITLE': 'T4', 'ARTIST': 'Ana', 'ALBUM': 'Blue'});
    File(p.join(lib, 'A', '03.flac')).deleteSync();
    r = scan(dbPath, covers, [lib]);
    expect([r.added, r.updated, r.removed, r.unchanged], [1, 1, 1, 1]);

    final db = openDb(dbPath);
    final titles = [for (final row in db.select('SELECT title FROM tracks ORDER BY path')) row['title']];
    expect(titles, ['Renamed', 'T2', 'T4']);
    db.close();

    // An unplugged library drive keeps its tracks (and their play counts).
    Directory(lib).renameSync('${lib}_away');
    r = scan(dbPath, covers, [lib]);
    expect(r.removed, 0);
    // Removing the folder from Settings does remove them.
    r = scan(dbPath, covers, []);
    expect(r.removed, 3);
  });

  test('albums group by album artist + album, across disc folders, with Various Artists', () {
    writeFlac(p.join(lib, 'Deep', 'CD1', '01.flac'), {'TITLE': 'a', 'ARTIST': 'Tide', 'ALBUM': 'Deep', 'DISCNUMBER': '1'});
    writeFlac(p.join(lib, 'Deep', 'CD2', '01.flac'), {'TITLE': 'b', 'ARTIST': 'Tide', 'ALBUM': 'Deep', 'DISCNUMBER': '2'});
    writeFlac(p.join(lib, 'Mix', '01.flac'), {'TITLE': 'c', 'ARTIST': 'X', 'ALBUM': 'Mix'});
    writeFlac(p.join(lib, 'Mix', '02.flac'), {'TITLE': 'd', 'ARTIST': 'Y', 'ALBUM': 'Mix'});
    scan(dbPath, covers, [lib]);
    final db = openDb(dbPath);
    final rows = db.select('SELECT title, album_artist, album_key FROM tracks ORDER BY title');
    expect(rows[0]['album_key'], rows[1]['album_key']); // CD1 + CD2 = one album
    expect(rows[2]['album_artist'], variousArtists);
    expect(rows[2]['album_key'], rows[3]['album_key']);
    db.close();
  });

  test('album grouping rules', () {
    final g = groupAlbums(const [
      GroupInput(1, r'C:\m\Blue', 'Blue', 'Ana', 'Ana', false),
      GroupInput(2, r'C:\m\Blue', 'Blue', 'Ana feat. Bo', null, false), // adopts the folder's album artist
      GroupInput(3, r'C:\m\Mix', 'Summer', 'X', null, true), // compilation flag
      GroupInput(4, r'C:\m\Mix2', 'Hits', 'X', null, false),
      GroupInput(5, r'C:\m\Mix2', 'Hits', 'Y', null, false), // several artists, no tags
      GroupInput(6, r'C:\m\Solo', 'Hits', 'Z', null, false), // same name, other artist: separate album
      GroupInput(7, r'C:\m\Solo\CD2', 'Hits', 'Z', null, false), // joins track 6 across folders
    ]);
    expect(g[2]!.$1, 'Ana');
    expect(g[1]!.$2, g[2]!.$2);
    expect(g[3]!.$1, variousArtists);
    expect(g[4]!.$1, variousArtists);
    expect(g[4]!.$2, g[5]!.$2);
    expect(g[6]!.$1, 'Z');
    expect(g[6]!.$2, isNot(g[4]!.$2));
    expect(g[6]!.$2, g[7]!.$2);
  });
}
