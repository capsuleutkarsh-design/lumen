import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

import 'db.dart';
import 'lyrics.dart';
import 'm3u.dart';
import 'models.dart';
import 'scanner.dart';
import 'suggestions.dart';

class Artist {
  Artist(this.name);
  final String name;
  final albums = <Album>[];
  final appearsOn = <Track>[]; // tracks on other artists' albums
  String? get cover =>
      albums.map((a) => a.cover).whereType<String>().firstOrNull ?? appearsOn.map((t) => t.cover).whereType<String>().firstOrNull;
}

class Playlist {
  Playlist(this.id, this.name, this.trackIds);
  final int id;
  final String name;
  final List<int> trackIds;
}

/// The library in memory (reloaded after each scan) plus the database for
/// stats, favourites, playlists and settings.
/// ponytail: everything in memory; fine to ~100k tracks, page from SQL beyond that.
class Library extends ChangeNotifier {
  Library(this.dataDir) : db = openDb(p.join(dataDir, 'library.db'));
  final String dataDir;
  final Database db;
  String get dbPath => p.join(dataDir, 'library.db');
  String get coverDir => p.join(dataDir, 'covers');

  List<Track> tracks = [];
  List<Album> albums = [];
  List<Artist> artists = [];
  Map<int, Track> byId = {};
  Map<String, Album> albumByKey = {};
  Set<int> favourites = {};
  List<Playlist> playlists = [];
  bool loaded = false;

  /// (done, total) while scanning, null when idle.
  final scan = ValueNotifier<(int, int)?>(null);
  String? lastScan;

  void load() {
    tracks = [for (final r in db.select('SELECT * FROM tracks')) Track.fromRow(r)];
    byId = {for (final t in tracks) t.id: t};
    final groups = <String, List<Track>>{};
    for (final t in tracks) {
      groups.putIfAbsent(t.albumKey, () => []).add(t);
    }
    albums = [for (final e in groups.entries) Album(e.key, e.value..sort(compareAlbumOrder))]
      ..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
    albumByKey = {for (final a in albums) a.key: a};
    final byName = <String, Artist>{};
    Artist artist(String n) => byName.putIfAbsent(n.toLowerCase(), () => Artist(n));
    for (final a in albums) {
      artist(a.artist).albums.add(a);
    }
    for (final t in tracks) {
      if (t.artist.toLowerCase() != t.albumArtist.toLowerCase()) artist(t.artist).appearsOn.add(t);
    }
    artists = byName.values.toList()..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    favourites = {for (final r in db.select('SELECT track_id FROM favourites')) r['track_id'] as int};
    _loadPlaylists();
    _home = null;
    loaded = true;
    notifyListeners();
  }

  void _loadPlaylists() {
    final items = <int, List<int>>{};
    for (final r in db.select('SELECT playlist_id, track_id FROM playlist_items ORDER BY playlist_id, pos')) {
      items.putIfAbsent(r['playlist_id'] as int, () => []).add(r['track_id'] as int);
    }
    playlists = [
      for (final r in db.select('SELECT id, name FROM playlists ORDER BY name COLLATE NOCASE'))
        Playlist(r['id'] as int, r['name'] as String, items[r['id']] ?? []),
    ];
  }

  // ------------------------------------------------------------ settings

  String? setting(String key) => db.select('SELECT value FROM settings WHERE key = ?', [key]).firstOrNull?['value'] as String?;
  void setSetting(String key, String value) =>
      db.execute('INSERT INTO settings(key, value) VALUES(?, ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value', [key, value]);

  List<String> get folders => (jsonDecode(setting('folders') ?? '[]') as List).cast<String>();
  set folders(List<String> v) {
    setSetting('folders', jsonEncode(v));
    watch();
    rescan();
    notifyListeners();
  }

  // ------------------------------------------------------------ scanning + watching

  bool _again = false;
  Future<void> rescan() async {
    if (scan.value != null) {
      _again = true;
      return;
    }
    scan.value = (0, 0);
    try {
      final r = await scanInBackground(dbPath, coverDir, folders, (d, t) => scan.value = (d, t));
      lastScan = r.toString();
      load();
    } finally {
      scan.value = null;
    }
    if (_again) {
      _again = false;
      await rescan();
    }
  }

  final _watchers = <StreamSubscription>[];
  Timer? _debounce;

  /// Rescans (incrementally) a moment after anything changes in a library folder.
  void watch() {
    for (final w in _watchers) {
      w.cancel();
    }
    _watchers.clear();
    for (final f in folders) {
      if (!Directory(f).existsSync()) continue;
      _watchers.add(
        Directory(f).watch(recursive: true).listen((_) {
          _debounce?.cancel();
          _debounce = Timer(const Duration(seconds: 2), rescan);
        }, onError: (_) {}),
      );
    }
  }

  // ------------------------------------------------------------ stats + suggestions

  HomeData? _home;
  HomeData get home => _home ??= suggest(tracks, albums, playEvents(), DateTime.now());

  List<PlayEvent> playEvents() => [
    for (final r in db.select('SELECT track_id, at, skipped FROM plays'))
      PlayEvent(r['track_id'] as int, DateTime.fromMillisecondsSinceEpoch(r['at'] as int), r['skipped'] == 1),
  ];

  void recordPlay(int trackId, {required bool skipped, DateTime? at}) {
    if (!byId.containsKey(trackId)) return;
    db.execute('INSERT INTO plays(track_id, at, skipped) VALUES(?, ?, ?)', [
      trackId,
      (at ?? DateTime.now()).millisecondsSinceEpoch,
      skipped ? 1 : 0,
    ]);
    _home = null;
  }

  /// mpv knows the true length of files whose header did not say (e.g. streamed FLAC).
  void fixDuration(int trackId, int ms) {
    db.execute('UPDATE tracks SET duration_ms = ? WHERE id = ? AND duration_ms = 0', [ms, trackId]);
  }

  String? embeddedLyrics(int trackId) => db.select('SELECT lyrics FROM tracks WHERE id = ?', [trackId]).firstOrNull?['lyrics'] as String?;

  // ------------------------------------------------------------ favourites

  bool isFavourite(int id) => favourites.contains(id);
  void toggleFavourite(int id) {
    if (favourites.remove(id)) {
      db.execute('DELETE FROM favourites WHERE track_id = ?', [id]);
    } else {
      favourites.add(id);
      db.execute('INSERT OR IGNORE INTO favourites(track_id, at) VALUES(?, ?)', [id, DateTime.now().millisecondsSinceEpoch]);
    }
    notifyListeners();
  }

  List<Track> get favouriteTracks => [for (final r in db.select('SELECT track_id FROM favourites ORDER BY at DESC')) ?byId[r['track_id']]];

  // ------------------------------------------------------------ playlists

  int createPlaylist(String name, [List<int> trackIds = const []]) {
    db.execute('INSERT INTO playlists(name, created_at) VALUES(?, ?)', [name, DateTime.now().millisecondsSinceEpoch]);
    final id = db.lastInsertRowId;
    setPlaylistTracks(id, trackIds);
    return id;
  }

  void renamePlaylist(int id, String name) {
    db.execute('UPDATE playlists SET name = ? WHERE id = ?', [name, id]);
    _loadPlaylists();
    notifyListeners();
  }

  void deletePlaylist(int id) {
    db.execute('DELETE FROM playlists WHERE id = ?', [id]);
    _loadPlaylists();
    notifyListeners();
  }

  void addToPlaylist(int id, List<int> trackIds) =>
      setPlaylistTracks(id, [...playlists.firstWhere((x) => x.id == id).trackIds, ...trackIds]);

  /// Replaces the playlist's order (used for add, reorder and remove).
  void setPlaylistTracks(int id, List<int> trackIds) {
    db.execute('BEGIN');
    db.execute('DELETE FROM playlist_items WHERE playlist_id = ?', [id]);
    final ins = db.prepare('INSERT INTO playlist_items(playlist_id, pos, track_id) VALUES(?, ?, ?)');
    for (var i = 0; i < trackIds.length; i++) {
      ins.execute([id, i, trackIds[i]]);
    }
    ins.close();
    db.execute('COMMIT');
    _loadPlaylists();
    notifyListeners();
  }

  /// Imports an M3U/M3U8 file; returns (playlist id, tracks not found in the library).
  (int, int) importM3u(String file) {
    final byPath = {for (final t in tracks) t.path.toLowerCase(): t.id};
    final paths = parseM3u(readText(file), p.dirname(file));
    final ids = [for (final x in paths) ?byPath[x.toLowerCase()]];
    return (createPlaylist(p.basenameWithoutExtension(file), ids), paths.length - ids.length);
  }

  void exportM3u(int playlistId, String file) {
    final pl = playlists.firstWhere((x) => x.id == playlistId);
    File(file).writeAsStringSync(toM3u8([for (final id in pl.trackIds) ?byId[id]]));
  }
}
