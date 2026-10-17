import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:gleo/library/db.dart';
import 'package:gleo/library/models.dart';
import 'package:gleo/library/scanner.dart';
import 'package:path/path.dart' as p;

/// A header-only FLAC file (STREAMINFO + Vorbis comments + an optional front cover): enough for the tag reader.
/// A value with NUL in it becomes several values of that field.
void writeFlac(String path, Map<String, String> tags, {int seconds = 60, List<int>? picture}) {
  final info = ByteData(34)
    ..setUint16(0, 4096)
    ..setUint16(2, 4096);
  final rate = 44100, samples = rate * seconds;
  info.setUint64(10, (rate << 44) | (1 << 41) | (15 << 36) | samples); // stereo, 16-bit
  final vc = BytesBuilder();
  void u32le(int v) => vc.add((ByteData(4)..setUint32(0, v, Endian.little)).buffer.asUint8List());
  final fields = [
    for (final e in tags.entries)
      for (final v in e.value.split('\u0000')) '${e.key}=$v',
  ];
  u32le(0);
  u32le(fields.length);
  for (final f in fields) {
    final s = utf8.encode(f);
    u32le(s.length);
    vc.add(s);
  }
  final body = vc.toBytes();
  List<int> u32(int v) => [v >> 24, (v >> 16) & 0xFF, (v >> 8) & 0xFF, v & 0xFF];
  final pic = picture == null
      ? null
      : [...u32(3), ...u32(10), ...ascii.encode('image/jpeg'), ...u32(0), ...List.filled(16, 0), ...u32(picture.length), ...picture];
  final out = BytesBuilder()
    ..add(ascii.encode('fLaC'))
    ..add([0, 0, 0, 34])
    ..add(info.buffer.asUint8List());
  if (pic != null) out.add([6, pic.length >> 16, (pic.length >> 8) & 0xFF, pic.length & 0xFF, ...pic]);
  out
    ..add([0x84, body.length >> 16, (body.length >> 8) & 0xFF, body.length & 0xFF])
    ..add(body);
  File(path)
    ..createSync(recursive: true)
    ..writeAsBytesSync(out.toBytes());
}

/// A small JPEG of one colour.
List<int> jpeg(int shade, {int size = 8}) => img.encodeJpg(img.Image(width: size, height: size)..clear(img.ColorRgb8(shade, shade, shade)));

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

  List<Object?> col(String sql) {
    final db = openDb(dbPath);
    final v = [for (final r in db.select(sql)) r.values.length == 1 ? r.values.first : r.values];
    db.close();
    return v;
  }

  test('rescan reads only new or changed files and marks missing ones gone', () {
    for (var i = 1; i <= 3; i++) {
      writeFlac(p.join(lib, 'A', '0$i.flac'), {'TITLE': 'T$i', 'ARTIST': 'Ana', 'ALBUM': 'Blue', 'TRACKNUMBER': '$i'});
    }
    var r = scan(dbPath, covers, [lib]);
    expect([r.added, r.updated, r.removed, r.unchanged], [3, 0, 0, 0]);
    expect(col('SELECT added_at = mtime FROM tracks'), [1, 1, 1]); // "Recently added" after a first scan: the files' own dates

    r = scan(dbPath, covers, [lib]);
    expect([r.added, r.updated, r.removed, r.unchanged], [0, 0, 0, 3]);
    expect(r.changed, isFalse); // nothing to reload

    // Change one (new tags, newer time), add one, delete one.
    final changed = File(p.join(lib, 'A', '01.flac'));
    writeFlac(changed.path, {'TITLE': 'Renamed', 'ARTIST': 'Ana', 'ALBUM': 'Blue', 'TRACKNUMBER': '1'}, seconds: 61);
    changed.setLastModifiedSync(DateTime.now().add(const Duration(minutes: 1)));
    writeFlac(p.join(lib, 'A', '04.flac'), {'TITLE': 'T4', 'ARTIST': 'Ana', 'ALBUM': 'Blue'});
    File(p.join(lib, 'A', '03.flac')).deleteSync();
    r = scan(dbPath, covers, [lib]);
    expect([r.added, r.updated, r.removed, r.unchanged], [1, 1, 1, 1]);
    expect(r.changed, isTrue);
    expect(col('SELECT title FROM tracks WHERE gone_at IS NULL ORDER BY path'), ['Renamed', 'T2', 'T4']);

    // An unplugged library drive keeps its tracks (and their play counts).
    Directory(lib).renameSync('${lib}_away');
    r = scan(dbPath, covers, [lib]);
    expect(r.removed, 0);
    // Removing the folder from Settings does remove them.
    r = scan(dbPath, covers, []);
    expect(r.removed, 3);
  });

  test('D1: rename, move and re-adding a folder keep the id, favourite, plays and playlist entry', () {
    writeFlac(p.join(lib, 'A', '01.flac'), {'TITLE': 'Song', 'ARTIST': 'Ana', 'ALBUM': 'Blue'});
    scan(dbPath, covers, [lib]);
    final id = col('SELECT id FROM tracks').single;
    final db = openDb(dbPath);
    db.execute('INSERT INTO favourites(track_id, at) VALUES(?, 0)', [id]);
    db.execute('INSERT INTO plays(track_id, at, skipped) VALUES(?, 0, 0), (?, 1, 0)', [id, id]);
    db.execute("INSERT INTO playlists(id, name, created_at) VALUES(1, 'Mine', 0)");
    db.execute('INSERT INTO playlist_items(playlist_id, pos, track_id) VALUES(1, 0, ?)', [id]);
    db.close();
    List<Object?> state() => [
      col('SELECT id FROM tracks WHERE gone_at IS NULL'),
      for (final t in ['favourites', 'plays', 'playlist_items']) col('SELECT count(*) FROM $t').single,
    ];

    File(p.join(lib, 'A', '01.flac')).renameSync(p.join(lib, 'A', '01 Song.flac'));
    var r = scan(dbPath, covers, [lib]);
    expect([r.moved, r.added, r.removed], [1, 0, 0]);
    expect(state(), [
      [id],
      1,
      2,
      1,
    ]);

    Directory(p.join(lib, 'B')).createSync();
    File(p.join(lib, 'A', '01 Song.flac')).renameSync(p.join(lib, 'B', '01 Song.flac'));
    r = scan(dbPath, covers, [lib]);
    expect(r.moved, 1);
    expect(state(), [
      [id],
      1,
      2,
      1,
    ]);
    expect(col('SELECT folder FROM tracks').single, p.join(lib, 'B'));

    // Folder removed from Settings, then added again (also under a new name).
    scan(dbPath, covers, []);
    expect(col('SELECT count(*) FROM tracks WHERE gone_at IS NULL').single, 0);
    Directory(lib).renameSync('${lib}2');
    r = scan(dbPath, covers, ['${lib}2']);
    expect([r.moved, r.added], [1, 0]);
    expect(state(), [
      [id],
      1,
      2,
      1,
    ]);
  });

  test('D2 + W13: a folder that cannot be read keeps its tracks and is reported', () {
    writeFlac(p.join(lib, 'A', '01.flac'), {'TITLE': 'Song', 'ARTIST': 'Ana', 'ALBUM': 'Blue'});
    writeFlac(p.join(lib, 'B', '01.flac'), {'TITLE': 'Other', 'ARTIST': 'Bo', 'ALBUM': 'Red'});
    scan(dbPath, covers, [lib]);
    final user = Platform.environment['USERNAME']!;
    final locked = p.join(lib, 'A');
    expect(Process.runSync('icacls', [locked, '/deny', '$user:(RX)']).exitCode, 0);
    try {
      final r = scan(dbPath, covers, [lib]);
      expect(r.removed, 0);
      expect(r.skipped, [locked]);
      expect(col('SELECT count(*) FROM tracks WHERE gone_at IS NULL').single, 2);
    } finally {
      Process.runSync('icacls', [locked, '/remove:d', user]);
    }
  });

  test('W12: junctions are followed once; a junction loop is harmless; nested folders count once', () {
    writeFlac(p.join(tmp.path, 'elsewhere', '01.flac'), {'TITLE': 'Linked', 'ARTIST': 'Ana', 'ALBUM': 'L'});
    writeFlac(p.join(lib, 'A', '01.flac'), {'TITLE': 'Plain', 'ARTIST': 'Ana', 'ALBUM': 'Blue'});
    expect(Process.runSync('cmd', ['/c', 'mklink', '/J', p.join(lib, 'Linked'), p.join(tmp.path, 'elsewhere')]).exitCode, 0);
    expect(Process.runSync('cmd', ['/c', 'mklink', '/J', p.join(lib, 'A', 'loop'), lib]).exitCode, 0);
    try {
      final r = scan(dbPath, covers, [lib, p.join(lib, 'A')]);
      expect(r.added, 2);
      expect(col('SELECT title FROM tracks ORDER BY title'), ['Linked', 'Plain']);
    } finally {
      Process.runSync('cmd', ['/c', 'rmdir', p.join(lib, 'Linked')]);
      Process.runSync('cmd', ['/c', 'rmdir', p.join(lib, 'A', 'loop')]);
    }
  });

  test('albums group by album artist + album, across disc folders, with Various Artists', () {
    writeFlac(p.join(lib, 'Deep', 'CD1', '01.flac'), {'TITLE': 'a', 'ARTIST': 'Tide', 'ALBUM': 'Deep', 'DISCNUMBER': '1'});
    writeFlac(p.join(lib, 'Deep', 'CD2', '01.flac'), {'TITLE': 'b', 'ARTIST': 'Tide', 'ALBUM': 'Deep', 'DISCNUMBER': '2'});
    writeFlac(p.join(lib, 'Mix', '01.flac'), {'TITLE': 'c', 'ARTIST': 'X', 'ALBUM': 'Mix'});
    writeFlac(p.join(lib, 'Mix', '02.flac'), {'TITLE': 'd', 'ARTIST': 'Y', 'ALBUM': 'Mix'});
    // W2: untagged CD1 folders of two albums stay apart and take the album folder's name.
    writeFlac(p.join(lib, 'Xa', 'CD1', '01.flac'), {'TITLE': 'e'});
    writeFlac(p.join(lib, 'Ya', 'CD1', '01.flac'), {'TITLE': 'f'});
    scan(dbPath, covers, [lib]);
    final rows = col('SELECT title, album, album_artist, album_key FROM tracks ORDER BY title').cast<List<Object?>>();
    expect(rows[0][3], rows[1][3]); // CD1 + CD2 = one album
    expect(rows[2][2], variousArtists);
    expect(rows[2][3], rows[3][3]);
    expect([rows[4][1], rows[5][1]], ['Xa', 'Ya']);
    expect(rows[4][3], isNot(rows[5][3]));
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

  test('W1 + W2: a guest track keeps a solo album; same-named albums in other folders stay apart; MusicBrainz ids join', () {
    final g = groupAlbums(const [
      GroupInput(1, r'C:\m\Ana\Blue', 'Blue', 'Ana', null, false),
      GroupInput(2, r'C:\m\Ana\Blue', 'Blue', 'Ana', null, false),
      GroupInput(3, r'C:\m\Ana\Blue', 'Blue', 'Bo & Cy', null, false),
      GroupInput(4, r'C:\m\Queen\Greatest Hits (1981)', 'Greatest Hits', 'Queen', 'Queen', false),
      GroupInput(5, r'C:\m\Queen\Greatest Hits II (1991)', 'Greatest Hits', 'Queen', 'Queen', false),
      GroupInput(6, r'C:\m\Live\Disc 1', 'Live', 'Ana', null, false, 'mb-1'),
      GroupInput(7, r'C:\m\Elsewhere', 'Live', 'Ana', null, false, 'mb-1'),
      GroupInput(8, r'C:\m\Ana\Album (Disc 2)', 'Album', 'Ana', null, false),
      GroupInput(9, r'C:\m\Ana\Album (Disc 1)', 'Album', 'Ana', null, false),
    ]);
    expect([g[1]!.$1, g[3]!.$1], ['Ana', 'Ana']);
    expect(g[4]!.$2, isNot(g[5]!.$2));
    expect(g[6]!.$2, g[7]!.$2);
    expect(g[8]!.$2, g[9]!.$2);
  });

  test('W11: tracks committed but never grouped are grouped by the next scan', () {
    writeFlac(p.join(lib, 'A', '01.flac'), {'TITLE': 'T', 'ARTIST': 'Ana', 'ALBUM': 'Blue'});
    scan(dbPath, covers, [lib]);
    final db = openDb(dbPath);
    db.execute("UPDATE tracks SET album_artist = '', album_key = ''");
    db.close();
    scan(dbPath, covers, [lib]);
    expect(col('SELECT album_artist FROM tracks').single, 'Ana');
  });

  test('W10: folder art added or changed later is picked up; AlbumArt, Artwork and lone images count; orphans are cleaned', () {
    writeFlac(p.join(lib, 'A', '01.flac'), {'TITLE': 'a', 'ALBUM': 'A'});
    writeFlac(p.join(lib, 'B', '01.flac'), {'TITLE': 'b', 'ALBUM': 'B'});
    writeFlac(p.join(lib, 'C', '01.flac'), {'TITLE': 'c', 'ALBUM': 'C'});
    writeFlac(p.join(lib, 'D', '01.flac'), {'TITLE': 'd', 'ALBUM': 'D'});
    writeFlac(p.join(lib, 'E', '01.flac'), {'TITLE': 'e', 'ALBUM': 'E'}, picture: jpeg(50));
    scan(dbPath, covers, [lib]);
    expect(col('SELECT cover IS NULL FROM tracks ORDER BY title'), [1, 1, 1, 1, 0]);

    File(p.join(lib, 'A', 'cover.jpg')).writeAsBytesSync(jpeg(100));
    File(p.join(lib, 'B', 'AlbumArt_{X}_Large.jpg')).writeAsBytesSync(jpeg(110));
    File(p.join(lib, 'C', 'Artwork', 'back.jpg'))
      ..createSync(recursive: true)
      ..writeAsBytesSync(jpeg(120));
    File(p.join(lib, 'C', 'Artwork', 'front.jpg')).writeAsBytesSync(jpeg(130));
    File(p.join(lib, 'D', 'scan 001.png')).writeAsBytesSync(img.encodePng(img.Image(width: 4, height: 4)));
    File(p.join(lib, 'E', 'folder.jpg')).writeAsBytesSync(jpeg(140)); // embedded art wins
    expect(scan(dbPath, covers, [lib]).changed, isTrue); // new covers only: still a change to show
    final first = col('SELECT cover FROM tracks ORDER BY title');
    expect(first.every((c) => c != null), isTrue);

    // A changed image (new modified time) gives a new thumbnail; the old one becomes an orphan.
    File(p.join(lib, 'A', 'cover.jpg'))
      ..writeAsBytesSync(jpeg(200))
      ..setLastModifiedSync(DateTime.now().add(const Duration(minutes: 1)));
    File(first[0]! as String).setLastModifiedSync(DateTime.now().subtract(const Duration(hours: 1)));
    scan(dbPath, covers, [lib]);
    final second = col('SELECT cover FROM tracks ORDER BY title');
    expect(second[0], isNot(first[0]));
    expect(second.skip(1), first.skip(1));
    expect(File(first[0]! as String).existsSync(), isFalse);
  });

  test('C2: a scan that throws in the isolate fails fast instead of hanging', () async {
    writeFlac(p.join(lib, 'A', '01.flac'), {'TITLE': 'Song'});
    File(covers).writeAsStringSync('x'); // the cover folder cannot be made
    await expectLater(scanInBackground(dbPath, covers, [lib], (_, _) {}).timeout(const Duration(seconds: 20)), throwsA(isA<ScanError>()));
  });
}
