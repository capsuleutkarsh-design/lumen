import 'dart:ffi';
import 'dart:io';
import 'dart:math' show max;
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

import '../art/cover_quality.dart';
import 'cue.dart';
import 'db.dart';
import 'lyrics.dart' show readText;
import 'models.dart';
import 'tags.dart';

class ScanResult {
  int added = 0, updated = 0, moved = 0, removed = 0, unchanged = 0;

  /// Whether the library has anything new to show (songs, covers): without it nothing needs reloading.
  bool changed = false;

  /// Folders that could not be read (no access, path too long...). Their tracks are kept.
  List<String> skipped = [];
  @override
  String toString() =>
      'added $added, updated $updated, moved $moved, removed $removed, unchanged $unchanged'
      '${skipped.isEmpty ? '' : ', ${skipped.length} folders skipped'}';
}

class ScanError implements Exception {
  ScanError(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Scans in a background isolate so the UI never waits. [onProgress] gets
/// (done, total) for files that need reading, after each short commit.
/// Throws [ScanError] if the scan fails or the isolate dies.
/// [mirror]: Android 13+ copies of .cue files Gleo may not read in place (see MainActivity.kt).
Future<ScanResult> scanInBackground(
  String dbPath,
  String coverDir,
  List<String> roots,
  void Function(int done, int total) onProgress, {
  String? mirror,
}) async {
  final port = ReceivePort();
  try {
    await Isolate.spawn(_isolateMain, (port.sendPort, dbPath, coverDir, roots, mirror), onError: port.sendPort, onExit: port.sendPort);
    await for (final m in port) {
      if (m is (int, int)) {
        onProgress(m.$1, m.$2);
      } else if (m is ScanResult) {
        return m;
      } else if (m is List) {
        throw ScanError('${m.first}'); // [error, stack] from onError
      } else {
        break; // null from onExit: the isolate ended without a result
      }
    }
    throw ScanError('the scanner stopped unexpectedly');
  } finally {
    port.close();
  }
}

void _isolateMain((SendPort, String, String, List<String>, String?) args) {
  final (send, dbPath, coverDir, roots, mirror) = args;
  send.send(scan(dbPath, coverDir, roots, (d, t) => send.send((d, t)), mirror));
}

/// Tracks gone this long are deleted for good (with their plays); until then a
/// file that comes back (renamed, moved, folder re-added) keeps its history.
const goneDays = 180;

/// Incremental scan: reads only new or changed files (by modified time and size),
/// matches renamed or moved files to their old row, marks missing files gone,
/// then regroups albums. Tags and covers are read outside the write transaction;
/// each commit holds the write lock for a few milliseconds only.
ScanResult scan(String dbPath, String coverDir, List<String> roots, [void Function(int, int)? onProgress, String? mirror]) {
  final db = openDb(dbPath);
  final res = ScanResult();
  try {
    // A folder inside another library folder is scanned once.
    final rs = roots.toSet().toList();
    rs.removeWhere((r) => rs.any((o) => o != r && p.isWithin(o, r)));

    final rows = db.select('SELECT path, mtime, size, gone_at IS NOT NULL, cover FROM tracks').rows;
    final known = <String, (int, int)>{}, gonePaths = <String>{};
    for (final v in rows) {
      v[3] == 1 ? gonePaths.add(v[0] as String) : known[v[0] as String] = (v[1] as int, v[2] as int);
    }
    final firstScan = known.isEmpty;
    final seen = <String>{};
    final todo = <(String, String, int, int)>[]; // path, root, size, modified
    final online = <String>[];
    final walk = _Walk(mirror);
    for (final root in rs) {
      if (!Directory(root).existsSync()) continue; // e.g. unplugged drive: keep its tracks
      online.add(root);
      for (final (path, size, mtime) in walk.files(root)) {
        seen.add(path);
        final k = known[path];
        if (k != null && k.$1 == mtime && k.$2 == size) {
          res.unchanged++;
        } else {
          todo.add((path, root, size, mtime));
        }
      }
    }
    res.skipped = walk.failed;

    // Files no longer where they were. Not those on an offline drive or under a folder we could not read.
    bool keep(String path) {
      final root = rs.where((r) => p.isWithin(r, path)).firstOrNull;
      return (root != null && !online.contains(root)) || walk.failed.any((f) => p.isWithin(f, path));
    }

    final missing = {
      for (final path in known.keys)
        if (!seen.contains(path) && !keep(path)) path,
    };
    // Rename/move candidates: missing now, or gone earlier (a folder removed and added again).
    // Looked up only when a file at a new path turns up.
    Map<String, List<(int, int)>>? candidates;
    Map<String, List<(int, int)>> cands() => candidates ??= () {
      final m = <String, List<(int, int)>>{};
      for (final r in db.select('SELECT id, path, size, duration_ms, title, artist, gone_at FROM tracks')) {
        if (r['gone_at'] == null && !missing.contains(r['path'])) continue;
        m.putIfAbsent(_matchKey(r['size'] as int, r['title'] as String, r['artist'] as String?), () => []).add((
          r['id'] as int,
          r['duration_ms'] as int,
        ));
      }
      return m;
    }();

    final upsert = db.prepare('''
      INSERT INTO tracks(path, root, folder, mtime, size, title, artist, album_artist_tag, compilation, album,
        track_no, disc_no, year, genre, duration_ms, codec, sample_rate, bit_depth, channels, bitrate, cover, lyrics, added_at,
        composer, work, movement, movement_no, artist_sort, album_artist_sort, album_sort, mb_album_id,
        rg_track_gain, rg_track_peak, rg_album_gain, rg_album_peak, embedded_cover, cue_start_ms)
      VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
      ON CONFLICT(path) DO UPDATE SET root=excluded.root, folder=excluded.folder, mtime=excluded.mtime,
        size=excluded.size, title=excluded.title, artist=excluded.artist, album_artist_tag=excluded.album_artist_tag,
        compilation=excluded.compilation, album=excluded.album, track_no=excluded.track_no, disc_no=excluded.disc_no,
        year=excluded.year, genre=excluded.genre, duration_ms=excluded.duration_ms, codec=excluded.codec,
        sample_rate=excluded.sample_rate, bit_depth=excluded.bit_depth, channels=excluded.channels,
        bitrate=excluded.bitrate, cover=excluded.cover, lyrics=excluded.lyrics, composer=excluded.composer,
        work=excluded.work, movement=excluded.movement, movement_no=excluded.movement_no,
        artist_sort=excluded.artist_sort, album_artist_sort=excluded.album_artist_sort, album_sort=excluded.album_sort,
        mb_album_id=excluded.mb_album_id, rg_track_gain=excluded.rg_track_gain, rg_track_peak=excluded.rg_track_peak,
        rg_album_gain=excluded.rg_album_gain, rg_album_peak=excluded.rg_album_peak,
        embedded_cover=excluded.embedded_cover, cue_start_ms=excluded.cue_start_ms, gone_at=NULL
      RETURNING id''');
    final moveTo = db.prepare('UPDATE tracks SET path = ? WHERE id = ?');
    final clearArtists = db.prepare('DELETE FROM track_artists WHERE track_id = ?');
    final addArtist = db.prepare('INSERT INTO track_artists(track_id, name, explicit) VALUES(?, ?, ?)');
    final covers = _Covers(
      coverDir,
      walk.images,
      {for (final v in rows) ?v[4] as String?},
      {for (final r in db.select('SELECT cover FROM cover_quality')) r['cover'] as String},
    );
    final now = DateTime.now().millisecondsSinceEpoch;
    onProgress?.call(0, todo.length);
    var i = 0;
    while (i < todo.length) {
      // Read a batch with no lock held: tags and cover decoding are the slow part.
      final batch = <(String, String, int, int, Tags, (String, bool)?)>[];
      final sw = Stopwatch()..start();
      (String, Tags)? file; // a CUE file's own tags, read once for all its tracks
      while (i < todo.length && batch.length < 50 && sw.elapsedMilliseconds < 1000) {
        final (path, root, size, mtime) = todo[i++];
        final c = walk.cueOf[path];
        final Tags t;
        if (c == null) {
          t = readTags(path);
        } else {
          final real = cueFile(path);
          if (file?.$1 != real) file = (real, readTags(real));
          t = cueTags(file!.$2, c.$1, c.$2, c.$3);
        }
        final cover = covers.forTrack(p.dirname(path), t.picture);
        t.picture = null;
        batch.add((path, root, size, mtime, t, cover));
      }
      // Then one short write.
      db.execute('BEGIN IMMEDIATE');
      for (final (path, root, size, mtime, t, cover) in batch) {
        final moved = known.containsKey(path) || gonePaths.contains(path) ? null : _match(cands(), size, t);
        if (known.containsKey(path)) {
          res.updated++;
        } else if (moved != null) {
          moveTo.execute([path, moved]);
          res.moved++;
        } else {
          res.added++;
        }
        final folder = p.dirname(path);
        final id =
            upsert.select([
                  path,
                  root,
                  folder,
                  mtime,
                  size,
                  t.title,
                  t.artist,
                  t.albumArtist,
                  t.compilation ? 1 : 0,
                  t.album ?? p.basename(albumFolder(folder)),
                  t.track,
                  t.disc,
                  t.year,
                  t.genre,
                  t.durationMs,
                  t.codec,
                  t.sampleRate,
                  t.bitDepth,
                  t.channels,
                  t.bitrate,
                  cover?.$1,
                  t.lyrics,
                  firstScan && mtime > 0 && mtime < now ? mtime : now, // first scan: when the file was added
                  t.composer,
                  t.work,
                  t.movementName,
                  t.movement,
                  t.artistSort,
                  t.albumArtistSort,
                  t.albumSort,
                  t.mbAlbumId,
                  t.rgTrackGain,
                  t.rgTrackPeak,
                  t.rgAlbumGain,
                  t.rgAlbumPeak,
                  (cover?.$2 ?? false) ? 1 : 0,
                  walk.cueOf[path]?.$2.startMs,
                ]).single['id']
                as int;
        clearArtists.execute([id]);
        final explicit = t.artistsTag.isNotEmpty || t.artists.length > 1;
        for (final a in t.artistsTag.isNotEmpty ? t.artistsTag : t.artists) {
          addArtist.execute([id, a, explicit ? 1 : 0]);
        }
      }
      covers.saveQuality(db);
      db.execute('COMMIT');
      onProgress?.call(i, todo.length);
    }
    for (final s in [upsert, moveTo, clearArtists, addArtist]) {
      s.close();
    }

    // Files still missing are marked gone (hidden, history kept); long-gone ones are deleted.
    final gone = db.prepare('UPDATE tracks SET gone_at = ? WHERE path = ? AND gone_at IS NULL');
    _batched(db, missing.toList(), (path) {
      gone.execute([now, path]);
      res.removed += db.updatedRows;
    });
    gone.close();
    db.execute('DELETE FROM tracks WHERE gone_at < ?', [now - goneDays * 86400000]);

    final newCovers = _refreshFolderCovers(db, covers, walk);
    final blank = db.select("SELECT 1 FROM tracks WHERE album_key = '' AND gone_at IS NULL LIMIT 1").isNotEmpty;
    res.changed = todo.isNotEmpty || res.removed > 0 || blank || newCovers;
    if (todo.isNotEmpty || res.removed > 0 || blank) regroup(db);
    covers.clean(db);
    onProgress?.call(todo.length, todo.length);
  } finally {
    db.close();
  }
  return res;
}

String _matchKey(int size, String title, String? artist) => '$size\u0000${normalise(title)}\u0000${normalise(artist ?? '')}';

/// A missing/gone row with the same size, title and artist, and a length within 2 s.
int? _match(Map<String, List<(int, int)>> candidates, int size, Tags t) {
  final list = candidates[_matchKey(size, t.title!, t.artist)];
  final i = list?.indexWhere((c) => (c.$2 - t.durationMs).abs() <= 2000) ?? -1;
  return i < 0 ? null : list!.removeAt(i).$1;
}

/// Folder art added, changed or removed since the last scan, for tracks without embedded art.
/// Returns whether any cover (or a cover's quality) changed.
bool _refreshFolderCovers(Database db, _Covers covers, _Walk walk) {
  final changes = <(String?, int)>[];
  for (final r in db.select('SELECT id, folder, cover FROM tracks WHERE embedded_cover = 0 AND gone_at IS NULL')) {
    final folder = r['folder'] as String;
    if (!walk.listed.contains(folder.toLowerCase())) continue; // not looked at this time (offline drive)
    final c = covers.forFolder(folder);
    if (c != r['cover']) changes.add((c, r['id'] as int));
  }
  final upd = db.prepare('UPDATE tracks SET cover = ? WHERE id = ?');
  _batched(db, changes, (x) => upd.execute([x.$1, x.$2]));
  upd.close();
  final changed = changes.isNotEmpty || covers._quality.isNotEmpty;
  db.execute('BEGIN IMMEDIATE');
  covers.saveQuality(db);
  db.execute('COMMIT');
  return changed;
}

/// Runs [write] for each item in short transactions, so a UI write never waits long.
void _batched<T>(Database db, List<T> items, void Function(T) write) {
  for (var i = 0; i < items.length; i += 2000) {
    db.execute('BEGIN IMMEDIATE');
    items.skip(i).take(2000).forEach(write);
    db.execute('COMMIT');
  }
}

const _imageExtensions = {'.jpg', '.jpeg', '.png', '.webp'};

/// A file: path, size, modified time (ms).
typedef _File = (String, int, int);

/// Lists audio files recursively. Follows junctions and symlinks once each (by real path),
/// remembers folders it could not read, and collects the images in each folder.
class _Walk {
  _Walk(this.mirror);

  /// Where Android 13+ keeps copies of .cue files it can't list in place (null elsewhere).
  final String? mirror;

  /// CUE tracks found, by their path (`<file>#<track no>`): the sheet, the track, and where it ends (null: the file's end).
  final cueOf = <String, (Cue, CueTrack, int?)>{};
  final _cues = <String, Cue>{};
  final failed = <String>[];
  final images = <String, List<_File>>{}; // lower-case folder -> its images
  final listed = <String>{}; // lower-case folders read
  final _visited = <String>{};

  /// [real] is the folder's real path (resolved for roots and links only: one system call each).
  Iterable<_File> files(String dir, [String? real]) sync* {
    List<(String, int, int, int)>? entries;
    try {
      real ??= Directory(dir).resolveSymbolicLinksSync();
      if (!_visited.add(real.toLowerCase())) return;
      entries = _listDir(dir);
    } on FileSystemException {
      entries = null;
    }
    if (entries == null) {
      failed.add(dir);
      return;
    }
    listed.add(dir.toLowerCase());
    final base = dir.endsWith(p.separator) ? dir : '$dir${p.separator}';
    final cues = [
      for (final (name, kind, _, mtime) in entries)
        if (kind == _file && name.toLowerCase().endsWith('.cue')) ('$base$name', mtime),
      ..._mirrored(dir),
    ];
    for (var (name, kind, size, mtime) in entries) {
      final path = '$base$name';
      String? target;
      if (kind == _link) {
        try {
          target = Link(path).resolveSymbolicLinksSync();
        } on FileSystemException {
          continue; // broken link
        }
        final st = FileStat.statSync(target);
        (kind, size, mtime) = (st.type == FileSystemEntityType.directory ? _dir : _file, st.size, st.modified.millisecondsSinceEpoch);
      }
      if (kind == _file) {
        final ext = p.extension(name).toLowerCase();
        if (audioExtensions.contains(ext)) {
          final split = cues.isEmpty ? const <(String, int)>[] : _split(path, mtime, cues);
          if (split.isEmpty) yield (path, size, mtime);
          for (final (track, time) in split) {
            yield (track, size, time);
          }
        } else if (_imageExtensions.contains(ext)) {
          images.putIfAbsent(dir.toLowerCase(), () => []).add((path, size, mtime));
        }
      } else {
        yield* files(path, target ?? p.join(real!, name));
      }
    }
  }
}

const _file = 0, _dir = 1, _link = 2;

extension on _Walk {
  /// Android 13+: the copies of [dir]'s .cue files (see [mirror]): (the copy, modified time).
  List<(String, int)> _mirrored(String dir) {
    final m = mirror;
    if (m == null) return const [];
    final d = Directory(p.join(m, p.relative(dir, from: p.rootPrefix(dir))));
    if (!d.existsSync()) return const [];
    return [
      for (final f in d.listSync().whereType<File>())
        if (f.path.toLowerCase().endsWith('.cue')) (f.path, f.statSync().modified.millisecondsSinceEpoch),
    ];
  }

  /// The CUE tracks of [audio] (`<file>#<no>`, and the newer modified time of the file and the sheet)
  /// from the first sheet in its folder that splits it; empty when none does.
  List<(String, int)> _split(String audio, int mtime, List<(String, int)> cues) {
    for (final (cuePath, cueTime) in cues) {
      final cue = _cues.putIfAbsent(cuePath, () {
        try {
          return parseCue(readText(cuePath));
        } on FileSystemException {
          return Cue();
        }
      });
      final ts = cue.tracksOf(p.basename(audio));
      if (ts.isEmpty) continue;
      final out = <(String, int)>[];
      for (var i = 0; i < ts.length; i++) {
        final path = '$audio#${ts[i].no}';
        cueOf[path] = (cue, ts[i], i + 1 < ts.length ? ts[i + 1].startMs : null);
        out.add((path, max(mtime, cueTime)));
      }
      return out;
    }
    return const [];
  }
}

/// A CUE track's tags: the sheet's titles, performers, date and genre over its file's tags [f].
Tags cueTags(Tags f, Cue cue, CueTrack tr, int? endMs) {
  final artist = tr.performer ?? cue.performer ?? f.artist;
  final t = Tags()
    ..title = tr.title ?? 'Track ${tr.no}'
    ..artist = artist
    ..albumArtist = cue.performer ?? f.albumArtist
    ..album = cue.title ?? f.album
    ..track = tr.no
    ..disc = f.disc
    ..year = cue.year ?? f.year
    ..genre = cue.genre ?? f.genre
    ..composer = f.composer
    ..mbAlbumId = f.mbAlbumId
    ..rgAlbumGain = f.rgAlbumGain ?? f.rgTrackGain
    ..rgAlbumPeak = f.rgAlbumPeak ?? f.rgTrackPeak
    ..durationMs = max(0, (endMs ?? f.durationMs) - tr.startMs)
    ..sampleRate = f.sampleRate
    ..bitDepth = f.bitDepth
    ..channels = f.channels
    ..bitrate = f.bitrate
    ..codec = f.codec
    ..picture = f.picture;
  if (artist != null) t.artists.add(artist);
  return t;
}

/// One folder's entries: (name, kind, size, modified ms); null if it cannot be read.
/// On Windows one FindFirstFileEx pass gives sizes and times too (no stat per file,
/// which was most of a no-change rescan). Elsewhere: list, then stat each file.
List<(String, int, int, int)>? _listDir(String dir) {
  if (Platform.isWindows) return _listWindows(dir);
  return [
    for (final e in Directory(dir).listSync(followLinks: false))
      if (e is Link)
        (p.basename(e.path), _link, 0, 0)
      else if (e is Directory)
        (p.basename(e.path), _dir, 0, 0)
      else if (e.statSync() case final st)
        (p.basename(e.path), _file, st.size, st.modified.millisecondsSinceEpoch),
  ];
}

final _kernel32 = DynamicLibrary.open('kernel32.dll');
final _findFirst = _kernel32
    .lookupFunction<
      IntPtr Function(Pointer<Utf16>, Int32, Pointer<Uint8>, Int32, Pointer<Void>, Uint32),
      int Function(Pointer<Utf16>, int, Pointer<Uint8>, int, Pointer<Void>, int)
    >('FindFirstFileExW');
final _findNext = _kernel32.lookupFunction<Int32 Function(IntPtr, Pointer<Uint8>), int Function(int, Pointer<Uint8>)>('FindNextFileW');
final _findClose = _kernel32.lookupFunction<Int32 Function(IntPtr), int Function(int)>('FindClose');

List<(String, int, int, int)>? _listWindows(String dir) {
  final pattern = (dir.endsWith('\\') ? '$dir*' : '$dir\\*').toNativeUtf16();
  final data = calloc<Uint8>(592); // WIN32_FIND_DATAW
  try {
    final h = _findFirst(pattern, 1 /* FindExInfoBasic */, data, 0, nullptr, 2 /* FIND_FIRST_EX_LARGE_FETCH */);
    if (h == -1) return null;
    final b = data.asTypedList(592).buffer.asByteData();
    final out = <(String, int, int, int)>[];
    do {
      final name = (data + 44).cast<Utf16>().toDartString();
      if (name == '.' || name == '..') continue;
      final attrs = b.getUint32(0, Endian.little), tag = b.getUint32(36, Endian.little);
      // Symlinks and junctions only; other reparse points (e.g. OneDrive files) are ordinary entries.
      final kind = attrs & 0x400 != 0 && (tag == 0xA000000C || tag == 0xA0000003) ? _link : (attrs & 0x10 != 0 ? _dir : _file);
      final size = (b.getUint32(28, Endian.little) << 32) | b.getUint32(32, Endian.little);
      final mtime = b.getUint64(20, Endian.little) ~/ 10000 - 11644473600000; // FILETIME (100 ns since 1601) to Unix ms
      out.add((name, kind, size, mtime));
    } while (_findNext(h, data) != 0);
    _findClose(h);
    return out;
  } finally {
    calloc.free(pattern);
    calloc.free(data);
  }
}

/// Regroups albums (see [groupAlbums]).
void regroup(Database db) {
  final rows = db.select(
    'SELECT id, folder, album, artist, album_artist_tag, compilation, mb_album_id, album_artist, album_key FROM tracks WHERE gone_at IS NULL',
  );
  final groups = groupAlbums([
    for (final r in rows)
      GroupInput(
        r['id'] as int,
        r['folder'] as String,
        r['album'] as String,
        r['artist'] as String?,
        r['album_artist_tag'] as String?,
        r['compilation'] == 1,
        r['mb_album_id'] as String?,
      ),
  ]);
  final changes = [
    for (final r in rows)
      if (groups[r['id']] case (final aa, final key) when aa != r['album_artist'] || key != r['album_key']) (aa, key, r['id']),
  ];
  final upd = db.prepare('UPDATE tracks SET album_artist = ?, album_key = ? WHERE id = ?');
  _batched(db, changes, (x) => upd.execute([x.$1, x.$2, x.$3]));
  upd.close();
}

/// Cover thumbnails: embedded picture first, else the folder's art (see [_pickImage]),
/// or its parent's for CD1/Disc 2 folders. Cached once per image.
class _Covers {
  _Covers(this.dir, this.images, this.known, this.checked) {
    Directory(dir).createSync(recursive: true);
  }
  final String dir;
  final Map<String, List<_File>> images;

  /// Thumbnails the database already uses (they exist: [clean] never deletes those).
  final Set<String> known;

  /// Thumbnails whose quality is already in `cover_quality`.
  final Set<String> checked;

  /// Quality results not written yet: thumbnail -> problem (null when fine).
  final _quality = <String, String?>{};

  /// Writes the quality results so far (inside the caller's transaction).
  void saveQuality(Database db) {
    if (_quality.isEmpty) return;
    final ins = db.prepare('INSERT OR REPLACE INTO cover_quality(cover, problem) VALUES(?, ?)');
    _quality.forEach((c, problem) => ins.execute([c, problem]));
    ins.close();
    _quality.clear();
  }

  final _folderCache = <String, String?>{};

  /// The thumbnail and whether it came from embedded art.
  (String, bool)? forTrack(String folder, Uint8List? embedded) {
    if (embedded != null && embedded.isNotEmpty) {
      final thumb = _thumb(_fnv(embedded), () => embedded);
      if (thumb != null) return (thumb, true);
    }
    final f = forFolder(folder);
    return f == null ? null : (f, false);
  }

  String? forFolder(String folder) => _folderCache.putIfAbsent(folder.toLowerCase(), () {
    final dirs = [folder, if (albumFolder(folder) != folder) p.dirname(folder)];
    for (final d in dirs) {
      final img = _pickImage(images[d.toLowerCase()] ?? const []);
      if (img != null) return _fileThumb(img);
    }
    for (final d in dirs) {
      for (final sub in ['artwork', 'scans', 'covers']) {
        final img = _pickImage(images[p.join(d, sub).toLowerCase()] ?? const [], any: true);
        if (img != null) return _fileThumb(img);
      }
    }
    return null;
  });

  String? _fileThumb(_File f) => _thumb(_fnv(Uint8List.fromList('${f.$1}|${f.$3}|${f.$2}'.codeUnits)), File(f.$1).readAsBytesSync);

  /// The thumbnail for an image, made once; its quality (small, blocky, blurry) is checked
  /// once on the full image, so low-quality covers can get generated art instead.
  String? _thumb(String hash, Uint8List Function() bytes) {
    final out = p.join(dir, '$hash.jpg');
    final exists = known.contains(out) || File(out).existsSync();
    if (exists && checked.contains(out)) return out;
    try {
      final image = img.decodeImage(bytes());
      if (image == null) return exists ? out : null;
      checked.add(out);
      _quality[out] = imageProblem(image);
      if (exists) return out;
      final small = image.width > 512 ? img.copyResize(image, width: 512, interpolation: img.Interpolation.average) : image;
      File(out).writeAsBytesSync(img.encodeJpg(small, quality: 88));
      return out;
    } catch (_) {
      return null;
    }
  }

  /// Deletes thumbnails no visible track uses (gone tracks get theirs again if they come back).
  /// Leaves files younger than 10 minutes alone, in case another scan is writing them.
  void clean(Database db) {
    final used = {
      for (final r in db.select('SELECT DISTINCT cover FROM tracks WHERE gone_at IS NULL AND cover IS NOT NULL')) r['cover'] as String,
    };
    db.execute('DELETE FROM cover_quality WHERE cover NOT IN (SELECT cover FROM tracks WHERE cover IS NOT NULL)');
    final old = DateTime.now().subtract(const Duration(minutes: 10));
    for (final f in Directory(dir).listSync().whereType<File>()) {
      if (used.contains(f.path)) continue;
      try {
        if (f.statSync().modified.isBefore(old)) f.deleteSync();
      } on FileSystemException {
        // in use or already gone
      }
    }
  }
}

/// cover/folder/front/album, then AlbumArt*.jpg (Large first); else the only image,
/// or with [any] the first by name.
_File? _pickImage(List<_File> files, {bool any = false}) {
  if (files.isEmpty) return null;
  int rank(_File f) {
    final n = p.basenameWithoutExtension(f.$1).toLowerCase();
    final i = const ['cover', 'folder', 'front', 'album'].indexOf(n);
    if (i >= 0) return i;
    if (n.startsWith('albumart')) return n.contains('large') ? 4 : 5;
    return 99;
  }

  final sorted = [...files]..sort((a, b) => rank(a) != rank(b) ? rank(a) - rank(b) : a.$1.compareTo(b.$1));
  return rank(sorted.first) < 99 || files.length == 1 || any ? sorted.first : null;
}

String _fnv(Uint8List b) {
  var h = 0xcbf29ce484222325;
  for (final x in b) {
    h = (h ^ x) * 0x100000001b3;
  }
  return (h >>> 1).toRadixString(16);
}
