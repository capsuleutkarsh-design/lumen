import 'package:sqlite3/sqlite3.dart';

/// Opens (and creates) the library database. Both the UI isolate and the
/// scanner isolate open their own connection; WAL lets them work together.
Database openDb(String path) {
  final db = sqlite3.open(path);
  db.execute('''
    PRAGMA journal_mode = WAL;
    PRAGMA busy_timeout = 10000;
    PRAGMA foreign_keys = ON;
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
  ''');
  return db;
}
