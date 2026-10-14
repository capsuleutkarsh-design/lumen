import 'dart:io';

import 'package:sqlite3/sqlite3.dart';

/// Schema changes, in order. Entry i brings a database from version i to i + 1
/// (`PRAGMA user_version`). Never edit a shipped entry: add a new one.
const migrations = [
  // 1: the 0.1.x schema. 0.1.x databases have user_version 0 and these tables already.
  '''
    CREATE TABLE IF NOT EXISTS tracks(
      id INTEGER PRIMARY KEY,
      path TEXT NOT NULL UNIQUE,
      root TEXT NOT NULL,
      folder TEXT NOT NULL,
      mtime INTEGER NOT NULL,
      size INTEGER NOT NULL,
      title TEXT NOT NULL,
      artist TEXT,
      album_artist_tag TEXT,
      compilation INTEGER NOT NULL DEFAULT 0,
      album TEXT NOT NULL,
      album_artist TEXT NOT NULL DEFAULT '',
      album_key TEXT NOT NULL DEFAULT '',
      track_no INTEGER,
      disc_no INTEGER,
      year INTEGER,
      genre TEXT,
      duration_ms INTEGER NOT NULL,
      codec TEXT NOT NULL,
      sample_rate INTEGER NOT NULL,
      bit_depth INTEGER NOT NULL,
      channels INTEGER NOT NULL,
      bitrate INTEGER NOT NULL,
      cover TEXT,
      lyrics TEXT,
      added_at INTEGER NOT NULL
    );
    CREATE TABLE IF NOT EXISTS plays(
      track_id INTEGER NOT NULL REFERENCES tracks(id) ON DELETE CASCADE,
      at INTEGER NOT NULL,
      skipped INTEGER NOT NULL
    );
    CREATE INDEX IF NOT EXISTS plays_track ON plays(track_id);
    CREATE TABLE IF NOT EXISTS favourites(
      track_id INTEGER PRIMARY KEY REFERENCES tracks(id) ON DELETE CASCADE,
      at INTEGER NOT NULL
    );
    CREATE TABLE IF NOT EXISTS playlists(
      id INTEGER PRIMARY KEY,
      name TEXT NOT NULL,
      created_at INTEGER NOT NULL
    );
    CREATE TABLE IF NOT EXISTS playlist_items(
      playlist_id INTEGER NOT NULL REFERENCES playlists(id) ON DELETE CASCADE,
      pos INTEGER NOT NULL,
      track_id INTEGER NOT NULL REFERENCES tracks(id) ON DELETE CASCADE
    );
    CREATE TABLE IF NOT EXISTS settings(key TEXT PRIMARY KEY, value TEXT NOT NULL);
  ''',
  // 2: 0.2.0. New tags; soft delete (gone_at) so renamed, moved or re-added files keep
  // their id; all artist values; indexes. mtime = 0 makes the next scan re-read every
  // file once for the new tags (ids, plays, favourites and playlists stay).
  '''
    ALTER TABLE tracks ADD COLUMN composer TEXT;
    ALTER TABLE tracks ADD COLUMN work TEXT;
    ALTER TABLE tracks ADD COLUMN movement TEXT;
    ALTER TABLE tracks ADD COLUMN movement_no INTEGER;
    ALTER TABLE tracks ADD COLUMN artist_sort TEXT;
    ALTER TABLE tracks ADD COLUMN album_artist_sort TEXT;
    ALTER TABLE tracks ADD COLUMN album_sort TEXT;
    ALTER TABLE tracks ADD COLUMN mb_album_id TEXT;
    ALTER TABLE tracks ADD COLUMN rg_track_gain REAL;
    ALTER TABLE tracks ADD COLUMN rg_track_peak REAL;
    ALTER TABLE tracks ADD COLUMN rg_album_gain REAL;
    ALTER TABLE tracks ADD COLUMN rg_album_peak REAL;
    ALTER TABLE tracks ADD COLUMN embedded_cover INTEGER NOT NULL DEFAULT 0;
    ALTER TABLE tracks ADD COLUMN gone_at INTEGER;
    CREATE TABLE track_artists(
      track_id INTEGER NOT NULL REFERENCES tracks(id) ON DELETE CASCADE,
      name TEXT NOT NULL,
      explicit INTEGER NOT NULL
    );
    CREATE INDEX track_artists_track ON track_artists(track_id);
    CREATE INDEX playlist_items_track ON playlist_items(track_id);
    CREATE INDEX playlist_items_order ON playlist_items(playlist_id, pos);
    CREATE INDEX plays_stats ON plays(track_id, skipped, at);
    UPDATE tracks SET mtime = 0;
  ''',
  // 3: 0.2.0 wave 2. "Hide from library" (a flag; the file is never touched) and smart
  // playlists (rules as JSON, see smart.dart), with four ready-made ones.
  '''
    ALTER TABLE tracks ADD COLUMN hidden INTEGER NOT NULL DEFAULT 0;
    CREATE TABLE smart_playlists(
      id INTEGER PRIMARY KEY,
      name TEXT NOT NULL,
      rules TEXT NOT NULL,
      created_at INTEGER NOT NULL
    );
    INSERT INTO smart_playlists(name, rules, created_at) VALUES
      ('Recently added', '{"match":"all","rules":[{"f":"added","a":30}],"sort":"added","limit":200}', 1),
      ('Most played', '{"match":"all","rules":[{"f":"plays","a":0}],"sort":"plays","limit":50}', 2),
      ('Never played', '{"match":"all","rules":[{"f":"never"}],"sort":"added","limit":0}', 3),
      ('Hi-Res', '{"match":"any","rules":[{"f":"rate","a":88200},{"f":"bits","a":24}],"sort":"artist","limit":0}', 4);
  ''',
];

/// Opens (and creates or upgrades) the library database. Both the UI isolate and
/// the scanner isolate open their own connection; WAL lets them work together.
Database openDb(String path) {
  final db = sqlite3.open(path);
  try {
    db.execute('''
      PRAGMA journal_mode = WAL;
      PRAGMA busy_timeout = 10000;
      PRAGMA foreign_keys = ON;
    ''');
    if (_version(db) < migrations.length) {
      db.execute('BEGIN IMMEDIATE'); // one connection migrates; another waits, then sees the new version
      try {
        for (var v = _version(db); v < migrations.length; v++) {
          db.execute(migrations[v]);
          db.execute('PRAGMA user_version = ${v + 1}');
        }
        db.execute('COMMIT');
      } catch (_) {
        db.execute('ROLLBACK');
        rethrow;
      }
    }
    return db;
  } catch (_) {
    db.close();
    rethrow;
  }
}

int _version(Database db) => db.select('PRAGMA user_version').single.values.first as int;

/// Opens the library database. If the file is corrupt, renames it (and its -wal/-shm)
/// to `library.corrupt-<date>.db`, never deleting it, and opens a fresh one.
/// Returns the database and the renamed file's path (null when nothing was wrong).
(Database, String?) openOrRecover(String path) {
  // Not an SQLite file at all: move it before SQLite opens it (closing would delete its -wal).
  final f = File(path);
  final notDb = f.existsSync() && f.lengthSync() > 0 && !_header(f);
  if (!notDb) {
    try {
      return (openDb(path), null);
    } on SqliteException catch (e) {
      // SQLITE_CORRUPT (11), SQLITE_NOTADB (26). Anything else (e.g. busy) is not ours to fix.
      if (e.resultCode != 11 && e.resultCode != 26) rethrow;
    }
  }
  final stamp = DateTime.now().toIso8601String().substring(0, 19).replaceAll(':', '-');
  final dot = path.lastIndexOf('.');
  final moved = '${path.substring(0, dot)}.corrupt-$stamp${path.substring(dot)}';
  for (final s in ['', '-wal', '-shm']) {
    if (File('$path$s').existsSync()) File('$path$s').renameSync('$moved$s');
  }
  return (openDb(path), moved);
}

bool _header(File f) {
  final r = f.openSync();
  try {
    return String.fromCharCodes(r.readSync(16)) == 'SQLite format 3\u0000';
  } finally {
    r.closeSync();
  }
}
