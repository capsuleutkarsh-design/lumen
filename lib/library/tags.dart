// A small pure-Dart tag reader: FLAC, Ogg (Vorbis/Opus/FLAC), MP3 (ID3v2/ID3v1),
// raw AAC (ADTS), MP4/M4A (AAC/ALAC), WAV, AIFF, WebM/Matroska, WavPack, APE
// and DSD (DSF/DFF). Reads only the bytes it needs.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:path/path.dart' as p;

class Tags {
  String? title, artist, albumArtist, album, genre, lyrics, composer, work, movementName;
  String? artistSort, albumArtistSort, albumSort, mbAlbumId;
  int? track, disc, year, movement;
  double? rgTrackGain, rgTrackPeak, rgAlbumGain, rgAlbumPeak;
  bool compilation = false;

  /// Every ARTIST value (multi-value tags keep them all). [artist] is these joined for display.
  final artists = <String>[];

  /// The ARTISTS tag (MusicBrainz Picard): artist names already split by the tagger.
  final artistsTag = <String>[];
  final genres = <String>[];
  int durationMs = 0, sampleRate = 0, bitDepth = 0, channels = 0, bitrate = 0;
  String codec = '';
  Uint8List? picture;
}

const audioExtensions = {
  '.flac',
  '.mp3',
  '.m4a',
  '.mp4',
  '.aac',
  '.alac',
  '.wav',
  '.aif',
  '.aiff',
  '.aifc',
  '.ogg',
  '.oga',
  '.opus',
  '.webm',
  '.mka',
  '.ape',
  '.wv',
  '.dsf',
  '.dff',
  '.wma',
};

/// Never throws: a file we cannot parse still gets a title from its name.
Tags readTags(String path, {bool picture = true}) {
  final t = Tags();
  final ext = p.extension(path).toLowerCase();
  RandomAccessFile? f;
  try {
    f = File(path).openSync();
    final r = _R(f);
    final magic = r.at(0, 12);
    final m4 = latin1.decode(magic.sublist(0, math.min(4, magic.length)));
    if (m4 == 'fLaC') {
      _flac(r, t, picture, 0);
    } else if (m4 == 'OggS') {
      _ogg(r, t, picture);
    } else if (m4 == 'RIFF') {
      _wav(r, t, picture);
    } else if (m4 == 'FORM') {
      _aiff(r, t, picture);
    } else if (magic.length >= 8 && latin1.decode(magic.sublist(4, 8)) == 'ftyp') {
      _mp4(r, t, picture);
    } else if (magic.length >= 4 && magic[0] == 0x1A && magic[1] == 0x45 && magic[2] == 0xDF && magic[3] == 0xA3) {
      _mkv(r, t, picture);
    } else if (m4 == 'wvpk') {
      _wavpack(r, t);
    } else if (m4 == 'MAC ') {
      _ape(r, t);
    } else if (m4 == 'DSD ') {
      _dsf(r, t, picture);
    } else if (m4 == 'FRM8') {
      _dff(r, t, picture);
    } else if (m4.startsWith('ID3') || ext == '.mp3' || ext == '.aac' || _sync(magic, 0)) {
      // ID3v2 tags first, then whatever follows: some taggers put ID3 in front of FLAC or raw AAC too.
      var pos = 0, n = 0;
      while ((n = _id3v2(r, pos, t, picture)) > 0) {
        pos += n;
      }
      final m = r.at(pos, 4);
      if (_starts(m, 0, 'fLaC')) {
        _flac(r, t, picture, pos);
      } else if (_adts(m, 0)) {
        _aac(r, t, pos);
      } else {
        _mp3(r, t, pos);
      }
    } else {
      t.codec = ext.replaceFirst('.', '').toUpperCase();
    }
  } catch (_) {
    // Keep whatever was read before the error.
  } finally {
    f?.closeSync();
  }
  t.title = _clean(t.title) ?? p.basenameWithoutExtension(path);
  final arts = _values(t.artists);
  t.artists
    ..clear()
    ..addAll(arts);
  final tagged = _values(t.artistsTag);
  t.artistsTag
    ..clear()
    ..addAll(tagged);
  t.artist = arts.isEmpty ? null : arts.join(', ');
  final genres = _values(t.genres);
  t.genre = genres.isEmpty ? null : genres.join('; ');
  t.albumArtist = _clean(t.albumArtist);
  t.album = _clean(t.album);
  t.composer = _clean(t.composer);
  t.work = _clean(t.work);
  t.movementName = _clean(t.movementName);
  t.artistSort = _clean(t.artistSort);
  t.albumArtistSort = _clean(t.albumArtistSort);
  t.albumSort = _clean(t.albumSort);
  t.mbAlbumId = _clean(t.mbAlbumId);
  return t;
}

String? _clean(String? s) {
  final v = s?.replaceAll('\u0000', '').trim();
  return (v == null || v.isEmpty) ? null : v;
}

/// Cleaned, non-empty values without case-insensitive repeats.
List<String> _values(List<String> xs) {
  final seen = <String>{};
  return [
    for (final x in xs.map(_clean).whereType<String>())
      if (seen.add(x.toLowerCase())) x,
  ];
}

class _R {
  _R(this.f) : length = f.lengthSync();
  final RandomAccessFile f;
  final int length;

  /// At most [n] bytes at [pos], never past the end: a bogus size field cannot allocate more than the file.
  Uint8List at(int pos, int n) {
    if (pos < 0 || pos >= length || n <= 0) return Uint8List(0);
    f.setPositionSync(pos);
    return f.readSync(math.min(n, length - pos));
  }
}

int _be(List<int> b, int o, int n) {
  var v = 0;
  for (var i = 0; i < n; i++) {
    v = (v << 8) | b[o + i];
  }
  return v;
}

int _le(List<int> b, int o, int n) {
  var v = 0;
  for (var i = n - 1; i >= 0; i--) {
    v = (v << 8) | b[o + i];
  }
  return v;
}

int? _num(String? s) => s == null ? null : int.tryParse(RegExp(r'\d{1,9}').firstMatch(s)?.group(0) ?? '');

/// The first four-digit run is the year ("05/01/2017" is 2017); else any number.
int? _year(String s) => int.tryParse(RegExp(r'\d{4}').firstMatch(s)?.group(0) ?? '') ?? _num(s);

double? _dbl(String s) => double.tryParse(RegExp(r'[-+]?\d+(\.\d+)?').firstMatch(s)?.group(0) ?? '');

/// Opus R128 gain is Q7.8 dB relative to -23 LUFS; ReplayGain's reference is -18 LUFS.
double? _r128(String s) {
  final v = int.tryParse(s.trim());
  return v == null ? null : v / 256 + 5;
}

/// UTF-8 when the bytes are valid UTF-8, else Latin-1 (Windows tools write ANSI).
String _utf8OrLatin1(List<int> b) {
  try {
    return utf8.decode(b);
  } on FormatException {
    return latin1.decode(b);
  }
}

// ---------------------------------------------------------------- one place for tag meanings

/// Applies one tag, named as in Vorbis comments. Each format maps its own names here.
/// NUL-separated values (ID3v2.4, APEv2) are kept as separate values.
void _set(Tags t, String key, String value) {
  for (final v in value.split('\u0000')) {
    if (v.trim().isEmpty) continue;
    switch (key.toUpperCase()) {
      case 'TITLE':
        t.title ??= v;
      case 'ARTIST':
        t.artists.add(v);
      case 'ARTISTS':
        t.artistsTag.add(v);
      case 'ALBUMARTIST' || 'ALBUM ARTIST' || 'ALBUM_ARTIST':
        t.albumArtist ??= v;
      case 'ALBUM':
        t.album ??= v;
      case 'GENRE':
        t.genres.add(v);
      case 'TRACKNUMBER' || 'TRACK' || 'PART_NUMBER':
        t.track ??= _num(v);
      case 'DISCNUMBER' || 'DISC':
        t.disc ??= _num(v);
      case 'DATE' || 'YEAR' || 'ORIGINALDATE' || 'ORIGINALYEAR' || 'DATE_RELEASED' || 'DATE_RECORDED':
        t.year ??= _year(v);
      case 'COMPILATION':
        t.compilation = v.trim() == '1';
      case 'LYRICS' || 'UNSYNCEDLYRICS':
        t.lyrics ??= v;
      case 'COMPOSER':
        t.composer ??= v;
      case 'WORK':
        t.work ??= v;
      case 'MOVEMENTNAME':
        t.movementName ??= v;
      case 'MOVEMENT':
        t.movement ??= _num(v);
      case 'ARTISTSORT':
        t.artistSort ??= v;
      case 'ALBUMARTISTSORT':
        t.albumArtistSort ??= v;
      case 'ALBUMSORT':
        t.albumSort ??= v;
      case 'MUSICBRAINZ_ALBUMID' || 'MUSICBRAINZ ALBUM ID':
        t.mbAlbumId ??= v.trim().toLowerCase();
      case 'REPLAYGAIN_TRACK_GAIN':
        t.rgTrackGain ??= _dbl(v);
      case 'REPLAYGAIN_TRACK_PEAK':
        t.rgTrackPeak ??= _dbl(v);
      case 'REPLAYGAIN_ALBUM_GAIN':
        t.rgAlbumGain ??= _dbl(v);
      case 'REPLAYGAIN_ALBUM_PEAK':
        t.rgAlbumPeak ??= _dbl(v);
      case 'R128_TRACK_GAIN':
        t.rgTrackGain ??= _r128(v);
      case 'R128_ALBUM_GAIN':
        t.rgAlbumGain ??= _r128(v);
    }
  }
}

// ---------------------------------------------------------------- Vorbis comments

void _vorbisComments(Uint8List b, int o, Tags t, bool picture) {
  final vendor = _le(b, o, 4);
  o += 4 + vendor;
  final n = _le(b, o, 4);
  o += 4;
  for (var i = 0; i < n && o + 4 <= b.length; i++) {
    final len = _le(b, o, 4);
    o += 4;
    if (o + len > b.length) break;
    final s = utf8.decode(b.sublist(o, o + len), allowMalformed: true);
    o += len;
    final eq = s.indexOf('=');
    if (eq < 0) continue;
    final k = s.substring(0, eq).toUpperCase(), v = s.substring(eq + 1);
    try {
      if (k == 'METADATA_BLOCK_PICTURE') {
        if (picture && t.picture == null) t.picture = _flacPicture(base64.decode(v.trim()));
      } else {
        _set(t, k, v);
      }
    } catch (_) {
      // A broken field (e.g. bad base64 cover) must not lose the fields after it.
    }
  }
}

Uint8List? _flacPicture(Uint8List b) {
  var o = 4;
  o += 4 + _be(b, o, 4); // mime
  o += 4 + _be(b, o, 4); // description
  o += 16;
  final len = _be(b, o, 4);
  return b.sublist(o + 4, o + 4 + len);
}

// ---------------------------------------------------------------- FLAC

void _flac(_R r, Tags t, bool picture, int start) {
  t.codec = 'FLAC';
  var pos = start + 4, blockSize = 0;
  Uint8List? fallbackPic;
  while (pos + 4 <= r.length) {
    final h = r.at(pos, 4);
    final last = h[0] & 0x80 != 0, type = h[0] & 0x7F, len = _be(h, 1, 3);
    if (type == 0) {
      final b = r.at(pos + 4, len);
      blockSize = _be(b, 0, 2);
      _streamInfo(b, 0, t);
    } else if (type == 4) {
      _vorbisComments(r.at(pos + 4, len), 0, t, picture);
    } else if (type == 6 && picture && t.picture == null) {
      final b = r.at(pos + 4, len);
      if (_be(b, 0, 4) == 3) {
        t.picture = _flacPicture(b);
      } else {
        fallbackPic ??= _flacPicture(b);
      }
    }
    pos += 4 + len;
    if (last) break;
  }
  t.picture ??= fallbackPic;
  if (t.durationMs == 0 && t.sampleRate > 0) t.durationMs = _flacTailDuration(r, blockSize, t.sampleRate);
  if (t.durationMs > 0) t.bitrate = ((r.length - pos) * 8 / t.durationMs).round();
}

void _streamInfo(Uint8List b, int o, Tags t) {
  final x = _be(b, o + 10, 8); // 20 bits rate, 3 channels-1, 5 bps-1, 36 total samples
  t.sampleRate = x >>> 44;
  t.channels = ((x >> 41) & 7) + 1;
  t.bitDepth = ((x >> 36) & 31) + 1;
  final samples = x & 0xFFFFFFFFF;
  if (t.sampleRate > 0) t.durationMs = samples * 1000 ~/ t.sampleRate;
}

// ---------------------------------------------------------------- Ogg

void _ogg(_R r, Tags t, bool picture) {
  // Collect the first two packets (header + comments), page by page.
  final packets = <BytesBuilder>[BytesBuilder()];
  var pos = 0;
  while (packets.length < 3 && pos + 27 <= r.length) {
    final h = r.at(pos, 27);
    final nseg = h[26];
    final segs = r.at(pos + 27, nseg);
    var data = pos + 27 + nseg;
    for (final s in segs) {
      packets.last.add(r.at(data, s));
      data += s;
      if (s < 255) packets.add(BytesBuilder());
    }
    pos = data;
  }
  final head = packets[0].toBytes(), tags = packets[1].toBytes();
  var rate = 0, preskip = 0;
  if (_starts(head, 1, 'vorbis')) {
    t.codec = 'Vorbis';
    t.channels = head[11];
    rate = t.sampleRate = _le(head, 12, 4);
    _vorbisComments(tags, 7, t, picture);
  } else if (_starts(head, 0, 'OpusHead')) {
    t.codec = 'Opus';
    t.channels = head[9];
    preskip = _le(head, 10, 2);
    rate = 48000;
    t.sampleRate = 48000;
    _vorbisComments(tags, 8, t, picture);
  } else if (_starts(head, 1, 'FLAC')) {
    t.codec = 'FLAC';
    _streamInfo(head, 17, t);
    rate = t.sampleRate;
    _vorbisComments(tags, 4, t, picture);
  }
  // Duration from the last page's granule position.
  final tailStart = r.length > 65536 ? r.length - 65536 : 0;
  final tail = r.at(tailStart, r.length - tailStart);
  for (var i = tail.length - 27; i >= 0; i--) {
    if (tail[i] == 0x4F && _starts(tail, i, 'OggS')) {
      final granule = _le(tail, i + 6, 8);
      if (rate > 0 && granule > 0) t.durationMs = (granule - preskip) * 1000 ~/ rate;
      break;
    }
  }
  // Leave the comment packet (which holds any cover art) out of the bitrate.
  if (t.durationMs > 0) t.bitrate = ((r.length - tags.length) * 8 / t.durationMs).round();
}

bool _starts(List<int> b, int o, String s) {
  if (o + s.length > b.length) return false;
  for (var i = 0; i < s.length; i++) {
    if (b[o + i] != s.codeUnitAt(i)) return false;
  }
  return true;
}

// ---------------------------------------------------------------- ID3v2 / MP3

const _id3Genres = [
  'Blues',
  'Classic Rock',
  'Country',
  'Dance',
  'Disco',
  'Funk',
  'Grunge',
  'Hip-Hop',
  'Jazz',
  'Metal',
  'New Age',
  'Oldies',
  'Other',
  'Pop',
  'R&B',
  'Rap',
  'Reggae',
  'Rock',
  'Techno',
  'Industrial',
  'Alternative',
  'Ska',
  'Death Metal',
  'Pranks',
  'Soundtrack',
  'Euro-Techno',
  'Ambient',
  'Trip-Hop',
  'Vocal',
  'Jazz+Funk',
  'Fusion',
  'Trance',
  'Classical',
  'Instrumental',
  'Acid',
  'House',
  'Game',
  'Sound Clip',
  'Gospel',
  'Noise',
  'Alt. Rock',
  'Bass',
  'Soul',
  'Punk',
  'Space',
  'Meditative',
  'Instrumental Pop',
  'Instrumental Rock',
  'Ethnic',
  'Gothic',
  'Darkwave',
  'Techno-Industrial',
  'Electronic',
  'Pop-Folk',
  'Eurodance',
  'Dream',
  'Southern Rock',
  'Comedy',
  'Cult',
  'Gangsta',
  'Top 40',
  'Christian Rap',
  'Pop/Funk',
  'Jungle',
  'Native American',
  'Cabaret',
  'New Wave',
  'Psychedelic',
  'Rave',
  'Showtunes',
  'Trailer',
  'Lo-Fi',
  'Tribal',
  'Acid Punk',
  'Acid Jazz',
  'Polka',
  'Retro',
  'Musical',
  'Rock & Roll',
  'Hard Rock',
];

String _genre(String g) {
  final m = RegExp(r'^(?:\((\d+)\)(.*)|(\d+))$').firstMatch(g.trim());
  if (m == null) return g;
  if ((m.group(2) ?? '').isNotEmpty) return m.group(2)!;
  final i = int.tryParse(m.group(1) ?? m.group(3)!) ?? 999;
  return i < _id3Genres.length ? _id3Genres[i] : g;
}

/// Decodes an ID3 text field, keeping NUL separators between multiple values.
String _text(Uint8List b, int enc) {
  if (enc == 1 || enc == 2) {
    var o = 0;
    var bigEndian = enc == 2;
    if (b.length >= 2 && ((b[0] == 0xFF && b[1] == 0xFE) || (b[0] == 0xFE && b[1] == 0xFF))) {
      bigEndian = b[0] == 0xFE;
      o = 2;
    }
    final units = <int>[];
    for (; o + 1 < b.length; o += 2) {
      final u = bigEndian ? (b[o] << 8) | b[o + 1] : b[o] | (b[o + 1] << 8);
      if (u == 0xFEFF && units.isNotEmpty && units.last == 0) continue; // BOM of the next value
      units.add(u);
    }
    return String.fromCharCodes(units);
  }
  return enc == 3 ? utf8.decode(b, allowMalformed: true) : latin1.decode(b);
}

String _first(String s) => s.split('\u0000').first;

/// Index just past a NUL terminator for [enc] starting at [o].
int _skipZ(Uint8List b, int o, int enc) {
  if (enc == 1 || enc == 2) {
    while (o + 1 < b.length && (b[o] != 0 || b[o + 1] != 0)) {
      o += 2;
    }
    return o + 2;
  }
  while (o < b.length && b[o] != 0) {
    o++;
  }
  return o + 1;
}

Uint8List _unsync(Uint8List b) {
  final out = BytesBuilder();
  for (var i = 0; i < b.length; i++) {
    out.addByte(b[i]);
    if (b[i] == 0xFF && i + 1 < b.length && b[i + 1] == 0) i++;
  }
  return out.toBytes();
}

const _id3Keys = {
  'TIT2': 'TITLE', 'TT2': 'TITLE', 'TPE1': 'ARTIST', 'TP1': 'ARTIST', 'TPE2': 'ALBUMARTIST', 'TP2': 'ALBUMARTIST', //
  'TALB': 'ALBUM', 'TAL': 'ALBUM', 'TRCK': 'TRACKNUMBER', 'TRK': 'TRACKNUMBER', 'TPOS': 'DISCNUMBER', 'TPA': 'DISCNUMBER',
  'TDRC': 'DATE', 'TYER': 'DATE', 'TYE': 'DATE', 'TDOR': 'DATE', 'TORY': 'DATE', 'TCMP': 'COMPILATION', 'TCP': 'COMPILATION',
  'TCOM': 'COMPOSER', 'TCM': 'COMPOSER', 'TIT1': 'WORK', 'TT1': 'WORK', 'MVNM': 'MOVEMENTNAME', 'MVIN': 'MOVEMENT',
  'TSO2': 'ALBUMARTISTSORT', 'TSOP': 'ARTISTSORT', 'TSOA': 'ALBUMSORT',
};

/// A frame ID (or padding / the end) starts at [o]: used to tell syncsafe from plain v2.4 sizes.
bool _frameAt(Uint8List b, int o) {
  if (o == b.length || (o < b.length && b[o] == 0)) return true;
  if (o + 4 > b.length) return false;
  for (var i = 0; i < 4; i++) {
    final c = b[o + i];
    if (!((c >= 0x41 && c <= 0x5A) || (c >= 0x30 && c <= 0x39))) return false;
  }
  return true;
}

/// Parses an ID3v2 tag at [pos]; returns its total size (0 if none).
int _id3v2(_R r, int pos, Tags t, bool picture) {
  final h = r.at(pos, 10);
  if (h.length < 10 || !_starts(h, 0, 'ID3')) return 0;
  final ver = h[3], flags = h[5];
  final size = (h[6] << 21) | (h[7] << 14) | (h[8] << 7) | h[9];
  var b = r.at(pos + 10, size);
  if (ver < 4 && flags & 0x80 != 0) b = _unsync(b);
  var o = 0;
  if (flags & 0x40 != 0) o += ver == 4 ? _syncsafe(b, 0) : 4 + _be(b, 0, 4);
  final idLen = ver == 2 ? 3 : 4, hdr = ver == 2 ? 6 : 10;
  while (o + hdr <= b.length && b[o] != 0) {
    final id = latin1.decode(b.sublist(o, o + idLen));
    var len = ver == 2 ? _be(b, o + 3, 3) : _be(b, o + 4, 4);
    if (ver == 4) {
      // Old iTunes wrote plain sizes in v2.4 tags: use the plain size when the syncsafe one leads nowhere.
      final ss = _syncsafe(b, o + 4);
      final plain = len;
      final notSyncsafe = b[o + 4] | b[o + 5] | b[o + 6] | b[o + 7] >= 0x80;
      len = notSyncsafe || (!_frameAt(b, o + hdr + ss) && _frameAt(b, o + hdr + plain)) ? plain : ss;
    }
    final fmt = ver == 2 ? 0 : b[o + 9];
    o += hdr;
    if (len < 0 || o + len > b.length) break;
    if (len == 0) continue; // an empty frame: skip it, keep reading
    var d = b.sublist(o, o + len);
    o += len;
    try {
      if (ver == 4) {
        if (fmt & 0x01 != 0) d = d.sublist(4);
        if (fmt & 0x02 != 0) d = _unsync(d);
      }
      if (d.isEmpty) continue;
      final key = _id3Keys[id];
      if (key != null) {
        final v = _text(d.sublist(1), d[0]);
        _set(t, key, v);
        continue;
      }
      switch (id) {
        case 'TCON' || 'TCO':
          for (final g in _text(d.sublist(1), d[0]).split('\u0000')) {
            _set(t, 'GENRE', _genre(g));
          }
        case 'TLEN' || 'TLE':
          t.durationMs = t.durationMs > 0 ? t.durationMs : (_num(_first(_text(d.sublist(1), d[0]))) ?? 0);
        case 'TXXX' || 'TXX':
          final enc = d[0], z = _skipZ(d, 1, enc);
          _set(t, _first(_text(d.sublist(1, math.min(z, d.length)), enc)), _text(d.sublist(math.min(z, d.length)), enc));
        case 'USLT' || 'ULT':
          final enc = d[0], z = _skipZ(d, 4, enc);
          t.lyrics ??= _first(_text(d.sublist(z), enc)).replaceAll('\r\n', '\n');
        case 'APIC' || 'PIC':
          if (!picture) break;
          final enc = d[0];
          var q = ver == 2 ? 4 : _skipZ(d, 1, 0); // v2.2 has a 3-byte format
          final type = d[q];
          q = _skipZ(d, q + 1, enc);
          if (t.picture == null || type == 3) t.picture = d.sublist(q);
      }
    } catch (_) {
      // One bad frame must not lose the rest.
    }
  }
  return 10 + size + (flags & 0x10 != 0 ? 10 : 0);
}

int _syncsafe(List<int> b, int o) => (b[o] << 21) | (b[o + 1] << 14) | (b[o + 2] << 7) | b[o + 3];

const _mpegRates = [
  [11025, 12000, 8000], [0, 0, 0], [22050, 24000, 16000], [44100, 48000, 32000], // MPEG 2.5, -, 2, 1
];
const _l3Bitrates = [
  [0, 32, 40, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320], // MPEG1 L3
  [0, 8, 16, 24, 32, 40, 48, 56, 64, 80, 96, 112, 128, 144, 160], // MPEG2/2.5 L3
];

/// An MPEG audio frame sync (MP3 or ADTS AAC).
bool _sync(List<int> b, int o) => o + 1 < b.length && b[o] == 0xFF && b[o + 1] & 0xE0 == 0xE0;

/// An ADTS (raw AAC) header: sync with layer bits 00.
bool _adts(List<int> b, int o) => o + 1 < b.length && b[o] == 0xFF && b[o + 1] & 0xF6 == 0xF0;

/// MP3 audio starting at [pos] (just past any ID3v2 tags, already read).
void _mp3(_R r, Tags t, int pos) {
  t.codec = 'MP3';
  if (t.title == null && r.length > 128) {
    final v1 = r.at(r.length - 128, 128);
    if (_starts(v1, 0, 'TAG')) {
      String s(int o, int l) => latin1.decode(v1.sublist(o, o + l)).split('\u0000').first.trim();
      t.title = s(3, 30);
      if (t.artists.isEmpty) _set(t, 'ARTIST', s(33, 30));
      t.album ??= s(63, 30);
      t.year ??= _num(s(93, 4));
      if (v1[125] == 0 && v1[126] != 0) t.track ??= v1[126];
    }
  }
  // First frame header (search a little in case of padding/junk).
  final buf = r.at(pos, 16384);
  for (var i = 0; i + 4 < buf.length; i++) {
    if (buf[i] != 0xFF || buf[i + 1] & 0xE0 != 0xE0) continue;
    final ver = (buf[i + 1] >> 3) & 3, layer = (buf[i + 1] >> 1) & 3;
    final bri = buf[i + 2] >> 4, sri = (buf[i + 2] >> 2) & 3;
    if (ver == 1 || layer != 1 || bri == 0 || bri == 15 || sri == 3) continue;
    t.sampleRate = _mpegRates[ver][sri];
    final mono = buf[i + 3] >> 6 == 3;
    t.channels = mono ? 1 : 2;
    final kbps = _l3Bitrates[ver == 3 ? 0 : 1][bri];
    final spf = ver == 3 ? 1152 : 576;
    final side = ver == 3 ? (mono ? 17 : 32) : (mono ? 9 : 17);
    final x = i + 4 + side;
    if (x + 12 < buf.length && (_starts(buf, x, 'Xing') || _starts(buf, x, 'Info')) && buf[x + 7] & 1 != 0) {
      final frames = _be(buf, x + 8, 4);
      t.durationMs = frames * spf * 1000 ~/ t.sampleRate;
    } else if (i + 36 + 18 < buf.length && _starts(buf, i + 36, 'VBRI')) {
      t.durationMs = _be(buf, i + 36 + 14, 4) * spf * 1000 ~/ t.sampleRate;
    } else if (t.durationMs == 0) {
      t.durationMs = (r.length - pos - i) * 8 ~/ kbps;
    }
    t.bitrate = t.durationMs > 0 ? ((r.length - pos - i) * 8 / t.durationMs).round() : kbps;
    break;
  }
}

const _aacRates = [96000, 88200, 64000, 48000, 44100, 32000, 24000, 22050, 16000, 12000, 11025, 8000, 7350];

/// Raw AAC (ADTS): rate and channels from the first header, length estimated from the first 64 KB of frames.
void _aac(_R r, Tags t, int pos) {
  t.codec = 'AAC';
  final b = r.at(pos, 65536);
  var o = 0, frames = 0;
  while (o + 7 <= b.length && _adts(b, o)) {
    if (frames == 0) {
      final sri = (b[o + 2] >> 2) & 15;
      t.sampleRate = sri < _aacRates.length ? _aacRates[sri] : 0;
      t.channels = ((b[o + 2] & 1) << 2) | (b[o + 3] >> 6);
    }
    final len = ((b[o + 3] & 3) << 11) | (b[o + 4] << 3) | (b[o + 5] >> 5);
    if (len < 7) break;
    o += len;
    frames++;
  }
  if (frames > 0 && t.sampleRate > 0) {
    final perFrame = o / frames;
    t.durationMs = ((r.length - pos) / perFrame * 1024 * 1000 / t.sampleRate).round();
    t.bitrate = (perFrame * 8 * t.sampleRate / 1024 / 1000).round();
  }
}

// ---------------------------------------------------------------- MP4 / M4A

void _mp4(_R r, Tags t, bool picture) {
  var pos = 0, mdat = 0;
  while (pos + 8 <= r.length) {
    final h = r.at(pos, 16);
    var size = _be(h, 0, 4), hdr = 8;
    final type = latin1.decode(h.sublist(4, 8));
    if (size == 1 && h.length >= 16) {
      size = _be(h, 8, 8); // 64-bit size: the box body starts after 16 bytes
      hdr = 16;
    }
    if (size == 0) size = r.length - pos;
    if (size < hdr) break;
    if (type == 'moov') _atoms(r.at(pos + hdr, size - hdr), t, picture);
    if (type == 'mdat') mdat += size - hdr;
    pos += size;
  }
  if (t.codec.isEmpty) t.codec = 'AAC';
  // The audio data alone, so cover art does not count towards the bitrate.
  final audio = mdat > 0 ? math.min(mdat, r.length) : r.length;
  if (t.durationMs > 0) t.bitrate = (audio * 8 / t.durationMs).round();
}

const _audioEntries = {'mp4a': 'AAC', 'alac': 'ALAC', 'fLaC': 'FLAC', 'Opus': 'Opus'};

void _atoms(Uint8List b, Tags t, bool picture, [String parent = '']) {
  var o = 0;
  while (o + 8 <= b.length) {
    var size = _be(b, o, 4);
    final type = latin1.decode(b.sublist(o + 4, o + 8));
    if (size < 8 || o + size > b.length) size = b.length - o;
    final body = b.sublist(o + 8, o + size);
    switch (type) {
      case 'trak' || 'mdia' || 'minf' || 'stbl' || 'udta' || 'ilst':
        _atoms(body, t, picture, type);
      case 'meta':
        if (body.length > 4) _atoms(body.sublist(4), t, picture, type);
      case 'mdhd':
        final v1 = body[0] == 1;
        final scale = _be(body, v1 ? 20 : 12, 4), dur = _be(body, v1 ? 24 : 16, v1 ? 8 : 4);
        if (scale > 0 && t.durationMs == 0) t.durationMs = dur * 1000 ~/ scale;
      case 'stsd':
        // Only audio sample entries: a chapter (text) track must not overwrite the format.
        final entry = latin1.decode(body.sublist(12, 16));
        final codec = _audioEntries[entry];
        if (codec == null || (t.codec.isNotEmpty && t.sampleRate > 0)) break;
        t.codec = codec;
        t.channels = _be(body, 8 + 8 + 16, 2);
        t.bitDepth = _be(body, 8 + 8 + 18, 2);
        t.sampleRate = _be(body, 8 + 8 + 24, 2);
        if (entry == 'alac') {
          // ALACSpecificConfig follows the 36-byte sample entry: size, 'alac', ver/flags, ...
          final c = 8 + 36 + 12;
          if (c + 24 <= body.length) {
            t.bitDepth = body[c + 5];
            t.channels = body[c + 9];
            t.sampleRate = _be(body, c + 20, 4);
          }
        } else if (_lossy(codec)) {
          t.bitDepth = 0;
        }
      default:
        if (parent == 'ilst') {
          try {
            _ilstItem(type, body, t, picture);
          } catch (_) {}
        }
    }
    o += size;
  }
}

const _ilstKeys = {
  '©nam': 'TITLE', '©ART': 'ARTIST', 'aART': 'ALBUMARTIST', '©alb': 'ALBUM', '©gen': 'GENRE', '©day': 'DATE', //
  '©lyr': 'LYRICS', '©wrt': 'COMPOSER', '©wrk': 'WORK', '©mvn': 'MOVEMENTNAME', 'soaa': 'ALBUMARTISTSORT',
  'soar': 'ARTISTSORT', 'soal': 'ALBUMSORT',
};

void _ilstItem(String type, Uint8List b, Tags t, bool picture) {
  if (type == '----') {
    // Freeform: mean, name, data (e.g. com.apple.iTunes:REPLAYGAIN_TRACK_GAIN).
    String? name;
    var o = 0;
    while (o + 8 <= b.length) {
      final size = _be(b, o, 4), kind = latin1.decode(b.sublist(o + 4, o + 8));
      if (size < 8 || o + size > b.length) break;
      if (kind == 'name' && size > 12) name = utf8.decode(b.sublist(o + 12, o + size), allowMalformed: true);
      if (kind == 'data' && name != null && size > 16) _set(t, name, utf8.decode(b.sublist(o + 16, o + size), allowMalformed: true));
      o += size;
    }
    return;
  }
  if (b.length < 16 || latin1.decode(b.sublist(4, 8)) != 'data') return;
  final d = b.sublist(16, _be(b, 0, 4).clamp(16, b.length));
  final key = _ilstKeys[type];
  if (key != null) {
    _set(t, key, utf8.decode(d, allowMalformed: true));
    return;
  }
  switch (type) {
    case 'gnre':
      if (d.length >= 2) _set(t, 'GENRE', _genre('${_be(d, 0, 2) - 1}'));
    case 'trkn':
      if (d.length >= 4) t.track ??= _be(d, 2, 2);
    case 'disk':
      if (d.length >= 4) t.disc ??= _be(d, 2, 2);
    case '©mvi':
      if (d.isNotEmpty && d.length <= 8) t.movement ??= _be(d, 0, d.length);
    case 'cpil':
      t.compilation = d.isNotEmpty && d[0] == 1;
    case 'covr':
      if (picture) t.picture ??= d;
  }
}

// ---------------------------------------------------------------- WAV / AIFF

const _infoKeys = {
  'INAM': 'TITLE', 'IART': 'ARTIST', 'IPRD': 'ALBUM', 'IGNR': 'GENRE', 'ICRD': 'DATE', 'ITRK': 'TRACKNUMBER', //
  'IPRT': 'TRACKNUMBER',
};

void _wav(_R r, Tags t, bool picture) {
  t.codec = 'WAV';
  var pos = 12, byteRate = 0, dataSize = 0;
  while (pos + 8 <= r.length) {
    final h = r.at(pos, 8);
    final id = latin1.decode(h.sublist(0, 4)), size = _le(h, 4, 4);
    if (id == 'fmt ') {
      final b = r.at(pos + 8, size);
      t.channels = _le(b, 2, 2);
      t.sampleRate = _le(b, 4, 4);
      byteRate = _le(b, 8, 4);
      t.bitDepth = _le(b, 14, 2);
      if (_le(b, 0, 2) == 0xFFFE && size >= 20 && _le(b, 18, 2) > 0) t.bitDepth = _le(b, 18, 2);
    } else if (id == 'data') {
      dataSize = math.min(size, r.length - pos - 8); // streamed WAVs write 0xFFFFFFFF
    } else if (id == 'LIST') {
      final b = r.at(pos + 8, size);
      if (_starts(b, 0, 'INFO')) {
        var o = 4;
        while (o + 8 <= b.length) {
          final k = latin1.decode(b.sublist(o, o + 4)), n = _le(b, o + 4, 4);
          if (o + 8 + n > b.length) break;
          final key = _infoKeys[k];
          if (key != null) _set(t, key, _utf8OrLatin1(b.sublist(o + 8, o + 8 + n)));
          o += 8 + n + (n & 1);
        }
      }
    } else if (id.toLowerCase() == 'id3 ') {
      _id3v2(r, pos + 8, t, picture);
    }
    pos += 8 + size + (size & 1);
  }
  if (byteRate > 0) t.durationMs = dataSize * 1000 ~/ byteRate;
  t.bitrate = byteRate * 8 ~/ 1000;
}

void _aiff(_R r, Tags t, bool picture) {
  t.codec = 'AIFF';
  var pos = 12;
  while (pos + 8 <= r.length) {
    final h = r.at(pos, 8);
    final id = latin1.decode(h.sublist(0, 4)), size = _be(h, 4, 4);
    if (id == 'COMM') {
      final b = r.at(pos + 8, size);
      t.channels = _be(b, 0, 2);
      final frames = _be(b, 2, 4);
      t.bitDepth = _be(b, 6, 2);
      // 80-bit extended float: keep the top 53 mantissa bits so the int stays positive.
      final exp = (_be(b, 8, 2) & 0x7FFF) - 16383 - 63 + 11;
      t.sampleRate = ((_be(b, 10, 8) >>> 11) * _pow2(exp)).round();
      if (t.sampleRate > 0) t.durationMs = frames * 1000 ~/ t.sampleRate;
    } else if (id == 'ID3 ' || id == 'id3 ') {
      _id3v2(r, pos + 8, t, picture);
    }
    pos += 8 + size + (size & 1);
  }
  t.bitrate = t.sampleRate * t.bitDepth * t.channels ~/ 1000;
}

double _pow2(int e) => e >= 0 ? (1 << e).toDouble() : 1 / (1 << -e);

// ---------------------------------------------------------------- Matroska / WebM

void _mkv(_R r, Tags t, bool picture) {
  // EBML: read IDs and sizes; descend into Segment, Info, Tracks, TrackEntry, Audio, Tags, Tag, SimpleTag.
  const containers = {0x18538067, 0x1549A966, 0x1654AE6B, 0xAE, 0xE1, 0x1254C367, 0x7373, 0x67C8};
  var scale = 1000000, durationTicks = 0.0;
  String? tagName, segmentTitle;
  double float(Uint8List d) {
    final v = d.length == 4
        ? ByteData.sublistView(d).getFloat32(0)
        : d.length == 8
        ? ByteData.sublistView(d).getFloat64(0)
        : 0.0;
    return v.isFinite ? v : 0.0;
  }

  void walk(int pos, int end) {
    while (pos < end && pos + 2 <= r.length) {
      final b = r.at(pos, 12);
      final idLen = _vlen(b[0]);
      final id = _be(b, 0, idLen);
      final sLen = _vlen(b[idLen]);
      var size = _be(b, idLen, sLen) & ((1 << (7 * sLen)) - 1);
      final data = pos + idLen + sLen;
      if (size == (1 << (7 * sLen)) - 1) size = end - data; // unknown size
      if (containers.contains(id)) {
        walk(data, data + size);
      } else if (id != 0x1F43B675 && size < 1 << 20) {
        // skip Clusters (audio)
        final d = r.at(data, size);
        switch (id) {
          case 0x2AD7B1:
            scale = _be(d, 0, d.length);
          case 0x4489:
            durationTicks = float(d);
          case 0x7BA9:
            segmentTitle = utf8.decode(d, allowMalformed: true);
          case 0x86:
            t.codec = latin1.decode(d).replaceFirst('A_', '').split('/').first;
          case 0xB5:
            t.sampleRate = float(d).round();
          case 0x9F:
            t.channels = _be(d, 0, d.length);
          case 0x6264:
            t.bitDepth = _be(d, 0, d.length);
          case 0x45A3:
            tagName = utf8.decode(d, allowMalformed: true).toUpperCase();
          case 0x4487:
            if (tagName != null) _set(t, tagName!, utf8.decode(d, allowMalformed: true));
        }
      }
      pos = data + size;
    }
  }

  walk(0, r.length);
  t.title ??= segmentTitle;
  t.codec = const {'OPUS': 'Opus', 'VORBIS': 'Vorbis', 'MPEG': 'MP3', 'AAC': 'AAC'}[t.codec] ?? t.codec;
  if (_lossy(t.codec)) t.bitDepth = 0;
  t.durationMs = (durationTicks * scale / 1e6).round();
  if (t.durationMs > 0) t.bitrate = (r.length * 8 / t.durationMs).round();
}

int _vlen(int first) {
  for (var i = 0; i < 8; i++) {
    if (first & (0x80 >> i) != 0) return i + 1;
  }
  return 8;
}

bool _lossy(String codec) => const {'MP3', 'AAC', 'Vorbis', 'Opus'}.contains(codec);

// ---------------------------------------------------------------- WavPack / APE (APEv2 tags)

const _wvRates = [6000, 8000, 9600, 11025, 12000, 16000, 22050, 24000, 32000, 44100, 48000, 64000, 88200, 96000, 192000];

void _wavpack(_R r, Tags t) {
  t.codec = 'WavPack';
  final h = r.at(0, 32);
  final total = _le(h, 12, 4), flags = _le(h, 24, 4);
  t.bitDepth = ((flags & 3) + 1) * 8 - ((flags >> 13) & 31);
  t.channels = flags & 4 != 0 ? 1 : 2;
  final ri = (flags >> 23) & 15;
  t.sampleRate = ri < _wvRates.length ? _wvRates[ri] : 0;
  if (t.sampleRate > 0 && total != 0xFFFFFFFF) t.durationMs = total * 1000 ~/ t.sampleRate;
  if (t.durationMs > 0) t.bitrate = (r.length * 8 / t.durationMs).round();
  _apeTag(r, t);
}

/// Monkey's Audio: the format and length from the header (new descriptor layout from 3.98, old before).
void _ape(_R r, Tags t) {
  t.codec = 'APE';
  final h = r.at(0, 32);
  final ver = _le(h, 4, 2);
  int perFrame, finalBlocks, frames;
  if (ver >= 3980) {
    final x = r.at(_le(h, 8, 4), 24);
    perFrame = _le(x, 4, 4);
    finalBlocks = _le(x, 8, 4);
    frames = _le(x, 12, 4);
    t.bitDepth = _le(x, 16, 2);
    t.channels = _le(x, 18, 2);
    t.sampleRate = _le(x, 20, 4);
  } else {
    final level = _le(h, 6, 2), flags = _le(h, 8, 2);
    t.channels = _le(h, 10, 2);
    t.sampleRate = _le(h, 12, 4);
    frames = _le(h, 24, 4);
    finalBlocks = _le(h, 28, 4);
    t.bitDepth = flags & 1 != 0 ? 8 : (flags & 8 != 0 ? 24 : 16);
    perFrame = ver >= 3950 ? 73728 * 4 : (ver >= 3900 || (ver >= 3800 && level == 4000) ? 73728 : 9216);
  }
  if (frames > 0 && t.sampleRate > 0) t.durationMs = ((frames - 1) * perFrame + finalBlocks) * 1000 ~/ t.sampleRate;
  if (t.durationMs > 0) t.bitrate = (r.length * 8 / t.durationMs).round();
  _apeTag(r, t);
}

void _apeTag(_R r, Tags t) {
  if (r.length < 32) return;
  var end = r.length;
  if (end > 128 && _starts(r.at(end - 128, 3), 0, 'TAG')) end -= 128; // trailing ID3v1
  final f = r.at(end - 32, 32);
  if (!_starts(f, 0, 'APETAGEX')) return;
  final size = _le(f, 12, 4), count = _le(f, 16, 4);
  final b = r.at(end - size, size - 32);
  var o = 0;
  for (var i = 0; i < count && o + 8 < b.length; i++) {
    final len = _le(b, o, 4), flags = _le(b, o + 4, 4);
    var k = o + 8;
    while (k < b.length && b[k] != 0) {
      k++;
    }
    if (k + 1 + len > b.length) break;
    final key = latin1.decode(b.sublist(o + 8, k)).toUpperCase();
    // Text items only (binary items hold cover art); NUL separates multiple values.
    if (flags & 6 == 0) _set(t, key, utf8.decode(b.sublist(k + 1, k + 1 + len), allowMalformed: true));
    o = k + 1 + len;
  }
}

// ---------------------------------------------------------------- DSD (DSF, DFF)

void _dsf(_R r, Tags t, bool picture) {
  t.codec = 'DSD';
  final h = r.at(0, 28 + 52);
  if (_starts(h, 28, 'fmt ')) {
    t.channels = _le(h, 28 + 24, 4);
    t.sampleRate = _le(h, 28 + 28, 4);
    t.bitDepth = 1;
    final samples = _le(h, 28 + 36, 8);
    if (t.sampleRate > 0) t.durationMs = samples * 1000 ~/ t.sampleRate;
    t.bitrate = t.sampleRate * t.channels ~/ 1000;
  }
  final meta = _le(h, 20, 8); // ID3v2 tag at the metadata pointer
  if (meta > 0) _id3v2(r, meta, t, picture);
}

void _dff(_R r, Tags t, bool picture) {
  t.codec = 'DSD';
  t.bitDepth = 1;
  var dataBytes = 0;
  void walk(int pos, int end) {
    while (pos + 12 <= end) {
      final h = r.at(pos, 12);
      if (h.length < 12) return;
      final id = latin1.decode(h.sublist(0, 4)), size = _be(h, 4, 8), body = pos + 12;
      switch (id) {
        case 'PROP':
          walk(body + 4, body + size); // 'SND ' then FS, CHNL, CMPR...
        case 'FS  ':
          t.sampleRate = _be(r.at(body, 4), 0, 4);
        case 'CHNL':
          t.channels = _be(r.at(body, 2), 0, 2);
        case 'DSD ':
          dataBytes = size;
        case 'ID3 ':
          _id3v2(r, body, t, picture);
      }
      if (size < 0) return;
      pos = body + size + (size & 1);
    }
  }

  walk(16, r.length);
  if (t.sampleRate > 0 && t.channels > 0) {
    t.durationMs = dataBytes * 8 * 1000 ~/ (t.channels * t.sampleRate);
    t.bitrate = t.sampleRate * t.channels ~/ 1000;
  }
}

// ---------------------------------------------------------------- FLAC without a sample count

/// Streamed FLAC files may have total samples = 0 in STREAMINFO. Estimate the
/// length from the last frame header (fixed block size): accurate to one frame.
int _flacTailDuration(_R r, int blockSize, int rate) {
  final start = r.length > 131072 ? r.length - 131072 : 0;
  final b = r.at(start, r.length - start);
  for (var i = b.length - 16; i >= 0; i--) {
    if (b[i] != 0xFF || b[i + 1] != 0xF8) continue;
    final n = _flacFrameNumber(b, i);
    if (n != null) return (n + 1) * blockSize * 1000 ~/ rate;
  }
  return 0;
}

int? _flacFrameNumber(Uint8List b, int i) {
  final bs = b[i + 2] >> 4, sr = b[i + 2] & 0xF;
  if (bs == 0 || sr == 0xF) return null;
  var q = i + 4;
  final lead = b[q++];
  var n = 0, extra = 0;
  if (lead < 0x80) {
    n = lead;
  } else if (lead >= 0xC0 && lead < 0xE0) {
    n = lead & 0x1F;
    extra = 1;
  } else if (lead >= 0xE0 && lead < 0xF0) {
    n = lead & 0x0F;
    extra = 2;
  } else if (lead >= 0xF0 && lead < 0xF8) {
    n = lead & 0x07;
    extra = 3;
  } else {
    return null;
  }
  for (var k = 0; k < extra; k++) {
    if (b[q] & 0xC0 != 0x80) return null;
    n = (n << 6) | (b[q++] & 0x3F);
  }
  if (bs == 6) q += 1;
  if (bs == 7) q += 2;
  if (sr == 12) q += 1;
  if (sr == 13 || sr == 14) q += 2;
  var c = 0;
  for (var k = i; k < q; k++) {
    c ^= b[k];
    for (var j = 0; j < 8; j++) {
      c = (c & 0x80) != 0 ? ((c << 1) ^ 0x07) & 0xFF : (c << 1) & 0xFF;
    }
  }
  return c == b[q] ? n : null;
}
