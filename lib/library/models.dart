import 'package:path/path.dart' as p;

/// The columns [Track.fromValues] reads, in its order.
const trackColumns =
    'id, path, folder, title, artist, album_artist, album, album_key, track_no, disc_no, year, genre, duration_ms, codec, sample_rate, '
    'bit_depth, bitrate, cover, added_at, composer, work, movement, movement_no, artist_sort, album_artist_sort, album_sort, rg_track_gain, rg_track_peak, rg_album_gain, rg_album_peak, cue_start_ms';

class Track {
  Track({
    required this.id,
    this.path = '',
    this.folder = '',
    required this.title,
    this.artist = 'Unknown artist',
    List<String>? artists,
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
    this.composer,
    this.work,
    this.movement,
    this.movementNo,
    this.artistSort,
    this.albumArtistSort,
    this.albumSort,
    this.rgTrackGain,
    this.rgTrackPeak,
    this.rgAlbumGain,
    this.rgAlbumPeak,
    this.startMs,
  }) : artists = artists ?? [artist],
       albumArtist = albumArtist ?? artist,
       albumKey = albumKey ?? '${(albumArtist ?? artist).toLowerCase()}\u0000${album.toLowerCase()}';

  /// The values of a `SELECT $trackColumns` row, by position (name lookups add up over 20k rows).
  /// [artists] are the names for artist pages (see [splitArtist]). [albumKey] and
  /// [albumArtist] override the row while a first scan has not grouped it yet.
  Track.fromValues(List<Object?> v, this.artists, [String? albumKey, String? albumArtist])
    : id = v[0] as int,
      startMs = v[30] as int?,
      path = v[30] == null ? v[1] as String : cueFile(v[1] as String),
      folder = v[2] as String,
      title = v[3] as String,
      artist = v[4] as String? ?? 'Unknown artist',
      albumArtist = albumArtist ?? v[5] as String,
      album = v[6] as String,
      albumKey = albumKey ?? v[7] as String,
      trackNo = v[8] as int?,
      discNo = v[9] as int?,
      year = v[10] as int?,
      genre = v[11] as String?,
      durationMs = v[12] as int,
      codec = v[13] as String,
      sampleRate = v[14] as int,
      bitDepth = v[15] as int,
      bitrate = v[16] as int,
      cover = v[17] as String?,
      addedAt = v[18] as int,
      composer = v[19] as String?,
      work = v[20] as String?,
      movement = v[21] as String?,
      movementNo = v[22] as int?,
      artistSort = v[23] as String?,
      albumArtistSort = v[24] as String?,
      albumSort = v[25] as String?,
      rgTrackGain = (v[26] as num?)?.toDouble(),
      rgTrackPeak = (v[27] as num?)?.toDouble(),
      rgAlbumGain = (v[28] as num?)?.toDouble(),
      rgAlbumPeak = (v[29] as num?)?.toDouble();

  final int id;
  final String path, folder, title, artist, albumArtist, album, albumKey, codec;
  final List<String> artists;
  final int? trackNo, discNo, year, movementNo;
  final String? genre, cover, composer, work, movement, artistSort, albumArtistSort, albumSort;

  /// ReplayGain: gain in dB, peak as a linear ratio, when the file is tagged (Opus R128 is converted).
  final double? rgTrackGain, rgTrackPeak, rgAlbumGain, rgAlbumPeak;
  final int durationMs, sampleRate, bitDepth, bitrate, addedAt;

  /// A CUE track: where it starts in its file ([path], shared with the album's other tracks). Null for a whole file.
  final int? startMs;

  Duration get duration => Duration(milliseconds: durationMs);

  /// Genre values: a tag "Rock; Pop" or "Rock/Pop" is two genres.
  List<String> get genres => splitGenres(genre);

  /// "FLAC 24/96", "WAV 16/44.1", "MP3 320k", "DSD64"; "FLAC 16/44.1 · CUE" for a CUE track.
  String get badge => '${formatBadge(codec, bitDepth, sampleRate, bitrate)}${startMs == null ? '' : ' · CUE'}';
}

/// A CUE track's file: its database path is `<file>#<track no>` (unique per track).
String cueFile(String dbPath) => dbPath.substring(0, dbPath.lastIndexOf('#'));

List<String> splitGenres(String? g) => g == null
    ? const []
    : [
        for (final x in g.split(RegExp(r'[;/]')))
          if (x.trim().isNotEmpty) x.trim(),
      ];

String formatBadge(String codec, int bitDepth, int sampleRate, int bitrate) {
  if (codec == 'DSD' && sampleRate > 0) return 'DSD${(sampleRate / 44100).round()}';
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

  /// ALBUMSORT / ALBUMARTISTSORT tags when present, for sorting.
  String get sortTitle => tracks.map((t) => t.albumSort).whereType<String>().firstOrNull ?? title;
  String get sortArtist => tracks.map((t) => t.albumArtistSort).whereType<String>().firstOrNull ?? artist;
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

/// The best-sounding of some copies of a song (Duplicates' "Best copy"): the most bits × rate, then the highest bitrate.
Track bestCopy(List<Track> copies) {
  int q(Track t) => t.bitDepth * t.sampleRate * 100000 + t.bitrate;
  return copies.reduce((a, b) => q(b) > q(a) ? b : a);
}

int compareAlbumOrder(Track a, Track b) {
  final d = (a.discNo ?? 1).compareTo(b.discNo ?? 1);
  if (d != 0) return d;
  final t = (a.trackNo ?? 9999).compareTo(b.trackNo ?? 9999);
  return t != 0 ? t : a.path.compareTo(b.path);
}

/// Lower case, letters and digits only: "Don't Stop!" and "dont stop" match.
String normalise(String s) => s.toLowerCase().replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), '');

// ---------------------------------------------------------------- artist names

final _feat = RegExp(r'\s*[(\[]?\b(?:feat\.?|ft\.?|featuring)\s+', caseSensitive: false);
final _joiners = RegExp(r'\s*(?:,|&|\s+x\s+)\s*', caseSensitive: false);
final _maySplit = RegExp(r'feat|ft|[,&]|\sx\s', caseSensitive: false);
final _brackets = RegExp(r'^[\s(\[]+|[\s)\]]+$');

/// The main artist: the part before "feat."/"ft."/"featuring".
String primaryArtist(String a) => a.split(_feat).first.trim();

/// Splits one artist tag value into names for artist pages. "feat./ft./featuring"
/// always splits. "&", "," and " x " split only when the whole name is not a
/// known act ([band]: album artists, names from ARTISTS tags) and at least one
/// part is a name seen on its own ([solo]), so "Simon & Garfunkel" stays whole.
List<String> splitArtist(String raw, {bool Function(String lower)? band, bool Function(String lower)? solo}) {
  if (!_maySplit.hasMatch(raw)) return [raw];
  final out = <String>[];
  for (var part in raw.split(_feat)) {
    part = part.replaceAll(_brackets, '');
    if (part.isEmpty) continue;
    final pieces = [
      for (final x in part.split(_joiners))
        if (x.trim().isNotEmpty) x.trim(),
    ];
    if (pieces.length > 1 && !(band?.call(part.toLowerCase()) ?? false) && pieces.any((x) => solo?.call(x.toLowerCase()) ?? false)) {
      out.addAll(pieces);
    } else {
      out.add(part);
    }
  }
  return out;
}

// ---------------------------------------------------------------- album grouping

const variousArtists = 'Various Artists';
final _discFolder = RegExp(r'^(cd|dis[ck])\s*\d+$', caseSensitive: false);
final _discSuffix = RegExp(r'[\s_\-]*[(\[]?\s*(cd|dis[ck])\s*\d+\s*[)\]]?$', caseSensitive: false);

/// The folder that stands for the album: "Album\CD1" is "Album", "Album (Disc 2)" is "Album".
String albumFolder(String folder) {
  final base = p.basename(folder);
  if (_discFolder.hasMatch(base)) return p.dirname(folder);
  final stripped = base.replaceFirst(_discSuffix, '');
  return stripped.isEmpty || stripped == base ? folder : p.join(p.dirname(folder), stripped);
}

class GroupInput {
  const GroupInput(this.id, this.folder, this.album, this.artist, this.albumArtistTag, this.compilation, [this.mbAlbumId]);
  final int id;
  final String folder, album;
  final String? artist, albumArtistTag, mbAlbumId;
  final bool compilation;
}

/// Decides each track's album artist and album key. Rules, in order:
/// 1. the track's own ALBUMARTIST tag;
/// 2. else the ALBUMARTIST tag shared by other tracks of the same album in the same album folder;
/// 3. else "Various Artists" if the album is marked compilation, or no main artist has more than half its tracks;
/// 4. else that main artist ("Ana feat. Bo" counts as Ana).
/// Albums are keyed by their MusicBrainz album id when tagged, else by album artist +
/// album name + album folder, so CD1/CD2 folders join up but same-named albums elsewhere don't.
Map<int, (String, String)> groupAlbums(Iterable<GroupInput> tracks) {
  final groups = <String, List<GroupInput>>{};
  for (final t in tracks) {
    groups.putIfAbsent('${albumFolder(t.folder).toLowerCase()}\u0000${t.album.toLowerCase()}', () => []).add(t);
  }
  final out = <int, (String, String)>{};
  for (final g in groups.values) {
    final tagged = <String, int>{};
    final mains = <String, (String, int)>{};
    for (final t in g) {
      if (t.albumArtistTag != null) tagged[t.albumArtistTag!] = (tagged[t.albumArtistTag!] ?? 0) + 1;
      if (t.artist != null) {
        final a = primaryArtist(t.artist!);
        final m = mains[a.toLowerCase()];
        mains[a.toLowerCase()] = (m?.$1 ?? a, (m?.$2 ?? 0) + 1);
      }
    }
    final String groupArtist;
    if (tagged.isNotEmpty) {
      groupArtist = tagged.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
    } else if (g.any((t) => t.compilation)) {
      groupArtist = variousArtists;
    } else if (mains.isEmpty) {
      groupArtist = 'Unknown artist';
    } else {
      final best = mains.values.reduce((a, b) => a.$2 >= b.$2 ? a : b);
      groupArtist = best.$2 * 2 > g.length ? best.$1 : variousArtists;
    }
    for (final t in g) {
      final aa = t.albumArtistTag ?? groupArtist;
      out[t.id] = (
        aa,
        t.mbAlbumId != null
            ? 'mb\u0000${t.mbAlbumId}'
            : '${aa.toLowerCase()}\u0000${t.album.toLowerCase()}\u0000${albumFolder(t.folder).toLowerCase()}',
      );
    }
  }
  return out;
}
