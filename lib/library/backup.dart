// Backup & restore in one file (.gleobackup, JSON): playlists, smart playlists, favourites, ratings,
// play history, hidden songs, cover choices and settings (the EQ and its presets are in the `sound`
// setting). Songs are written with their tags, so a restore on another computer or a phone finds
// them by artist, title and length when the paths differ. Music files are never touched.
import 'dart:convert';

import 'library.dart';
import 'models.dart';

/// Settings that belong to this computer or phone (folders, devices, the window, the queue) stay out.
const _local = {'folders', 'queue', 'queue_pos', 'audio_device', 'exclusive', 'window', 'mini', 'resume', 'muted'};

/// The backup file's text.
String makeBackup(Library lib, {String app = '', String platform = ''}) {
  final db = lib.db;
  final ids = <int>{};
  List<int> keep(List<int> xs) {
    ids.addAll(xs);
    return xs;
  }

  final favourites = [for (final r in db.select('SELECT track_id, at FROM favourites')) (r['track_id'] as int, r['at'] as int)];
  final plays = [for (final r in db.select('SELECT track_id, at, skipped FROM plays')) r.values];
  final playlists = [
    for (final pl in db.select('SELECT id, name, created_at FROM playlists'))
      {
        'name': pl['name'],
        'created': pl['created_at'],
        'songs': keep([for (final r in db.select('SELECT track_id FROM playlist_items WHERE playlist_id = ? ORDER BY pos', [pl['id']])) r['track_id'] as int]),
      },
  ];
  final ratings = {for (final r in db.select('SELECT id, rating FROM tracks WHERE rating > 0')) r['id'] as int: r['rating'] as int};
  final hidden = [for (final r in db.select('SELECT id FROM tracks WHERE hidden = 1')) r['id'] as int];
  ids
    ..addAll(favourites.map((f) => f.$1))
    ..addAll(plays.map((p) => p[0] as int))
    ..addAll(ratings.keys)
    ..addAll(hidden);
  final songs = [
    for (final r in db.select('SELECT id, path, title, artist, album, duration_ms FROM tracks'))
      if (ids.contains(r['id'])) {'id': r['id'], 'path': r['path'], 'title': r['title'], 'artist': r['artist'], 'album': r['album'], 'ms': r['duration_ms']},
  ];
  return const JsonEncoder.withIndent(' ').convert({
    'gleo': 'backup',
    'version': 1,
    'app': app,
    'platform': platform,
    'made': DateTime.now().toIso8601String(),
    'songs': songs,
    'favourites': [for (final (id, at) in favourites) [id, at]],
    'ratings': [for (final e in ratings.entries) [e.key, e.value]],
    'plays': plays,
    'hidden': hidden,
    'playlists': playlists,
    'smart': [for (final r in db.select('SELECT name, rules, created_at FROM smart_playlists')) {'name': r['name'], 'rules': r['rules'], 'created': r['created_at']}],
    'covers': {for (final r in db.select('SELECT album_key, choice FROM album_covers')) r['album_key'] as String: r['choice']},
    'settings': {
      for (final r in db.select('SELECT key, value FROM settings'))
        if (!_local.contains(r['key'])) r['key'] as String: r['value'],
    },
  });
}

/// A backup read and matched to this library, before anything changes.
class RestorePlan {
  RestorePlan(this.data, this.songs);
  final Map<String, Object?> data;

  /// The backup's song id -> this library's track id, for the songs found here.
  final Map<int, int> songs;

  int get total => (data['songs'] as List).length;
  int get matched => songs.length;
  int count(String key) => (data[key] as List?)?.length ?? (data[key] as Map?)?.length ?? 0;
}

/// Reads [text] (throws a FormatException when it is not a Gleo backup) and finds its songs here:
/// the same path, else the same artist and title (ignoring case and punctuation) within 2 s of the
/// same length, preferring the same album.
RestorePlan planRestore(Library lib, String text) {
  final Object? j;
  try {
    j = jsonDecode(text);
  } on FormatException {
    throw const FormatException('This is not a Gleo backup.');
  }
  if (j is! Map<String, Object?> || j['gleo'] != 'backup' || j['songs'] is! List) throw const FormatException('This is not a Gleo backup.');
  final all = [for (final r in lib.db.select('SELECT id, path, title, artist, album, duration_ms FROM tracks WHERE gone_at IS NULL')) r];
  final byPath = {for (final r in all) (r['path'] as String).toLowerCase(): r['id'] as int};
  String key(Object? artist, Object? title) => '${normalise('${artist ?? ''}')}\u0000${normalise('$title')}';
  final byTags = <String, List<Map<String, Object?>>>{};
  for (final r in all) {
    byTags.putIfAbsent(key(r['artist'], r['title']), () => []).add(r);
  }
  final out = <int, int>{};
  for (final s in (j['songs'] as List).cast<Map<String, Object?>>()) {
    final id = s['id'] as int;
    final same = byPath['${s['path']}'.toLowerCase()];
    if (same != null) {
      out[id] = same;
      continue;
    }
    final ms = (s['ms'] as num?)?.toInt() ?? 0;
    final near = [
      for (final r in byTags[key(s['artist'], s['title'])] ?? const <Map<String, Object?>>[])
        if (((r['duration_ms'] as int) - ms).abs() <= 2000) r,
    ];
    if (near.isEmpty) continue;
    final album = normalise('${s['album'] ?? ''}');
    near.sort((a, b) {
      final x = (normalise('${a['album']}') == album ? 0 : 1) - (normalise('${b['album']}') == album ? 0 : 1);
      return x != 0 ? x : ((a['duration_ms'] as int) - ms).abs() - ((b['duration_ms'] as int) - ms).abs();
    });
    out[id] = near.first['id'] as int;
  }
  return RestorePlan(j, out);
}

/// Replaces this library's playlists, smart playlists, favourites, ratings, play history, hidden
/// songs, cover choices and the backed-up settings with the backup's, in one transaction.
void applyRestore(Library lib, RestorePlan plan) {
  final db = lib.db, j = plan.data, map = plan.songs;
  List<List<Object?>> rows(String k) => [for (final r in j[k] as List? ?? const []) (r as List).cast<Object?>()];
  db.execute('BEGIN');
  try {
    db.execute('''
      DELETE FROM playlists; DELETE FROM smart_playlists; DELETE FROM favourites; DELETE FROM plays; DELETE FROM album_covers;
      UPDATE tracks SET rating = 0 WHERE rating != 0; UPDATE tracks SET hidden = 0 WHERE hidden != 0;''');
    for (final f in rows('favourites')) {
      if (map[f[0]] case final id?) db.execute('INSERT OR IGNORE INTO favourites(track_id, at) VALUES(?, ?)', [id, f[1]]);
    }
    for (final r in rows('ratings')) {
      if (map[r[0]] case final id?) db.execute('UPDATE tracks SET rating = ? WHERE id = ?', [r[1], id]);
    }
    final play = db.prepare('INSERT INTO plays(track_id, at, skipped) VALUES(?, ?, ?)');
    for (final r in rows('plays')) {
      if (map[r[0]] case final id?) play.execute([id, r[1], r[2]]);
    }
    play.close();
    for (final h in j['hidden'] as List? ?? const []) {
      if (map[h] case final id?) db.execute('UPDATE tracks SET hidden = 1 WHERE id = ?', [id]);
    }
    for (final pl in (j['playlists'] as List? ?? const []).cast<Map<String, Object?>>()) {
      db.execute('INSERT INTO playlists(name, created_at) VALUES(?, ?)', [pl['name'], pl['created'] ?? 0]);
      final pid = db.lastInsertRowId;
      var pos = 0;
      for (final s in pl['songs'] as List? ?? const []) {
        if (map[s] case final id?) db.execute('INSERT INTO playlist_items(playlist_id, pos, track_id) VALUES(?, ?, ?)', [pid, pos++, id]);
      }
    }
    for (final s in (j['smart'] as List? ?? const []).cast<Map<String, Object?>>()) {
      db.execute('INSERT INTO smart_playlists(name, rules, created_at) VALUES(?, ?, ?)', [s['name'], s['rules'], s['created'] ?? 0]);
    }
    for (final e in (j['covers'] as Map? ?? const {}).entries) {
      db.execute('INSERT OR REPLACE INTO album_covers(album_key, choice) VALUES(?, ?)', [e.key, e.value]);
    }
    for (final e in (j['settings'] as Map? ?? const {}).entries) {
      if (!_local.contains(e.key)) lib.setSetting(e.key as String, '${e.value}');
    }
    db.execute('COMMIT');
  } catch (_) {
    db.execute('ROLLBACK');
    rethrow;
  }
  lib.load();
}
