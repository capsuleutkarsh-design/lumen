import 'dart:convert';

import 'models.dart';
import 'suggestions.dart' show PlayStat;

/// One rule of a smart playlist. [f] is the field; [a] and [b] are its values:
/// - `genre` is [a] (text, any of the song's genres, ignoring case)
/// - `year` between [a] and [b] (whole years, both included)
/// - `added` in the last [a] days
/// - `plays` more than [a] times
/// - `never` never played
/// - `fav` a favourite
/// - `format` is [a] (FLAC, MP3, ...)
/// - `rate` sample rate at least [a] Hz
/// - `bits` bit depth at least [a]
/// - `artist` contains [a] (text, ignoring case)
/// - `rating` at least [a] stars
class SmartRule {
  const SmartRule(this.f, [this.a, this.b]);
  final String f;
  final Object? a, b;

  static const fields = {
    'genre': 'Genre is',
    'year': 'Year between',
    'added': 'Added in the last … days',
    'plays': 'Play count more than',
    'never': 'Never played',
    'fav': 'Is a favourite',
    'format': 'Format is',
    'rate': 'Sample rate at least (Hz)',
    'bits': 'Bit depth at least',
    'artist': 'Artist contains',
    'rating': 'Rating at least (stars)',
  };

  /// Fields that take no value, and those that take two numbers.
  static const noValue = {'never', 'fav'};
  static const range = {'year'};
  static const text = {'genre', 'format', 'artist'};

  Map<String, Object?> toJson() => {'f': f, 'a': ?a, 'b': ?b};
  static SmartRule fromJson(Map<String, Object?> j) => SmartRule(j['f'] as String, j['a'], j['b']);

  int get _a => (a as num?)?.toInt() ?? 0;
  int get _b => (b as num?)?.toInt() ?? 0;
  String get _text => (a as String? ?? '').toLowerCase().trim();

  bool test(Track t, SmartContext c) => switch (f) {
    'genre' => t.genres.any((g) => g.toLowerCase() == _text),
    'year' => t.year != null && t.year! >= _a && t.year! <= (b == null ? _a : _b),
    'added' => t.addedAt >= c.now.subtract(Duration(days: _a)).millisecondsSinceEpoch,
    'plays' => (c.stats[t.id]?.plays ?? 0) > _a,
    'never' => (c.stats[t.id]?.plays ?? 0) == 0,
    'fav' => c.favourites.contains(t.id),
    'format' => t.codec.toLowerCase() == _text,
    'rate' => t.sampleRate >= _a,
    'bits' => t.bitDepth >= _a,
    'artist' => t.artist.toLowerCase().contains(_text),
    'rating' => (c.ratings[t.id] ?? 0) >= _a,
    _ => false,
  };

  /// "Genre is Jazz", "Year between 1990 and 1999".
  String describe() => switch (f) {
    'year' => 'Year ${b == null || a == b ? 'is $a' : 'between $a and $b'}',
    'added' => 'Added in the last $a days',
    'plays' => _a == 0 ? 'Played at least once' : 'Played more than $a times',
    'never' => 'Never played',
    'fav' => 'Favourite',
    'rate' => 'Sample rate at least ${(_a / 1000).toStringAsFixed(_a % 1000 == 0 ? 0 : 1)} kHz',
    'bits' => 'Bit depth at least $a',
    'rating' => 'Rated $a ${_a == 1 ? 'star' : 'stars'} or more',
    _ => '${fields[f] ?? f} $a',
  };
}

/// What rules need besides the track: plays, favourites, today, star ratings.
class SmartContext {
  const SmartContext(this.stats, this.favourites, this.now, [this.ratings = const {}]);
  final Map<int, PlayStat> stats;
  final Set<int> favourites;
  final DateTime now;
  final Map<int, int> ratings;
}

class SmartPlaylist {
  SmartPlaylist(this.id, this.name, {this.rules = const [], this.any = false, this.sort = 'added', this.limit = 0});
  final int id;
  final String name;
  final List<SmartRule> rules;

  /// Match any rule instead of all of them.
  final bool any;

  /// added (newest first), plays (most first), last (last played first), title, artist, year (newest first).
  final String sort;

  /// 0 = no limit.
  final int limit;

  static const sorts = {
    'added': 'Recently added',
    'plays': 'Most played',
    'last': 'Recently played',
    'title': 'Title',
    'artist': 'Artist',
    'year': 'Year',
  };

  String get rulesJson => jsonEncode({
    'match': any ? 'any' : 'all',
    'rules': [for (final r in rules) r.toJson()],
    'sort': sort,
    'limit': limit,
  });

  /// A playlist stored with rules that no longer parse shows no songs instead of failing.
  static SmartPlaylist fromRow(int id, String name, String json) {
    try {
      final j = jsonDecode(json) as Map<String, Object?>;
      return SmartPlaylist(
        id,
        name,
        rules: [for (final r in j['rules'] as List? ?? const []) SmartRule.fromJson((r as Map).cast())],
        any: j['match'] == 'any',
        sort: j['sort'] as String? ?? 'added',
        limit: (j['limit'] as num?)?.toInt() ?? 0,
      );
    } catch (_) {
      return SmartPlaylist(id, name);
    }
  }

  /// The matching songs, sorted and cut to the limit. No rules matches nothing.
  List<Track> evaluate(List<Track> tracks, SmartContext c) {
    if (rules.isEmpty) return const [];
    final out = [
      for (final t in tracks)
        if (any ? rules.any((r) => r.test(t, c)) : rules.every((r) => r.test(t, c))) t,
    ];
    int plays(Track t) => c.stats[t.id]?.plays ?? 0;
    int last(Track t) => c.stats[t.id]?.last?.millisecondsSinceEpoch ?? 0;
    int str(String a, String b) => a.toLowerCase().compareTo(b.toLowerCase());
    out.sort(switch (sort) {
      'plays' => (a, b) => plays(b).compareTo(plays(a)),
      'last' => (a, b) => last(b).compareTo(last(a)),
      'title' => (a, b) => str(a.title, b.title),
      'artist' => (a, b) => str(a.artist, b.artist) != 0 ? str(a.artist, b.artist) : compareAlbumOrder(a, b),
      'year' => (a, b) => (b.year ?? 0).compareTo(a.year ?? 0),
      _ => (a, b) => b.addedAt.compareTo(a.addedAt),
    });
    return limit > 0 && out.length > limit ? out.sublist(0, limit) : out;
  }
}
