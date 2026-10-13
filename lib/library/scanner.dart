import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

import 'db.dart';
import 'models.dart';
import 'tags.dart';

class ScanResult {
  int added = 0, updated = 0, removed = 0, unchanged = 0;
  @override
  String toString() => 'added $added, updated $updated, removed $removed, unchanged $unchanged';
}

/// Scans in a background isolate so the UI never waits. [onProgress] gets
/// (done, total) for files that need reading.
Future<ScanResult> scanInBackground(
  String dbPath,
  String coverDir,
  List<String> roots,
  void Function(int done, int total) onProgress,
) async {
  final port = ReceivePort();
  await Isolate.spawn(_isolateMain, (port.sendPort, dbPath, coverDir, roots));
  await for (final m in port) {
    if (m is (int, int)) {
      onProgress(m.$1, m.$2);
    } else {
      port.close();
      final (a, u, r, n) = m as (int, int, int, int);
      return ScanResult()
        ..added = a
        ..updated = u
        ..removed = r
        ..unchanged = n;
    }
  }
  throw StateError('scanner stopped');
}

void _isolateMain((SendPort, String, String, List<String>) args) {
  final (send, dbPath, coverDir, roots) = args;
  final r = scan(dbPath, coverDir, roots, (d, t) => send.send((d, t)));
  send.send((r.added, r.updated, r.removed, r.unchanged));
}

/// Incremental scan: reads only new or changed files (by modified time and
/// size), removes files that are gone, then regroups albums.
ScanResult scan(String dbPath, String coverDir, List<String> roots, [void Function(int, int)? onProgress]) {
  final db = openDb(dbPath);
  final res = ScanResult();
  try {
    final known = <String, (int, int)>{
      for (final r in db.select('SELECT path, mtime, size FROM tracks')) r['path'] as String: (r['mtime'] as int, r['size'] as int),
    };
    final seen = <String>{};
    final todo = <(String, String, FileStat)>[];
    final online = <String>[];
    for (final root in roots) {
      final dir = Directory(root);
      if (!dir.existsSync()) continue; // e.g. unplugged drive: keep its tracks
      online.add(root);
      for (final e in _list(dir)) {
        if (!audioExtensions.contains(p.extension(e.path).toLowerCase())) continue;
        final st = e.statSync();
        seen.add(e.path);
        final k = known[e.path];
        if (k != null && k.$1 == st.modified.millisecondsSinceEpoch && k.$2 == st.size) {
          res.unchanged++;
        } else {
          todo.add((e.path, root, st));
        }
      }
    }

    final upsert = db.prepare('''
      INSERT INTO tracks(path, root, folder, mtime, size, title, artist, album_artist_tag, compilation, album,
        track_no, disc_no, year, genre, duration_ms, codec, sample_rate, bit_depth, channels, bitrate, cover, lyrics, added_at)
      VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
      ON CONFLICT(path) DO UPDATE SET root=excluded.root, folder=excluded.folder, mtime=excluded.mtime,
        size=excluded.size, title=excluded.title, artist=excluded.artist, album_artist_tag=excluded.album_artist_tag,
        compilation=excluded.compilation, album=excluded.album, track_no=excluded.track_no, disc_no=excluded.disc_no,
        year=excluded.year, genre=excluded.genre, duration_ms=excluded.duration_ms, codec=excluded.codec,
        sample_rate=excluded.sample_rate, bit_depth=excluded.bit_depth, channels=excluded.channels,
        bitrate=excluded.bitrate, cover=excluded.cover, lyrics=excluded.lyrics''');
    final covers = _Covers(coverDir);
    final now = DateTime.now().millisecondsSinceEpoch;
    for (var i = 0; i < todo.length; i++) {
      if (i % 50 == 0) {
        if (i > 0) db.execute('COMMIT');
        db.execute('BEGIN');
        onProgress?.call(i, todo.length);
      }
      final (path, root, st) = todo[i];
      final t = readTags(path);
      final folder = p.dirname(path);
      upsert.execute([
        path,
        root,
        folder,
        st.modified.millisecondsSinceEpoch,
        st.size,
        t.title,
        t.artist,
        t.albumArtist,
        t.compilation ? 1 : 0,
        t.album ?? p.basename(folder),
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
        covers.forTrack(folder, t.picture),
        t.lyrics,
        now,
      ]);
      known.containsKey(path) ? res.updated++ : res.added++;
    }
    if (todo.isNotEmpty) db.execute('COMMIT');
    upsert.close();

    // Remove tracks whose file is gone, or whose library folder was removed.
    final del = db.prepare('DELETE FROM tracks WHERE path = ?');
    db.execute('BEGIN');
    for (final path in known.keys) {
      if (seen.contains(path)) continue;
      final root = roots.where((r) => p.isWithin(r, path)).firstOrNull;
      if (root != null && !online.contains(root)) continue;
      del.execute([path]);
      res.removed++;
    }
    db.execute('COMMIT');
    del.close();

    if (todo.isNotEmpty || res.removed > 0) regroup(db);
    onProgress?.call(todo.length, todo.length);
  } finally {
    db.close();
  }
  return res;
}

/// Lists files recursively, skipping folders we may not read.
Iterable<File> _list(Directory dir) sync* {
  List<FileSystemEntity> entries;
  try {
    entries = dir.listSync(followLinks: false);
  } on FileSystemException {
    return;
  }
  for (final e in entries) {
    if (e is File) {
      yield e;
    } else if (e is Directory) {
      yield* _list(e);
    }
  }
}

void regroup(Database db) {
  final rows = db.select('SELECT id, folder, album, artist, album_artist_tag, compilation, album_artist, album_key FROM tracks');
  final groups = groupAlbums([
    for (final r in rows)
      GroupInput(
        r['id'] as int,
        r['folder'] as String,
        r['album'] as String,
        r['artist'] as String?,
        r['album_artist_tag'] as String?,
        r['compilation'] == 1,
      ),
  ]);
  final upd = db.prepare('UPDATE tracks SET album_artist = ?, album_key = ? WHERE id = ?');
  db.execute('BEGIN');
  for (final r in rows) {
    final (aa, key) = groups[r['id']]!;
    if (aa != r['album_artist'] || key != r['album_key']) upd.execute([aa, key, r['id']]);
  }
  db.execute('COMMIT');
  upd.close();
}

/// Cover thumbnails: embedded picture first, else cover/folder/front image in
/// the folder (or its parent for CD1/Disc 2 folders). Cached once per image.
class _Covers {
  _Covers(this.dir) {
    Directory(dir).createSync(recursive: true);
  }
  final String dir;
  final _folderCache = <String, String?>{};

  String? forTrack(String folder, Uint8List? embedded) {
    if (embedded != null && embedded.isNotEmpty) {
      final thumb = _thumb(_fnv(embedded), () => embedded);
      if (thumb != null) return thumb;
    }
    return _folderCache.putIfAbsent(folder, () => _folderImage(folder));
  }

  String? _folderImage(String folder) {
    for (final d in [folder, if (RegExp(r'^(cd|dis[ck])\s*\d+$', caseSensitive: false).hasMatch(p.basename(folder))) p.dirname(folder)]) {
      List<FileSystemEntity> files;
      try {
        files = Directory(d).listSync();
      } on FileSystemException {
        continue;
      }
      for (final name in ['cover', 'folder', 'front', 'album']) {
        for (final f in files.whereType<File>()) {
          final base = p.basename(f.path).toLowerCase();
          if (base == '$name.jpg' || base == '$name.jpeg' || base == '$name.png') {
            final st = f.statSync();
            return _thumb(_fnv(Uint8List.fromList('${f.path}|${st.modified}|${st.size}'.codeUnits)), f.readAsBytesSync);
          }
        }
      }
    }
    return null;
  }

  String? _thumb(String hash, Uint8List Function() bytes) {
    final out = p.join(dir, '$hash.jpg');
    if (File(out).existsSync()) return out;
    try {
      final image = img.decodeImage(bytes());
      if (image == null) return null;
      final small = image.width > 512 ? img.copyResize(image, width: 512, interpolation: img.Interpolation.average) : image;
      File(out).writeAsBytesSync(img.encodeJpg(small, quality: 88));
      return out;
    } catch (_) {
      return null;
    }
  }
}

String _fnv(Uint8List b) {
  var h = 0xcbf29ce484222325;
  for (final x in b) {
    h = (h ^ x) * 0x100000001b3;
  }
  return h.toUnsigned(64).toRadixString(16);
}
