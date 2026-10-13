import 'package:sqlite3/sqlite3.dart' show Row;

class Track {
  Track({
    required this.id,
    this.path = '',
    this.folder = '',
    required this.title,
    this.artist = 'Unknown artist',
    String? albumArtist,
    this.album = '',
    String? albumKey,
    this.trackNo,
    this.discNo,
    this.year,
    this.genre,
    this.durationMs = 0,
    this.codec = 'FLAC',
    this.sampleRate = 44100,
    this.bitDepth = 16,
    this.bitrate = 0,
    this.cover,
    this.addedAt = 0,
  }) : albumArtist = albumArtist ?? artist,
       albumKey = albumKey ?? '${(albumArtist ?? artist).toLowerCase()}\u0000${album.toLowerCase()}';

  Track.fromRow(Row r)
    : id = r['id'] as int,
      path = r['path'] as String,
      folder = r['folder'] as String,
      title = r['title'] as String,
      artist = r['artist'] as String? ?? 'Unknown artist',
      albumArtist = r['album_artist'] as String,
      album = r['album'] as String,
      albumKey = r['album_key'] as String,
      trackNo = r['track_no'] as int?,
      discNo = r['disc_no'] as int?,
      year = r['year'] as int?,
      genre = r['genre'] as String?,
      durationMs = r['duration_ms'] as int,
      codec = r['codec'] as String,
      sampleRate = r['sample_rate'] as int,
      bitDepth = r['bit_depth'] as int,
      bitrate = r['bitrate'] as int,
      cover = r['cover'] as String?,
      addedAt = r['added_at'] as int;

  final int id;
  final String path, folder, title, artist, albumArtist, album, albumKey, codec;
  final int? trackNo, discNo, year;
  final String? genre, cover;
  final int durationMs, sampleRate, bitDepth, bitrate, addedAt;

  Duration get duration => Duration(milliseconds: durationMs);

  /// "FLAC 24/96", "WAV 16/44.1", "MP3 320k".
  String get badge => formatBadge(codec, bitDepth, sampleRate, bitrate);
}

String formatBadge(String codec, int bitDepth, int sampleRate, int bitrate) {
  if (bitDepth > 0 && sampleRate > 0) {
    final k = sampleRate / 1000;
    final rate = k == k.roundToDouble() ? k.round().toString() : k.toStringAsFixed(1);
    return '$codec $bitDepth/$rate';
  }
  return bitrate > 0 ? '$codec ${bitrate}k' : codec;
}

class Album {
  Album(this.key, this.tracks);
  final String key;
  final List<Track> tracks; // sorted by disc, track number

  Track get first => tracks.first;
  String get title => first.album;
  String get artist => first.albumArtist;
  int? get year => tracks.map((t) => t.year).whereType<int>().firstOrNull;
  String? get cover => tracks.map((t) => t.cover).whereType<String>().firstOrNull;
  int get addedAt => tracks.map((t) => t.addedAt).reduce((a, b) => a < b ? a : b);
  Duration get duration => Duration(milliseconds: tracks.fold(0, (s, t) => s + t.durationMs));
  int get discCount => tracks.map((t) => t.discNo ?? 1).toSet().length;

  /// The badge if every track shares it, else the best one with "+".
  String get badge {
    final badges = tracks.map((t) => t.badge).toSet();
    if (badges.length == 1) return badges.first;
    final best = tracks.reduce((a, b) => (a.bitDepth * a.sampleRate) >= (b.bitDepth * b.sampleRate) ? a : b);
    return 'Mixed · up to ${best.badge}';
  }
}

int compareAlbumOrder(Track a, Track b) {
  final d = (a.discNo ?? 1).compareTo(b.discNo ?? 1);
  if (d != 0) return d;
  final t = (a.trackNo ?? 9999).compareTo(b.trackNo ?? 9999);
  return t != 0 ? t : a.path.compareTo(b.path);
}

// ---------------------------------------------------------------- album grouping

const variousArtists = 'Various Artists';

class GroupInput {
  const GroupInput(this.id, this.folder, this.album, this.artist, this.albumArtistTag, this.compilation);
  final int id;
  final String folder, album;
  final String? artist, albumArtistTag;
  final bool compilation;
}

/// Decides each track's album artist and album key. Rules, in order:
/// 1. the track's own ALBUMARTIST tag;
/// 2. else the ALBUMARTIST tag shared by other tracks of the same album in the same folder;
/// 3. else "Various Artists" if the folder's album is marked compilation or has several artists;
/// 4. else the track artist.
/// Albums are then keyed by album artist + album name, so CD1/CD2 folders join up.
Map<int, (String, String)> groupAlbums(Iterable<GroupInput> tracks) {
  final groups = <String, List<GroupInput>>{};
  for (final t in tracks) {
    groups.putIfAbsent('${t.folder.toLowerCase()}\u0000${t.album.toLowerCase()}', () => []).add(t);
  }
  final out = <int, (String, String)>{};
  for (final g in groups.values) {
    final tagged = <String, int>{};
    for (final t in g) {
      if (t.albumArtistTag != null) tagged[t.albumArtistTag!] = (tagged[t.albumArtistTag!] ?? 0) + 1;
    }
    final artists = {for (final t in g) t.artist?.toLowerCase()}..remove(null);
    final String groupArtist;
    if (tagged.isNotEmpty) {
      groupArtist = tagged.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
    } else if (g.any((t) => t.compilation) || artists.length > 1) {
      groupArtist = variousArtists;
    } else {
      groupArtist = g.first.artist ?? 'Unknown artist';
    }
    for (final t in g) {
      final aa = t.albumArtistTag ?? groupArtist;
      out[t.id] = (aa, '${aa.toLowerCase()}\u0000${t.album.toLowerCase()}');
    }
  }
  return out;
}
