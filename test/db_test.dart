import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:music_player/library/db.dart';
import 'package:music_player/library/library.dart';
import 'package:music_player/library/scanner.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

import 'scanner_test.dart' show writeFlac;

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('mp_db'));
  tearDown(() => tmp.deleteSync(recursive: true));

  test('a 0.1.1 database upgrades in place: ids, plays, favourites and playlists stay', () {
    final dbPath = p.join(tmp.path, 'library.db'), song = p.join(tmp.path, 'lib', 'A', '01.flac');
    writeFlac(song, {'TITLE': 'Song', 'ARTIST': 'Ana', 'ALBUM': 'Blue', 'COMPOSER': 'Bach'});
    // The 0.1.1 schema (user_version 0) with one scanned track and its history.
    final old = sqlite3.open(dbPath);
    old.execute('PRAGMA journal_mode = WAL;');
    old.execute(migrations[0]);
    old.execute(
      'INSERT INTO tracks(id, path, root, folder, mtime, size, title, artist, album, album_artist, album_key, duration_ms, codec, '
      "sample_rate, bit_depth, channels, bitrate, cover, added_at) VALUES(7, ?, ?, ?, 1, 1, 'Song', 'Ana', 'Blue', 'Ana', ?, "
      "60000, 'FLAC', 44100, 16, 2, 0, NULL, 5)",
      [song, p.join(tmp.path, 'lib'), p.dirname(song), 'ana\u0000blue'],
    );
    old.execute('INSERT INTO favourites VALUES(7, 1); INSERT INTO plays VALUES(7, 2, 0);');
    old.execute("INSERT INTO playlists VALUES(1, 'Mine', 0); INSERT INTO playlist_items VALUES(1, 0, 7);");
    old.execute("INSERT INTO settings VALUES('volume', '0.5');");
    expect(old.select('PRAGMA user_version').single.values.first, 0);
    old.close();

    final db = openDb(dbPath);
    expect(db.select('PRAGMA user_version').single.values.first, migrations.length);
    expect(db.select('SELECT id, mtime, gone_at FROM tracks').single.values, [7, 0, null]); // mtime 0: re-read once
    expect(db.select("SELECT name FROM sqlite_master WHERE name = 'playlist_items_track'"), isNotEmpty); // P2
    db.close();

    final r = scan(dbPath, p.join(tmp.path, 'covers'), [p.join(tmp.path, 'lib')]);
    expect([r.added, r.updated], [0, 1]);
    final d = openDb(dbPath);
    expect(d.select('SELECT id, composer, added_at FROM tracks').single.values, [7, 'Bach', 5]);
    expect(
      [
        for (final t in ['favourites', 'plays', 'playlist_items', 'settings']) d.select('SELECT count(*) c FROM $t').single['c'],
      ],
      [1, 1, 1, 1],
    );
    d.close();
  });

  test('C1: a corrupt library.db is renamed, never deleted, and a fresh one opens', () {
    final dbPath = p.join(tmp.path, 'library.db');
    File(dbPath).writeAsStringSync('this is not a database' * 100);
    File('$dbPath-wal').writeAsStringSync('wal');
    final lib = Library(tmp.path);
    expect(lib.corruptBackup, isNotNull);
    expect(p.basename(lib.corruptBackup!), startsWith('library.corrupt-'));
    expect(File(lib.corruptBackup!).readAsStringSync(), startsWith('this is not a database'));
    expect(File('${lib.corruptBackup}-wal').existsSync(), isTrue);
    lib.load();
    expect(lib.tracks, isEmpty);
    lib.db.close();
    // A healthy database is left alone.
    final again = Library(tmp.path);
    expect(again.corruptBackup, isNull);
    again.db.close();
  });

  test('C2: a scan that throws reports the failure; the next rescan runs', () async {
    final lib = Library(tmp.path);
    writeFlac(p.join(tmp.path, 'lib', '01.flac'), {'TITLE': 'Song'});
    lib.setSetting('folders', '["${p.join(tmp.path, 'lib').replaceAll(r'\', r'\\')}"]');
    File(lib.coverDir).writeAsStringSync('x'); // the scanner cannot make its cover folder
    await expectLater(scanInBackground(lib.dbPath, lib.coverDir, lib.folders, (_, _) {}), throwsA(isA<ScanError>()));
    await lib.rescan().timeout(const Duration(seconds: 20));
    expect(lib.lastScan, startsWith('failed: '));
    expect(lib.scan.value, isNull);
    File(lib.coverDir).deleteSync();
    await lib.rescan().timeout(const Duration(seconds: 20));
    expect(lib.lastScan, startsWith('added 1'));
    expect(lib.tracks.single.title, 'Song');
    lib.db.close();
  });

  test('the 0.1.x cover cache moves to the cache folder and the rows follow', () {
    final data = p.join(tmp.path, 'data'), cache = p.join(tmp.path, 'cache');
    final oldCover = p.join(data, 'covers', 'abc.jpg');
    File(oldCover)
      ..createSync(recursive: true)
      ..writeAsStringSync('jpg');
    final db = openDb(p.join(data, 'library.db'));
    db.execute(
      'INSERT INTO tracks(path, root, folder, mtime, size, title, album, duration_ms, codec, sample_rate, bit_depth, channels, bitrate, cover, added_at) '
      "VALUES('x', 'r', 'f', 0, 0, 't', 'a', 0, 'FLAC', 0, 0, 0, 0, ?, 0)",
      [oldCover],
    );
    db.close();
    final lib = Library(data, cacheDir: cache);
    final moved = p.join(cache, 'covers', 'abc.jpg');
    expect(File(moved).readAsStringSync(), 'jpg');
    expect(Directory(p.join(data, 'covers')).existsSync(), isFalse);
    expect(lib.db.select('SELECT cover FROM tracks').single['cover'], moved);
    lib.db.close();
  });
}
