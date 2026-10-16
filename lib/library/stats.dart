import 'library.dart';
import 'models.dart';

/// One counted play (a song listened to past the play-count point; skips are left out).
typedef PlayRow = ({int trackId, DateTime at, int durationMs});

enum Bucket { day, week, month }

/// The start of the day, week (Monday) or month [t] falls in, local time.
DateTime bucketStart(DateTime t, Bucket b) => switch (b) {
  Bucket.day => DateTime(t.year, t.month, t.day),
  Bucket.week => DateTime(t.year, t.month, t.day - (t.weekday - 1)),
  Bucket.month => DateTime(t.year, t.month),
};

DateTime _next(DateTime t, Bucket b) => switch (b) {
  Bucket.day => DateTime(t.year, t.month, t.day + 1),
  Bucket.week => DateTime(t.year, t.month, t.day + 7),
  Bucket.month => DateTime(t.year, t.month + 1),
};

class ListenStats {
  ListenStats(this.buckets, this.total, this.plays, this.songs, this.albums, this.artists);

  /// Listening time per day / week / month from the first bucket to the last, empty ones included.
  final List<(DateTime, Duration)> buckets;
  final Duration total;
  final int plays;

  /// Most played first: (thing, plays).
  final List<(int, int)> songs; // track id
  final List<(String, int)> albums; // album key
  final List<(String, int)> artists; // artist name
}

/// Adds up [rows] played in [from, to). Listening time is each counted play times the song's
/// length (Gleo stores plays, not seconds). Top lists keep [top] entries each.
ListenStats listenStats(Iterable<PlayRow> rows, Map<int, Track> byId, DateTime from, DateTime to, Bucket b, {int top = 5}) {
  final time = <DateTime, int>{};
  final songs = <int, int>{}, albums = <String, int>{}, artists = <String, int>{};
  var total = 0, plays = 0;
  for (final r in rows) {
    if (r.at.isBefore(from) || !r.at.isBefore(to)) continue;
    plays++;
    total += r.durationMs;
    time.update(bucketStart(r.at, b), (v) => v + r.durationMs, ifAbsent: () => r.durationMs);
    songs.update(r.trackId, (v) => v + 1, ifAbsent: () => 1);
    final t = byId[r.trackId];
    if (t == null) continue; // hidden or gone: counted in the time, not in the top lists
    albums.update(t.albumKey, (v) => v + 1, ifAbsent: () => 1);
    for (final a in t.artists) {
      artists.update(a, (v) => v + 1, ifAbsent: () => 1);
    }
  }
  final buckets = <(DateTime, Duration)>[];
  for (var d = bucketStart(from, b); d.isBefore(to); d = _next(d, b)) {
    buckets.add((d, Duration(milliseconds: time[d] ?? 0)));
  }
  List<(K, int)> best<K>(Map<K, int> m) =>
      (m.entries.toList()..sort((x, y) => y.value.compareTo(x.value))).take(top).map((e) => (e.key, e.value)).toList();
  songs.removeWhere((id, _) => !byId.containsKey(id));
  return ListenStats(buckets, Duration(milliseconds: total), plays, best(songs), best(albums), best(artists));
}

extension LibraryStats on Library {
  /// Counted plays from [from] on, with each song's length (hidden and gone songs too).
  List<PlayRow> playsSince(DateTime from) => [
    for (final r in db.select(
      'SELECT p.track_id, p.at, t.duration_ms FROM plays p JOIN tracks t ON t.id = p.track_id WHERE p.skipped = 0 AND p.at >= ? ORDER BY p.at',
      [from.millisecondsSinceEpoch],
    ))
      (trackId: r['track_id'] as int, at: DateTime.fromMillisecondsSinceEpoch(r['at'] as int), durationMs: r['duration_ms'] as int),
  ];

  /// When the first counted play happened (null: nothing played yet).
  DateTime? get firstPlay {
    final v = db.select('SELECT min(at) m FROM plays WHERE skipped = 0').first['m'] as int?;
    return v == null ? null : DateTime.fromMillisecondsSinceEpoch(v);
  }

  /// Bytes on disk of the songs in the library.
  int get librarySize => db.select('SELECT coalesce(sum(size), 0) s FROM tracks WHERE gone_at IS NULL AND hidden = 0').first['s'] as int;
}

/// Songs per format ("FLAC", "MP3", ...), most first.
List<(String, int)> formatCounts(Iterable<Track> tracks) {
  final m = <String, int>{};
  for (final t in tracks) {
    m.update(t.codec, (v) => v + 1, ifAbsent: () => 1);
  }
  return (m.entries.toList()..sort((a, b) => b.value.compareTo(a.value))).map((e) => (e.key, e.value)).toList();
}

/// 1536 -> "1.5 KB", 3.2e9 -> "3.2 GB".
String fmtBytes(int n) {
  const units = ['bytes', 'KB', 'MB', 'GB', 'TB'];
  var v = n.toDouble();
  var i = 0;
  while (v >= 1024 && i < units.length - 1) {
    v /= 1024;
    i++;
  }
  return i == 0 ? '$n bytes' : '${v.toStringAsFixed(v >= 100 ? 0 : 1)} ${units[i]}';
}
