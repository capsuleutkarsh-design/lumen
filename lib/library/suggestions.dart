// Home suggestions from local listening stats only. Every pick carries the
// plain-words reason shown on hover.
import 'models.dart';

class PlayEvent {
  const PlayEvent(this.trackId, this.at, this.skipped);
  final int trackId;
  final DateTime at;
  final bool skipped;
}

class Pick<T> {
  const Pick(this.item, this.why);
  final T item;
  final String why;
}

class HomeData {
  List<Pick<Album>> jumpBackIn = [], recentlyAdded = [];
  List<Pick<Track>> mostPlayed = [], notLately = [], because = [];
  Track? seed;
}

/// Listening rules: a play counts after half the track or 4 minutes of actual
/// listening; leaving a track before 30 s is a skip.
class ListenRules {
  static const countAfter = Duration(minutes: 4);
  static const skipBefore = Duration(seconds: 30);
  static bool counts(Duration listened, Duration length) => listened >= countAfter || (length > Duration.zero && listened * 2 >= length);
  static bool isSkip(Duration listened) => listened < skipBefore;
}

String ago(DateTime t, DateTime now) {
  final d = now.difference(t);
  if (d.inMinutes < 60) return 'just now';
  if (d.inHours < 24) return '${d.inHours} h ago';
  if (d.inDays == 1) return 'yesterday';
  if (d.inDays < 60) return '${d.inDays} days ago';
  return '${d.inDays ~/ 30} months ago';
}

/// One track's listening: plays, skips and the last (non-skipped) play.
class PlayStat {
  PlayStat([this.plays = 0, this.skips = 0, this.last]);
  int plays, skips;
  DateTime? last;
}

/// Adds up play events (the database does this in SQL; see Library.home).
Map<int, PlayStat> statsFrom(Iterable<PlayEvent> events) {
  final stats = <int, PlayStat>{};
  for (final e in events) {
    final s = stats.putIfAbsent(e.trackId, PlayStat.new);
    if (e.skipped) {
      s.skips++;
    } else {
      s.plays++;
      if (s.last == null || e.at.isAfter(s.last!)) s.last = e.at;
    }
  }
  return stats;
}

HomeData suggest(List<Track> tracks, List<Album> albums, Map<int, PlayStat> allStats, DateTime now, {int limit = 12}) {
  final byId = {for (final t in tracks) t.id: t};
  final stats = {
    for (final e in allStats.entries)
      if (byId.containsKey(e.key)) e.key: e.value,
  };
  final h = HomeData();
  String times(int n) => n == 1 ? 'once' : '$n times';

  // Jump back in: albums by their most recent play.
  final albumLast = <Album, DateTime>{};
  for (final a in albums) {
    for (final t in a.tracks) {
      final l = stats[t.id]?.last;
      if (l != null && (albumLast[a] == null || l.isAfter(albumLast[a]!))) albumLast[a] = l;
    }
  }
  h.jumpBackIn = [
    for (final a in (albumLast.keys.toList()..sort((x, y) => albumLast[y]!.compareTo(albumLast[x]!))).take(limit))
      Pick(a, 'You played this ${ago(albumLast[a]!, now)}'),
  ];

  // Most played tracks.
  final played = stats.entries.where((e) => e.value.plays > 0).toList()
    ..sort((a, b) {
      final c = b.value.plays.compareTo(a.value.plays);
      return c != 0 ? c : b.value.last!.compareTo(a.value.last!);
    });
  h.mostPlayed = [for (final e in played.take(limit)) Pick(byId[e.key]!, 'Played ${times(e.value.plays)}')];

  // Not played in a while: played at least 3 times, but not in the last 30 days.
  final cutoff = now.subtract(const Duration(days: 30));
  h.notLately = [
    for (final e in played.where((e) => e.value.plays >= 3 && e.value.last!.isBefore(cutoff)).take(limit))
      Pick(byId[e.key]!, 'Played ${times(e.value.plays)}, last ${ago(e.value.last!, now)}'),
  ];

  // Recently added albums.
  h.recentlyAdded = [
    for (final a in (albums.toList()..sort((x, y) => y.addedAt.compareTo(x.addedAt))).take(limit))
      Pick(a, 'Added ${ago(DateTime.fromMillisecondsSinceEpoch(a.addedAt), now)}'),
  ];

  // Because you played X: same artist, then same album artist, then same genre and decade.
  final seedEntry = played.isEmpty ? null : (played.toList()..sort((a, b) => b.value.last!.compareTo(a.value.last!))).first;
  final seed = seedEntry == null ? null : byId[seedEntry.key];
  h.seed = seed;
  if (seed != null) {
    final recent = now.subtract(const Duration(days: 2));
    bool excluded(Track t) {
      if (t.id == seed.id) return true;
      final s = stats[t.id];
      if (s == null) return false;
      if (s.last != null && s.last!.isAfter(recent)) return true; // played lately
      return s.skips >= 2 && s.skips > s.plays; // often skipped
    }

    int? decade(Track t) => t.year == null ? null : t.year! ~/ 10 * 10;
    final picks = <Pick<Track>>[];
    final used = <int>{};
    void tier(bool Function(Track) match, String why) {
      final ts = tracks.where((t) => !used.contains(t.id) && !excluded(t) && match(t)).toList()
        ..sort((a, b) => a.albumKey != b.albumKey ? a.albumKey.compareTo(b.albumKey) : compareAlbumOrder(a, b));
      for (final t in ts) {
        if (picks.length >= limit) return;
        used.add(t.id);
        picks.add(Pick(t, why));
      }
    }

    // An untagged seed ("Unknown artist") would match every untagged track: skip those tiers.
    const unknown = 'unknown artist';
    final low = seed.artist.toLowerCase(), lowAa = seed.albumArtist.toLowerCase();
    if (low != unknown) tier((t) => t.artist.toLowerCase() == low, 'Same artist as “${seed.title}”: ${seed.artist}');
    if (seed.albumArtist != variousArtists && lowAa != unknown) {
      tier((t) => t.albumArtist.toLowerCase() == lowAa, 'From ${seed.albumArtist}, like “${seed.title}”');
    }
    if (seed.genre != null && decade(seed) != null) {
      tier(
        (t) => t.genre?.toLowerCase() == seed.genre!.toLowerCase() && decade(t) == decade(seed),
        '${seed.genre} from the ${decade(seed)}s, like “${seed.title}”',
      );
    }
    h.because = picks;
  }
  return h;
}
