// Lyrics from LRCLIB (https://lrclib.net): free, no account or key. Only used when the user turns on
// Settings → Online → Download lyrics, only for songs with no lyrics of their own. What is found is kept
// as a .lrc in Gleo's data folder (never next to the music); a miss is remembered for 30 days.
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'models.dart';

/// The lyrics in an LRCLIB answer: an /api/get object, or an /api/search list (the closest length
/// within 2 s of [seconds] wins). Synced (LRC) lyrics are preferred; null when there are none
/// (not found, instrumental, empty).
String? lrclibPick(String body, int seconds) {
  final j = jsonDecode(body);
  final all = [
    if (j is Map) j,
    if (j is List) ...j.whereType<Map>(),
  ];
  String? text(Object? x) => x is String && x.trim().isNotEmpty ? x : null;
  int off(Map m) => ((m['duration'] as num? ?? seconds) - seconds).abs().round();
  int rank(Map m) => (text(m['syncedLyrics']) == null ? 100 : 0) + off(m);
  final fit = [
    for (final m in all)
      if (m['instrumental'] != true && off(m) <= 2 && (text(m['syncedLyrics']) ?? text(m['plainLyrics'])) != null) m,
  ]..sort((a, b) => rank(a) - rank(b));
  return fit.isEmpty ? null : text(fit.first['syncedLyrics']) ?? text(fit.first['plainLyrics']);
}

/// Where a song's downloaded lyrics are kept (by track id).
String savedLyrics(String dataDir, int id) => p.join(dataDir, 'lyrics', '$id.lrc');

final _asking = <int, Future<String?>>{};

/// Downloaded lyrics for [t]: kept ones, else asks LRCLIB (artist, title, album and length; then a
/// search by artist and title). Null when LRCLIB has none (remembered for 30 days). Throws when it
/// can't be reached, so a later try asks again.
Future<String?> lrclibLyrics(Track t, String dataDir, String userAgent) => _asking[t.id] ??= () async {
  try {
    final saved = File(savedLyrics(dataDir, t.id)), miss = File(p.join(dataDir, 'lyrics', '${t.id}.none'));
    if (saved.existsSync()) return saved.readAsStringSync();
    if (miss.existsSync() && DateTime.now().difference(miss.lastModifiedSync()).inDays < 30) return null;
    final secs = (t.durationMs / 1000).round();
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10)
      ..userAgent = userAgent;
    String? found;
    try {
      Future<(int, String)> ask(String path, Map<String, String> q) async {
        final res = await (await client.getUrl(Uri.https('lrclib.net', path, q))).close().timeout(const Duration(seconds: 15));
        return (res.statusCode, await res.transform(utf8.decoder).join());
      }

      final (code, body) = await ask('/api/get', {
        'artist_name': t.artist,
        'track_name': t.title,
        if (t.album.isNotEmpty) 'album_name': t.album,
        'duration': '$secs',
      });
      if (code == 200) found = lrclibPick(body, secs);
      if (found == null && (code == 200 || code == 404)) {
        final (c2, b2) = await ask('/api/search', {'artist_name': t.artist, 'track_name': t.title});
        if (c2 == 200) found = lrclibPick(b2, secs);
      } else if (code != 200) {
        throw HttpException('LRCLIB answered $code');
      }
    } finally {
      client.close();
    }
    Directory(p.dirname(miss.path)).createSync(recursive: true);
    found == null ? miss.writeAsStringSync('') : saved.writeAsStringSync(found);
    return found;
  } finally {
    _asking.remove(t.id);
  }
}();
