// A small pure-Dart tag reader: FLAC, Ogg (Vorbis/Opus/FLAC), MP3 (ID3v2/ID3v1),
// MP4/M4A (AAC/ALAC), WAV, AIFF and WebM/Matroska. Reads only the bytes it needs.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

class Tags {
  String? title, artist, albumArtist, album, genre, lyrics;
  int? track, disc, year;
  bool compilation = false;
  int durationMs = 0, sampleRate = 0, bitDepth = 0, channels = 0, bitrate = 0;
  String codec = '';
  Uint8List? picture;
}

const audioExtensions = {
  '.flac', '.mp3', '.m4a', '.mp4', '.aac', '.alac', '.wav', '.aif', '.aiff', '.aifc',
  '.ogg', '.oga', '.opus', '.webm', '.mka', '.ape', '.wv', '.dsf', '.dff', '.wma',
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
    final m4 = latin1.decode(magic.sublist(0, 4), allowInvalid: true);
    if (m4 == 'fLaC') {
      _flac(r, t, picture);
    } else if (m4 == 'OggS') {
      _ogg(r, t, picture);
    } else if (m4 == 'RIFF') {
      _wav(r, t, picture);
    } else if (m4 == 'FORM') {
      _aiff(r, t, picture);
    } else if (latin1.decode(magic.sublist(4, 8), allowInvalid: true) == 'ftyp') {
      _mp4(r, t, picture);
    } else if (magic[0] == 0x1A && magic[1] == 0x45 && magic[2] == 0xDF && magic[3] == 0xA3) {
      _mkv(r, t, picture);
    } else if (m4 == 'wvpk') {
      _wavpack(r, t);
    } else if (m4 == 'MAC ') {
      t.codec = 'APE';
      _apeTag(r, t);
    } else if (m4.startsWith('ID3') || ext == '.mp3' || (magic[0] == 0xFF && magic[1] & 0xE0 == 0xE0)) {
      _mp3(r, t, picture);
    } else {
      t.codec = ext.replaceFirst('.', '').toUpperCase();
    }
  } catch (_) {
    // Keep whatever was read before the error.
  } finally {
    f?.closeSync();
  }
  t.title = _clean(t.title) ?? p.basenameWithoutExtension(path);
  t.artist = _clean(t.artist);
  t.albumArtist = _clean(t.albumArtist);
  t.album = _clean(t.album);
  t.genre = _clean(t.genre);
  return t;
}

String? _clean(String? s) {
  final v = s?.replaceAll('\u0000', '').trim();
  return (v == null || v.isEmpty) ? null : v;
}

class _R {
  _R(this.f) : length = f.lengthSync();
  final RandomAccessFile f;
  final int length;
  Uint8List at(int pos, int n) {
    f.setPositionSync(pos);
    return f.readSync(n);
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

int? _num(String? s) => s == null ? null : int.tryParse(RegExp(r'\d+').firstMatch(s)?.group(0) ?? '');

// ---------------------------------------------------------------- Vorbis comments

void _vorbisComments(Uint8List b, int o, Tags t, bool picture) {
  final vendor = _le(b, o, 4);
  o += 4 + vendor;
  final n = _le(b, o, 4);
  o += 4;
  for (var i = 0; i < n && o + 4 <= b.length; i++) {
    final len = _le(b, o, 4);
    o += 4;
    final s = utf8.decode(b.sublist(o, o + len), allowMalformed: true);
    o += len;
    final eq = s.indexOf('=');
    if (eq < 0) continue;
    final k = s.substring(0, eq).toUpperCase(), v = s.substring(eq + 1);
    switch (k) {
      case 'TITLE': t.title ??= v;
      case 'ARTIST': t.artist ??= v;
      case 'ALBUMARTIST' || 'ALBUM ARTIST' || 'ALBUM_ARTIST': t.albumArtist ??= v;
      case 'ALBUM': t.album ??= v;
      case 'GENRE': t.genre ??= v;
      case 'TRACKNUMBER': t.track ??= _num(v);
      case 'DISCNUMBER': t.disc ??= _num(v);
      case 'DATE' || 'YEAR' || 'ORIGINALDATE': t.year ??= _num(v);
      case 'COMPILATION': t.compilation = v.trim() == '1';
      case 'LYRICS' || 'UNSYNCEDLYRICS': t.lyrics ??= v;
      case 'METADATA_BLOCK_PICTURE':
        if (picture && t.picture == null) t.picture = _flacPicture(base64.decode(v.trim()));
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

void _flac(_R r, Tags t, bool picture) {
  t.codec = 'FLAC';
  var pos = 4, blockSize = 0;
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
  t.sampleRate = x >> 44;
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
  if (t.durationMs > 0) t.bitrate = (r.length * 8 / t.durationMs).round();
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
  'Blues', 'Classic Rock', 'Country', 'Dance', 'Disco', 'Funk', 'Grunge', 'Hip-Hop', 'Jazz', 'Metal', 'New Age',
  'Oldies', 'Other', 'Pop', 'R&B', 'Rap', 'Reggae', 'Rock', 'Techno', 'Industrial', 'Alternative', 'Ska',
  'Death Metal', 'Pranks', 'Soundtrack', 'Euro-Techno', 'Ambient', 'Trip-Hop', 'Vocal', 'Jazz+Funk', 'Fusion',
  'Trance', 'Classical', 'Instrumental', 'Acid', 'House', 'Game', 'Sound Clip', 'Gospel', 'Noise', 'Alt. Rock',
  'Bass', 'Soul', 'Punk', 'Space', 'Meditative', 'Instrumental Pop', 'Instrumental Rock', 'Ethnic', 'Gothic',
  'Darkwave', 'Techno-Industrial', 'Electronic', 'Pop-Folk', 'Eurodance', 'Dream', 'Southern Rock', 'Comedy',
  'Cult', 'Gangsta', 'Top 40', 'Christian Rap', 'Pop/Funk', 'Jungle', 'Native American', 'Cabaret', 'New Wave',
  'Psychedelic', 'Rave', 'Showtunes', 'Trailer', 'Lo-Fi', 'Tribal', 'Acid Punk', 'Acid Jazz', 'Polka', 'Retro',
  'Musical', 'Rock & Roll', 'Hard Rock',
];

String _genre(String g) {
  final m = RegExp(r'^\(?(\d+)\)?(.*)$').firstMatch(g.trim());
  if (m == null) return g;
  if (m.group(2)!.isNotEmpty) return m.group(2)!;
  final i = int.parse(m.group(1)!);
  return i < _id3Genres.length ? _id3Genres[i] : g;
}

String _text(Uint8List b, int enc) {
  String s;
  if (enc == 1 || enc == 2) {
    var o = 0;
    var bigEndian = enc == 2;
    if (b.length >= 2 && ((b[0] == 0xFF && b[1] == 0xFE) || (b[0] == 0xFE && b[1] == 0xFF))) {
      bigEndian = b[0] == 0xFE;
      o = 2;
    }
    final units = <int>[];
    for (; o + 1 < b.length; o += 2) {
      units.add(bigEndian ? (b[o] << 8) | b[o + 1] : b[o] | (b[o + 1] << 8));
    }
    s = String.fromCharCodes(units);
  } else if (enc == 3) {
    s = utf8.decode(b, allowMalformed: true);
  } else {
    s = latin1.decode(b);
  }
  // Multiple values are separated by NUL: keep the first.
  final z = s.indexOf('\u0000');
  return z >= 0 ? s.substring(0, z) : s;
}

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
    final len = ver == 2 ? _be(b, o + 3, 3) : ver == 4 ? _syncsafe(b, o + 4) : _be(b, o + 4, 4);
    final fmt = ver == 2 ? 0 : b[o + 9];
    o += hdr;
    if (len <= 0 || o + len > b.length) break;
    var d = b.sublist(o, o + len);
    o += len;
    if (ver == 4) {
      if (fmt & 0x01 != 0) d = d.sublist(4);
      if (fmt & 0x02 != 0) d = _unsync(d);
    }
    if (d.isEmpty) continue;
    String txt() => _text(d.sublist(1), d[0]);
    switch (id) {
      case 'TIT2' || 'TT2': t.title ??= txt();
      case 'TPE1' || 'TP1': t.artist ??= txt();
      case 'TPE2' || 'TP2': t.albumArtist ??= txt();
      case 'TALB' || 'TAL': t.album ??= txt();
      case 'TCON' || 'TCO': t.genre ??= _genre(txt());
      case 'TRCK' || 'TRK': t.track ??= _num(txt());
      case 'TPOS' || 'TPA': t.disc ??= _num(txt());
      case 'TDRC' || 'TYER' || 'TYE' || 'TDOR' || 'TORY': t.year ??= _num(txt());
      case 'TCMP' || 'TCP': t.compilation = txt().trim() == '1';
      case 'TLEN' || 'TLE': t.durationMs = t.durationMs > 0 ? t.durationMs : (_num(txt()) ?? 0);
      case 'TXXX':
        final enc = d[0], z = _skipZ(d, 1, enc);
        final desc = _text(d.sublist(1, z), enc).toUpperCase();
        final v = _text(d.sublist(z), enc);
        if (desc == 'ALBUMARTIST' || desc == 'ALBUM ARTIST') t.albumArtist ??= v;
        if (desc == 'COMPILATION') t.compilation = v.trim() == '1';
      case 'USLT' || 'ULT':
        final enc = d[0], z = _skipZ(d, 4, enc);
        t.lyrics ??= _text(d.sublist(z), enc).replaceAll('\r\n', '\n');
      case 'APIC' || 'PIC':
        if (!picture) break;
        final enc = d[0];
        var q = ver == 2 ? 4 : _skipZ(d, 1, 0); // v2.2 has a 3-byte format
        final type = d[q];
        q = _skipZ(d, q + 1, enc);
        if (t.picture == null || type == 3) t.picture = d.sublist(q);
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

void _mp3(_R r, Tags t, bool picture) {
  t.codec = 'MP3';
  var pos = 0, n = 0;
  while ((n = _id3v2(r, pos, t, picture)) > 0) {
    pos += n;
  }
  if (t.title == null && r.length > 128) {
    final v1 = r.at(r.length - 128, 128);
    if (_starts(v1, 0, 'TAG')) {
      String s(int o, int l) => latin1.decode(v1.sublist(o, o + l)).split('\u0000').first.trim();
      t.title = s(3, 30);
      t.artist ??= s(33, 30);
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

// ---------------------------------------------------------------- MP4 / M4A

void _mp4(_R r, Tags t, bool picture) {
  var pos = 0;
  while (pos + 8 <= r.length) {
    final h = r.at(pos, 16);
    var size = _be(h, 0, 4);
    final type = latin1.decode(h.sublist(4, 8));
    if (size == 1) size = _be(h, 8, 8);
    if (size == 0) size = r.length - pos;
    if (size < 8) break;
    if (type == 'moov') _atoms(r.at(pos + 8, size - 8), t, picture);
    pos += size;
  }
  if (t.codec.isEmpty) t.codec = 'AAC';
  if (t.durationMs > 0) t.bitrate = (r.length * 8 / t.durationMs).round();
}

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
        _atoms(body.sublist(4), t, picture, type);
      case 'mdhd':
        final v1 = body[0] == 1;
        final scale = _be(body, v1 ? 20 : 12, 4), dur = _be(body, v1 ? 24 : 16, v1 ? 8 : 4);
        if (scale > 0 && t.durationMs == 0) t.durationMs = dur * 1000 ~/ scale;
      case 'stsd':
        final entry = latin1.decode(body.sublist(12, 16));
        t.channels = _be(body, 8 + 8 + 16, 2);
        t.bitDepth = _be(body, 8 + 8 + 18, 2);
        t.sampleRate = _be(body, 8 + 8 + 24, 2);
        if (entry == 'alac') {
          t.codec = 'ALAC';
          // ALACSpecificConfig follows the 36-byte sample entry: size, 'alac', ver/flags, ...
          final c = 8 + 36 + 12;
          if (c + 24 <= body.length) {
            t.bitDepth = body[c + 5];
            t.channels = body[c + 9];
            t.sampleRate = _be(body, c + 20, 4);
          }
        } else if (entry == 'mp4a') {
          t.codec = 'AAC';
          t.bitDepth = 0;
        } else {
          t.codec = entry.toUpperCase().trim();
        }
      default:
        if (parent == 'ilst') _ilstItem(type, body, t, picture);
    }
    o += size;
  }
}

void _ilstItem(String type, Uint8List b, Tags t, bool picture) {
  if (b.length < 16 || latin1.decode(b.sublist(4, 8)) != 'data') return;
  final d = b.sublist(16, _be(b, 0, 4).clamp(16, b.length));
  String s() => utf8.decode(d, allowMalformed: true);
  switch (type) {
    case '©nam': t.title ??= s();
    case '©ART': t.artist ??= s();
    case 'aART': t.albumArtist ??= s();
    case '©alb': t.album ??= s();
    case '©gen': t.genre ??= s();
    case 'gnre': if (d.length >= 2) t.genre ??= _genre('${_be(d, 0, 2) - 1}');
    case '©day': t.year ??= _num(s());
    case '©lyr': t.lyrics ??= s();
    case 'trkn': if (d.length >= 4) t.track ??= _be(d, 2, 2);
    case 'disk': if (d.length >= 4) t.disc ??= _be(d, 2, 2);
    case 'cpil': t.compilation = d.isNotEmpty && d[0] == 1;
    case 'covr': if (picture) t.picture ??= d;
  }
}

// ---------------------------------------------------------------- WAV / AIFF

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
      dataSize = size;
    } else if (id == 'LIST') {
      final b = r.at(pos + 8, size);
      if (_starts(b, 0, 'INFO')) {
        var o = 4;
        while (o + 8 <= b.length) {
          final k = latin1.decode(b.sublist(o, o + 4)), n = _le(b, o + 4, 4);
          if (o + 8 + n > b.length) break;
          final v = utf8.decode(b.sublist(o + 8, o + 8 + n), allowMalformed: true);
          switch (k) {
            case 'INAM': t.title ??= v;
            case 'IART': t.artist ??= v;
            case 'IPRD': t.album ??= v;
            case 'IGNR': t.genre ??= v;
            case 'ICRD': t.year ??= _num(v);
            case 'ITRK' || 'IPRT': t.track ??= _num(v);
          }
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
  String? tagName;
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
      } else if (id != 0x1F43B675 && size < 1 << 20) { // skip Clusters (audio)
        final d = r.at(data, size);
        switch (id) {
          case 0x2AD7B1: scale = _be(d, 0, size);
          case 0x4489: durationTicks = size == 4 ? ByteData.sublistView(d).getFloat32(0) : ByteData.sublistView(d).getFloat64(0);
          case 0x86: t.codec = latin1.decode(d).replaceFirst('A_', '').split('/').first;
          case 0xB5: t.sampleRate = (size == 4 ? ByteData.sublistView(d).getFloat32(0) : ByteData.sublistView(d).getFloat64(0)).round();
          case 0x9F: t.channels = _be(d, 0, size);
          case 0x6264: t.bitDepth = _be(d, 0, size);
          case 0x45A3: tagName = utf8.decode(d, allowMalformed: true).toUpperCase();
          case 0x4487:
            final v = utf8.decode(d, allowMalformed: true);
            switch (tagName) {
              case 'TITLE': t.title ??= v;
              case 'ARTIST': t.artist ??= v;
              case 'ALBUM_ARTIST' || 'ALBUMARTIST': t.albumArtist ??= v;
              case 'ALBUM': t.album ??= v;
              case 'GENRE': t.genre ??= v;
              case 'DATE' || 'DATE_RELEASED' || 'DATE_RECORDED': t.year ??= _num(v);
              case 'PART_NUMBER' || 'TRACK': t.track ??= _num(v);
            }
        }
      }
      pos = data + size;
    }
  }

  walk(0, r.length);
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
    final len = _le(b, o, 4);
    var k = o + 8;
    while (b[k] != 0) {
      k++;
    }
    final key = latin1.decode(b.sublist(o + 8, k)).toUpperCase();
    final v = utf8.decode(b.sublist(k + 1, k + 1 + len), allowMalformed: true);
    o = k + 1 + len;
    switch (key) {
      case 'TITLE': t.title ??= v;
      case 'ARTIST': t.artist ??= v;
      case 'ALBUM ARTIST' || 'ALBUMARTIST' || 'ALBUM_ARTIST': t.albumArtist ??= v;
      case 'ALBUM': t.album ??= v;
      case 'GENRE': t.genre ??= v;
      case 'TRACK': t.track ??= _num(v);
      case 'DISC': t.disc ??= _num(v);
      case 'YEAR' || 'DATE': t.year ??= _num(v);
      case 'COMPILATION': t.compilation = v.trim() == '1';
      case 'LYRICS': t.lyrics ??= v;
    }
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
