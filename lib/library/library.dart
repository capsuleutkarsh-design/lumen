import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

import '../art/art_cache.dart';
import '../art/art_sources.dart';
import 'db.dart';
import 'lyrics.dart';
import 'm3u.dart';
import 'models.dart';
import 'scanner.dart';
import 'smart.dart';
import 'suggestions.dart';

class Artist {
  Artist(this.name);
  final String name;

  /// ARTISTSORT / ALBUMARTISTSORT tag when present ("Beatles, The").
  String? sortName;
  final albums = <Album>[];
  final appearsOn = <Track>[]; // tracks on other artists' albums, features included
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
  /// [cacheDir] holds the cover thumbnails (Local AppData in the app); without it they live in [dataDir].
  Library(this.dataDir, {String? cacheDir}) : coverDir = p.join(cacheDir ?? dataDir, 'covers') {
    final (d, moved) = openOrRecover(dbPath);
    db = d;
    corruptBackup = moved;
    _moveCovers(p.join(dataDir, 'covers'));
  }
  final String dataDir, coverDir;
  late final Database db;
  String get dbPath => p.join(dataDir, 'library.db');

  /// Set when library.db could not be opened at start: the damaged file was renamed
  /// to this path (never deleted) and a fresh library was started. Show it to the user.
  String? corruptBackup;

  /// Folders the last scan could not read (no access, path too long...). Their tracks are kept.
  List<String> skippedFolders = [];

  List<Track> tracks = [];
  List<Album> albums = [];
  List<Artist> artists = [];
  Map<int, Track> byId = {};
  Map<String, Album> albumByKey = {};
  Map<String, Artist> _artistByName = {};
  Set<int> favourites = {};
  List<Playlist> playlists = [];
  bool loaded = false;

  /// (done, total) while scanning, null when idle.
  final scan = ValueNotifier<(int, int)?>(null);
  String? lastScan;

  void load() {
    final rows = db.select('SELECT $trackColumns FROM tracks WHERE gone_at IS NULL AND hidden = 0');
    // A first scan shows tracks before it has grouped them: group those here meanwhile.
    final blank = db.select(
      "SELECT id, folder, album, artist, album_artist_tag, compilation, mb_album_id FROM tracks WHERE album_key = '' AND gone_at IS NULL AND hidden = 0",
    );
    final provisional = blank.isEmpty ? const <int, (String, String)>{} : groupAlbums([for (final r in blank) _groupInput(r)]);

    // Artist names. Several tag values (or an ARTISTS tag) are used as they are;
    // a single ARTIST value is split by the rules in splitArtist.
    final explicit = <int, List<String>>{};
    for (final r in db.select('SELECT track_id, name FROM track_artists WHERE explicit = 1')) {
      explicit.putIfAbsent(r['track_id'] as int, () => []).add(r['name'] as String);
    }
    // Known acts and names, built only if some credit might split.
    late final bands = {
      for (final v in rows.rows) (provisional[v[0]]?.$1 ?? v[5] as String).toLowerCase(),
      for (final v in explicit.values) ...v.map((x) => x.toLowerCase()),
    };
    late final solo = {...bands, for (final v in rows.rows) ?(v[4] as String?)?.toLowerCase()};
    const unknown = ['Unknown artist'];
    List<String> names(int id, String? artist) {
      if (explicit[id] case final v?) return v;
      if (artist == null) return unknown;
      final out = splitArtist(artist, band: (n) => bands.contains(n), solo: (n) => solo.contains(n));
      if (out.length == 1) return out;
      final seen = <String>{};
      return [
        for (final x in out)
          if (seen.add(x.toLowerCase())) x,
      ];
    }

    tracks = [
      for (final v in rows.rows) Track.fromValues(v, names(v[0] as int, v[4] as String?), provisional[v[0]]?.$2, provisional[v[0]]?.$1),
    ];
    byId = {for (final t in tracks) t.id: t};
    final groups = <String, List<Track>>{};
    for (final t in tracks) {
      groups.putIfAbsent(t.albumKey, () => []).add(t);
    }
    albums = [for (final e in groups.entries) Album(e.key, e.value..sort(compareAlbumOrder))];
    final sortKey = {for (final a in albums) a: a.sortTitle.toLowerCase()};
    albums.sort((a, b) => sortKey[a]!.compareTo(sortKey[b]!));
    albumByKey = {for (final a in albums) a.key: a};
    final byName = <String, Artist>{};
    Artist artist(String n) => byName.putIfAbsent(n.toLowerCase(), () => Artist(n));
    for (final a in albums) {
      artist(a.artist).albums.add(a);
    }
    for (final t in tracks) {
      for (final n in t.artists) {
        if (n.toLowerCase() != t.albumArtist.toLowerCase()) artist(n).appearsOn.add(t);
      }
      if (t.albumArtistSort != null) byName[t.albumArtist.toLowerCase()]?.sortName ??= t.albumArtistSort;
      if (t.artistSort != null && t.artists.length == 1) byName[t.artists.first.toLowerCase()]?.sortName ??= t.artistSort;
    }
    _artistByName = byName;
    artists = byName.values.toList()..sort((a, b) => (a.sortName ?? a.name).toLowerCase().compareTo((b.sortName ?? b.name).toLowerCase()));
    favourites = {for (final r in db.select('SELECT track_id FROM favourites')) r['track_id'] as int};
    ratings = {for (final r in db.select('SELECT id, rating FROM tracks WHERE rating > 0')) r['id'] as int: r['rating'] as int};
    lowCovers = {for (final r in db.select('SELECT cover FROM cover_quality WHERE problem IS NOT NULL')) r['cover'] as String};
    coverChoices = {
      for (final r in db.select('SELECT album_key, choice FROM album_covers')) r['album_key'] as String: r['choice'] as String,
    };
    _loadPlaylists();
    _auto = null;
    _home = null;
    _genres = null;
    _years = null;
    _composers = null;
    loaded = true;
    notifyListeners();
  }

  static GroupInput _groupInput(Row r) => GroupInput(
    r['id'] as int,
    r['folder'] as String,
    r['album'] as String,
    r['artist'] as String?,
    r['album_artist_tag'] as String?,
    r['compilation'] == 1,
    r['mb_album_id'] as String?,
  );

  void _loadPlaylists() {
    final items = <int, List<int>>{};
    for (final r in db.select('SELECT playlist_id, track_id FROM playlist_items ORDER BY playlist_id, pos')) {
      // Tracks whose file is gone stay in the table (they come back if the file does) but are not listed.
      if (byId.containsKey(r['track_id'])) items.putIfAbsent(r['playlist_id'] as int, () => []).add(r['track_id'] as int);
    }
    playlists = [
      for (final r in db.select('SELECT id, name FROM playlists ORDER BY name COLLATE NOCASE'))
        Playlist(r['id'] as int, r['name'] as String, items[r['id']] ?? []),
    ];
  }

  /// The artist page for [name]: exact, else the first artist of a credit like "Ana feat. Bo" or "Ana, Bo".
  Artist? artistNamed(String name) =>
      _artistByName[name.toLowerCase()] ?? _artistByName[splitArtist(name, solo: (_) => true).firstOrNull?.toLowerCase() ?? ''];

  // ------------------------------------------------------------ cover art

  /// Cover thumbnails the scanner found small, blocky or blurry.
  Set<String> lowCovers = {};

  /// Art key ([artKeyOf] the album key) -> the user's pick: 'original', or the key of an artwork Gleo draws ([Art.key]).
  Map<String, String> coverChoices = {};

  /// What an album shows: its own cover, unless it has none or a low-quality one, or the user
  /// picked other art (Change cover). Otherwise Gleo's art, picked by the album key from the
  /// art sources that are on (art_sources.dart).
  Art artFor(String albumKey, String? cover) {
    final choice = coverChoices[artKeyOf(albumKey)];
    if (choice != null && choice != 'original' && knownArt(choice)) return Art.drawn(choice);
    if (cover != null && (choice == 'original' || !lowCovers.contains(cover))) return Art.file(cover);
    return autoArtFor(albumKey);
  }

  /// Gleo's own pick for an album (see [artFor]).
  Art autoArtFor(String albumKey) => _autoArt[artKeyOf(albumKey)] ?? autoArt(albumKey, artSourcesOn);

  /// The automatic art of every album that shows it, picked once per load or change: albums in
  /// the order they were added, and a pack image an earlier album already shows moves on to the
  /// pack's next free one. So a library never shows a pack image twice until the pack runs out,
  /// and a new album never changes the art of older ones.
  Map<String, Art> get _autoArt => _auto ??= () {
    final on = artSourcesOn, taken = <String>{}, out = <String, Art>{};
    int order(Album x, Album y) => x.addedAt != y.addedAt ? x.addedAt.compareTo(y.addedAt) : x.key.compareTo(y.key);
    for (final a in [...albums]..sort(order)) {
      final key = artKeyOf(a.key), cover = a.cover;
      if (out.containsKey(key) || coverChoices.containsKey(key) || (cover != null && !lowCovers.contains(cover))) continue;
      final art = out[key] = freeArt(autoArt(key, on), taken);
      taken.add(art.key!);
    }
    return out;
  }();
  Map<String, Art>? _auto;

  /// Settings → Disc & covers: the art sources Gleo picks from (painterly ones by default).
  Set<String> get artSourcesOn => _sourcesOn ??= sourcesOn(setting('artSources'));
  Set<String>? _sourcesOn;
  set artSourcesOn(Set<String> ids) {
    setSetting('artSources', jsonEncode(ids.toList()));
    _sourcesOn = ids;
    _auto = null;
    notifyListeners();
  }

  /// Stores the cover picked for an album: 'original', an [Art.key], or null for automatic.
  /// Only the database changes, never the music files.
  void setCoverChoice(String albumKey, String? choice) {
    albumKey = artKeyOf(albumKey); // the same album in a moved folder keeps it
    _auto = null;
    if (choice == null) {
      db.execute('DELETE FROM album_covers WHERE album_key = ?', [albumKey]);
      coverChoices.remove(albumKey);
    } else {
      db.execute('INSERT OR REPLACE INTO album_covers(album_key, choice) VALUES(?, ?)', [albumKey, choice]);
      coverChoices[albumKey] = choice;
    }
    notifyListeners();
  }

  // ------------------------------------------------------------ browsing data (cached until the next load)

  Map<String, List<Track>>? _genres;

  /// Genre name → its tracks, A–Z. A tag "Rock; Pop" or "Rock/Pop" lists the track under both.
  Map<String, List<Track>> get genres => _genres ??= _groupBy((t) => t.genres);

  /// Albums with at least one track in [genre].
  List<Album> genreAlbums(String genre) => [
    for (final k in {for (final t in genres[genre] ?? const <Track>[]) t.albumKey}) ?albumByKey[k],
  ];

  Map<int, List<Album>>? _years;

  /// Year → albums from that year, newest year first. Albums without a year are left out.
  Map<int, List<Album>> get years {
    if (_years != null) return _years!;
    final m = <int, List<Album>>{};
    for (final a in albums) {
      if (a.year case final y?) m.putIfAbsent(y, () => []).add(a);
    }
    return _years = Map.fromEntries(m.entries.toList()..sort((a, b) => b.key.compareTo(a.key)));
  }

  Map<String, List<Track>>? _composers;

  /// Composer → their tracks, A–Z.
  Map<String, List<Track>> get composers => _composers ??= _groupBy((t) => [?t.composer]);

  /// A composer's tracks by work (WORK / TIT1 / ©wrk; the album when untagged), movements in order.
  Map<String, List<Track>> works(String composer) {
    final m = <String, List<Track>>{};
    for (final t in composers[composer] ?? const <Track>[]) {
      m.putIfAbsent(t.work ?? t.album, () => []).add(t);
    }
    for (final ts in m.values) {
      ts.sort(
        (a, b) => a.movementNo != null && b.movementNo != null && a.movementNo != b.movementNo
            ? a.movementNo!.compareTo(b.movementNo!)
            : compareAlbumOrder(a, b),
      );
    }
    return m;
  }

  /// Possible duplicates: same artist and title (ignoring case and punctuation), lengths within 2 s.
  List<List<Track>> duplicates() {
    final groups = <String, List<Track>>{};
    for (final t in tracks) {
      groups.putIfAbsent('${normalise(t.artist)}\u0000${normalise(t.title)}', () => []).add(t);
    }
    final out = <List<Track>>[];
    for (final g in groups.values.where((g) => g.length > 1)) {
      g.sort((a, b) => a.durationMs.compareTo(b.durationMs));
      var run = [g.first];
      for (final t in g.skip(1)) {
        if (t.durationMs - run.first.durationMs <= 2000) {
          run.add(t);
        } else {
          if (run.length > 1) out.add(run);
          run = [t];
        }
      }
      if (run.length > 1) out.add(run);
    }
    return out;
  }

  /// Groups tracks by the names [keys] gives (case-insensitive, first spelling wins), sorted A–Z.
  Map<String, List<Track>> _groupBy(List<String> Function(Track) keys) {
    final m = <String, (String, List<Track>)>{};
    for (final t in tracks) {
      for (final k in keys(t)) {
        m.putIfAbsent(k.toLowerCase(), () => (k, [])).$2.add(t);
      }
    }
    final sorted = m.values.toList()..sort((a, b) => a.$1.toLowerCase().compareTo(b.$1.toLowerCase()));
    return {for (final (k, ts) in sorted) k: ts};
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

  /// Points the cover paths stored under [old] at the same files in [coverDir].
  void repointCovers(String old) => db.execute('UPDATE tracks SET cover = ? || substr(cover, ?) WHERE substr(cover, 1, ?) = ?', [
    coverDir,
    old.length + 1,
    old.length,
    old,
  ]);

  /// Moves a cover cache from the old place (next to the database, 0.1.x) to [coverDir].
  void _moveCovers(String old) {
    if (p.equals(old, coverDir) || !Directory(old).existsSync()) return;
    Directory(coverDir).createSync(recursive: true);
    for (final f in Directory(old).listSync().whereType<File>()) {
      final to = p.join(coverDir, p.basename(f.path));
      try {
        if (File(to).existsSync()) {
          f.deleteSync();
        } else {
          try {
            f.renameSync(to);
          } on FileSystemException {
            f.copySync(to); // another drive
            f.deleteSync();
          }
        }
      } on FileSystemException {
        // left behind: the next scan makes the thumbnail again
      }
    }
    repointCovers(old);
    try {
      Directory(old).deleteSync(recursive: true);
    } on FileSystemException {
      // try again next start
    }
  }

  // ------------------------------------------------------------ scanning + watching

  bool _again = false;
  Future<void> rescan() async {
    if (scan.value != null) {
      _again = true;
      return;
    }
    scan.value = (0, 0);
    // A first scan of a big library shows what it has found every 500 files or 2 s.
    final first = tracks.isEmpty;
    var shown = 0;
    final since = Stopwatch()..start();
    try {
      final r = await scanInBackground(dbPath, coverDir, folders, mirror: Directory(textMirror).existsSync() ? textMirror : null, (d, t) {
        scan.value = (d, t);
        if (first && d > shown && d < t && (d - shown >= 500 || since.elapsedMilliseconds >= 2000)) {
          shown = d;
          since.reset();
          load();
        }
      });
      lastScan = r.toString();
      skippedFolders = r.skipped;
    } catch (e) {
      lastScan = 'failed: $e';
    } finally {
      scan.value = null;
    }
    load();
    if (_watching && !setEquals(_existing(), _watched)) watch();
    if (_again) {
      _again = false;
      await rescan();
    }
  }

  final _watchers = <StreamSubscription>[];
  var _watched = <String>{};
  var _watching = false;
  Timer? _debounce, _poll;

  Set<String> _existing() => {
    for (final f in folders)
      if (Directory(f).existsSync()) f,
  };

  void _soon() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 2), rescan);
  }

  /// Rescans (incrementally) a moment after anything changes in a library folder.
  /// A watcher that fails, or a folder that appears later (drive plugged in), is picked up again.
  void watch() {
    if (Platform.isAndroid) return; // no recursive watch there: the app rescans on resume and on pull-to-refresh
    _watching = true;
    for (final w in _watchers) {
      w.cancel();
    }
    _watchers.clear();
    _watched = _existing();
    for (final f in _watched) {
      void lost([_]) {
        _watched.remove(f); // re-watched after the rescan
        _soon();
      }

      _watchers.add(Directory(f).watch(recursive: true).listen((_) => _soon(), onError: lost, onDone: lost));
    }
    _poll ??= Timer.periodic(const Duration(minutes: 1), (_) {
      if (!setEquals(_existing(), _watched)) _soon();
    });
  }

  // ------------------------------------------------------------ stats + suggestions

  HomeData? _home;
  HomeData get home => _home ??= suggest(tracks, albums, playStats(), DateTime.now());

  /// Android 13+: copies of the .lrc and .cue files Gleo may not read in place, under their own full path
  /// (MainActivity.kt copies them from folders picked in Android's folder picker).
  String get textMirror => p.join(dataDir, 'saf');

  /// Plays, skips and last play per track, added up by the database.
  Map<int, PlayStat> playStats() => {
    for (final r in db.select(
      'SELECT track_id, sum(skipped = 0) n, sum(skipped) s, max(CASE WHEN skipped = 0 THEN at END) last FROM plays GROUP BY track_id',
    ))
      r['track_id'] as int: PlayStat(
        r['n'] as int,
        r['s'] as int,
        r['last'] == null ? null : DateTime.fromMillisecondsSinceEpoch(r['last'] as int),
      ),
  };

  void recordPlay(int trackId, {required bool skipped, DateTime? at}) {
    if (!byId.containsKey(trackId)) return;
    db.execute('INSERT INTO plays(track_id, at, skipped) VALUES(?, ?, ?)', [
      trackId,
      (at ?? DateTime.now()).millisecondsSinceEpoch,
      skipped ? 1 : 0,
    ]);
    _home = null;
    plays.value++;
  }

  /// Goes up by one with every play or skip recorded (smart playlists and Statistics listen to it).
  final plays = ValueNotifier(0);

  /// mpv knows the true length of files whose header did not say (e.g. streamed FLAC).
  void fixDuration(int trackId, int ms) {
    db.execute('UPDATE tracks SET duration_ms = ? WHERE id = ? AND duration_ms = 0', [ms, trackId]);
  }

  String? embeddedLyrics(int trackId) => db.select('SELECT lyrics FROM tracks WHERE id = ?', [trackId]).firstOrNull?['lyrics'] as String?;

  // ------------------------------------------------------------ hidden songs

  /// Hides songs from the library (Duplicates' "Hide from library"). Only a flag in the
  /// database: the files are never touched, and plays, favourites and playlists are kept.
  void setHidden(Iterable<int> ids, bool hidden) {
    final upd = db.prepare('UPDATE tracks SET hidden = ? WHERE id = ?');
    db.execute('BEGIN');
    for (final id in ids) {
      upd.execute([hidden ? 1 : 0, id]);
    }
    db.execute('COMMIT');
    upd.close();
    load();
  }

  List<int> get hiddenIds => [for (final r in db.select('SELECT id FROM tracks WHERE hidden = 1 AND gone_at IS NULL')) r['id'] as int];

  // ------------------------------------------------------------ smart playlists

  List<SmartPlaylist> get smartPlaylists => [
    for (final r in db.select('SELECT id, name, rules FROM smart_playlists ORDER BY created_at, id'))
      SmartPlaylist.fromRow(r['id'] as int, r['name'] as String, r['rules'] as String),
  ];

  SmartPlaylist? smartPlaylist(int id) => smartPlaylists.where((s) => s.id == id).firstOrNull;

  /// Saves [s] (id 0 makes a new one) and returns its id.
  int saveSmart(SmartPlaylist s) {
    if (s.id == 0) {
      db.execute('INSERT INTO smart_playlists(name, rules, created_at) VALUES(?, ?, ?)', [
        s.name,
        s.rulesJson,
        DateTime.now().millisecondsSinceEpoch,
      ]);
    } else {
      db.execute('UPDATE smart_playlists SET name = ?, rules = ? WHERE id = ?', [s.name, s.rulesJson, s.id]);
    }
    final id = s.id == 0 ? db.lastInsertRowId : s.id;
    notifyListeners();
    return id;
  }

  void deleteSmart(int id) {
    db.execute('DELETE FROM smart_playlists WHERE id = ?', [id]);
    notifyListeners();
  }

  /// The songs [s] matches right now.
  List<Track> smartTracks(SmartPlaylist s) => s.evaluate(tracks, SmartContext(playStats(), favourites, DateTime.now(), ratings));

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

  // ------------------------------------------------------------ ratings

  /// Star ratings by track id (1-5; not rated = missing). Only in the database: files are never changed.
  Map<int, int> ratings = {};
  int rating(int id) => ratings[id] ?? 0;

  /// Gives [ids] [stars] (0 clears the rating).
  void setRating(Iterable<int> ids, int stars) {
    final upd = db.prepare('UPDATE tracks SET rating = ? WHERE id = ?');
    db.execute('BEGIN');
    for (final id in ids) {
      upd.execute([stars, id]);
      stars == 0 ? ratings.remove(id) : ratings[id] = stars;
    }
    db.execute('COMMIT');
    upd.close();
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

  String exportM3u(int playlistId) => toM3u8([for (final id in playlists.firstWhere((x) => x.id == playlistId).trackIds) ?byId[id]]);
}
