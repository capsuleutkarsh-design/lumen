// Writes the tiny crafted audio files the tag tests read (headers and tags only, a few KB each).
// Run from the project root: dart run test/fixtures/make_fixtures.dart
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

const dir = 'test/fixtures';

List<int> be(int v, int n) => [for (var i = n - 1; i >= 0; i--) (v >> (8 * i)) & 0xFF];
List<int> le(int v, int n) => [for (var i = 0; i < n; i++) (v >> (8 * i)) & 0xFF];
List<int> ss(int v) => [(v >> 21) & 0x7F, (v >> 14) & 0x7F, (v >> 7) & 0x7F, v & 0x7F];
List<int> a(String s) => latin1.encode(s); // MP4 item names use © (0xA9)
List<int> u(String s) => utf8.encode(s);

/// ID3v2 frame; [plain] writes a v2.4 size the old-iTunes way (not syncsafe).
List<int> frame(String id, List<int> body, {int ver = 3, bool plain = false}) => [
  ...a(id),
  ...(ver == 4 && !plain ? ss(body.length) : be(body.length, 4)),
  0,
  0,
  ...body,
];
List<int> id3(int ver, List<List<int>> frames, {int? size}) {
  final body = [for (final f in frames) ...f];
  return [...a('ID3'), ver, 0, 0, ...ss(size ?? body.length), ...body];
}

List<int> txt(String s) => [3, ...u(s)];

/// One silent MPEG-1 Layer III frame, 128 kbps, 44.1 kHz, stereo (417 bytes).
List<int> mp3Frame() => [0xFF, 0xFB, 0x90, 0x00, ...List.filled(413, 0)];

/// fLaC + STREAMINFO (+ more metadata blocks, the last one flagged).
List<int> flac({int rate = 44100, int seconds = 1, List<(int, List<int>)> blocks = const []}) {
  final info = ByteData(34)
    ..setUint16(0, 4096)
    ..setUint16(2, 4096)
    ..setUint64(10, (rate << 44) | (1 << 41) | (15 << 36) | rate * seconds);
  final all = [(0, info.buffer.asUint8List().toList()), ...blocks];
  return [
    ...a('fLaC'),
    for (var i = 0; i < all.length; i++) ...[(i == all.length - 1 ? 0x80 : 0) | all[i].$1, ...be(all[i].$2.length, 3), ...all[i].$2],
  ];
}

List<int> vorbis(List<String> fields) => [
  ...le(0, 4),
  ...le(fields.length, 4),
  for (final f in fields) ...[...le(u(f).length, 4), ...u(f)],
];

/// MP4 box.
List<int> box(String type, List<int> body) => [...be(8 + body.length, 4), ...a(type), ...body];
List<int> fullBox(String type, List<int> body) => box(type, [0, 0, 0, 0, ...body]);
List<int> ilstItem(String type, List<int> value, {int kind = 1}) => box(type, box('data', [...be(kind, 4), 0, 0, 0, 0, ...value]));
List<int> trak(String entry, {int rate = 44100}) => box('trak', [
  ...box('mdia', [
    ...fullBox('mdhd', [...be(0, 4), ...be(0, 4), ...be(rate, 4), ...be(rate, 4), 0, 0, 0, 0]),
    ...box('minf', [
      ...box('stbl', [
        // stsd: version/flags, count, then one sample entry: size, type, 6 reserved, data ref, 8 reserved,
        // channels, sample size, 4 bytes, rate (16.16).
        ...fullBox('stsd', [
          ...be(1, 4),
          ...box(entry, [...List.filled(6, 0), 0, 1, ...List.filled(8, 0), 0, 2, 0, 16, 0, 0, 0, 0, ...be(rate, 2), 0, 0]),
        ]),
      ]),
    ]),
  ]),
]);

/// EBML element with a 1-byte (or 8-byte) size.
List<int> ebml(int id, List<int> body) {
  final idBytes = id > 0xFFFFFF ? be(id, 4) : (id > 0xFFFF ? be(id, 3) : (id > 0xFF ? be(id, 2) : [id]));
  final size = body.length < 127 ? [0x80 | body.length] : [0x01, ...be(body.length, 7)];
  return [...idBytes, ...size, ...body];
}

List<int> f64(double v) => (ByteData(8)..setFloat64(0, v)).buffer.asUint8List();

void w(String name, List<int> bytes) => File('$dir/$name').writeAsBytesSync(bytes);

void main() {
  Directory(dir).createSync(recursive: true);

  // FLAC with an ID3v2 tag in front (W3).
  w('id3_then_flac.flac', [
    ...id3(3, [frame('TIT2', txt('From ID3'))]),
    ...flac(
      blocks: [
        (4, vorbis(['ARTIST=Ana'])),
      ],
    ),
  ]);

  // Vorbis comments: broken picture first (W5), d/m/y date (W16), several artists (W19),
  // ARTISTS, genres, classical, sort names, MusicBrainz id, ReplayGain and R128.
  w(
    'vorbis.flac',
    flac(
      blocks: [
        (
          4,
          vorbis([
            'METADATA_BLOCK_PICTURE=not*base64',
            'TITLE=Real title',
            'ARTIST=Ana',
            'ARTIST=Bo',
            'ARTISTS=Ana',
            'ARTISTS=Bo',
            'DATE=05/01/2017',
            'GENRE=Rock;Pop',
            'COMPOSER=Bach',
            'WORK=Mass in B minor',
            'MOVEMENTNAME=Kyrie',
            'MOVEMENT=2',
            'ALBUMARTISTSORT=Ana, The',
            'ARTISTSORT=Ana',
            'ALBUMSORT=Mass',
            'MUSICBRAINZ_ALBUMID=0F1E-ab',
            'REPLAYGAIN_TRACK_GAIN=-6.50 dB',
            'REPLAYGAIN_TRACK_PEAK=0.988',
            'R128_ALBUM_GAIN=-512',
          ]),
        ),
      ],
    ),
  );

  // FLAC at 705.6 kHz: the 20-bit rate has its top bit set (>>> not >>).
  w('hirate.flac', flac(rate: 705600));

  // ID3v2.4 written by old iTunes (plain frame sizes, W6), an empty frame (W7), NUL multi-values,
  // numeric genre, classical frames, sort frames, TXXX MusicBrainz id and ReplayGain.
  w('itunes.mp3', [
    ...id3(4, [
      frame('COMM', [3, ...a('eng'), 0, ...List.filled(996, 0x61)], ver: 4, plain: true),
      frame('TXXX', [], ver: 4, plain: true),
      frame('TIT2', txt('Real title'), ver: 4, plain: true),
      frame('TPE1', [3, ...u('Ana'), 0, ...u('Bo')], ver: 4, plain: true),
      frame('TCON', txt('(17)'), ver: 4, plain: true),
      frame('TCOM', txt('Bach'), ver: 4, plain: true),
      frame('TIT1', txt('Mass'), ver: 4, plain: true),
      frame('MVNM', txt('Gloria'), ver: 4, plain: true),
      frame('MVIN', txt('3/5'), ver: 4, plain: true),
      frame('TSO2', txt('Ana, The'), ver: 4, plain: true),
      frame('TXXX', [3, ...u('MusicBrainz Album Id'), 0, ...u('abc-123')], ver: 4, plain: true),
      frame('TXXX', [3, ...u('REPLAYGAIN_ALBUM_GAIN'), 0, ...u('+1.25 dB')], ver: 4, plain: true),
    ]),
    ...mp3Frame(),
  ]);

  // An ID3 header claiming 256 MB on a tiny file (C3).
  w('id3_huge.mp3', [
    ...id3(3, [frame('TIT2', txt('Real title'))], size: 0x0FFFFFFF),
    ...mp3Frame(),
  ]);

  // WAV: LIST/INFO in Windows-1252 (W8) whose size claims ~4 GB (polish: keep the duration).
  final fmt = [...le(1, 2), ...le(2, 2), ...le(44100, 4), ...le(44100 * 4, 4), ...le(4, 2), ...le(16, 2)];
  final name = [...latin1.encode('Beyoncé'), 0];
  w('cp1252.wav', [
    ...a('RIFF'), ...le(4 + 24 + 8 + 1764 + 8 + 4 + 8 + name.length, 4), ...a('WAVE'), //
    ...a('fmt '), ...le(16, 4), ...fmt,
    ...a('data'), ...le(1764, 4), ...List.filled(1764, 0), // 10 ms
    ...a('LIST'), ...le(0xFFFFFF00, 4), ...a('INFO'), ...a('IART'), ...le(name.length, 4), ...name,
  ]);

  // MP4: a chapter (text) track before the audio track (W4), a 64-bit moov size (W17), an mdat
  // for the bitrate, and iTunes items incl. classical, sort names and a freeform ReplayGain.
  final ilst = box('ilst', [
    ...ilstItem('©nam', u('Real title')),
    ...ilstItem('©ART', u('Ana')),
    ...ilstItem('©wrt', u('Bach')),
    ...ilstItem('©wrk', u('Mass')),
    ...ilstItem('©mvn', u('Credo')),
    ...ilstItem('©mvi', [0, 4], kind: 21),
    ...ilstItem('soaa', u('Ana, The')),
    ...box('----', [
      ...fullBox('mean', u('com.apple.iTunes')),
      ...fullBox('name', u('REPLAYGAIN_TRACK_GAIN')),
      ...box('data', [0, 0, 0, 1, 0, 0, 0, 0, ...u('-3.00 dB')]),
    ]),
  ]);
  final moovBody = [
    ...fullBox('mvhd', List.filled(96, 0)),
    ...trak('text'),
    ...trak('mp4a'),
    ...box('udta', fullBox('meta', [...fullBox('hdlr', List.filled(21, 0)), ...ilst])),
  ];
  w('chapters64.m4a', [
    ...box('ftyp', [...a('M4A '), 0, 0, 0, 0, ...a('M4A mp42isom')]),
    ...be(1, 4), ...a('moov'), ...be(16 + moovBody.length, 8), ...moovBody, //
    ...box('mdat', List.filled(1000, 0)),
  ]);

  // Raw AAC (ADTS), 10 frames of 100 bytes, 44.1 kHz stereo (W14).
  final adts = [0xFF, 0xF1, 0x50, 0x80, (100 >> 3) & 0xFF, ((100 & 7) << 5) | 0x1F, 0xFC];
  w('adts.aac', [
    for (var i = 0; i < 10; i++) ...[...adts, ...List.filled(93, 0)],
  ]);

  // Matroska: segment title, a NaN duration (polish), FLAC track, DISC tag (W18).
  w('segment.mka', [
    ...ebml(0x1A45DFA3, ebml(0x4282, a('matroska'))),
    ...ebml(0x18538067, [
      ...ebml(0x1549A966, [...ebml(0x2AD7B1, be(1000000, 3)), ...ebml(0x4489, f64(double.nan)), ...ebml(0x7BA9, u('Segment title'))]),
      ...ebml(
        0x1654AE6B,
        ebml(0xAE, [
          ...ebml(0x86, a('A_FLAC')),
          ...ebml(0xE1, [
            ...ebml(0xB5, f64(48000)),
            ...ebml(0x9F, [2]),
          ]),
        ]),
      ),
      ...ebml(0x1254C367, ebml(0x7373, ebml(0x67C8, [...ebml(0x45A3, a('DISC')), ...ebml(0x4487, a('2'))]))),
    ]),
  ]);

  // DSF (DSD64 stereo, 1 s) with ID3v2 at the metadata pointer (W9).
  final dsfTag = id3(3, [frame('TIT2', txt('DSD title')), frame('TPE1', txt('Ana'))]);
  const dsfData = 12 + 64;
  w('dsd.dsf', [
    ...a('DSD '), ...le(28, 8), ...le(28 + 52 + dsfData + dsfTag.length, 8), ...le(28 + 52 + dsfData, 8), //
    ...a('fmt '), ...le(52, 8), ...le(1, 4), ...le(0, 4), ...le(2, 4), ...le(2, 4), ...le(2822400, 4), ...le(1, 4),
    ...le(2822400, 8), ...le(4096, 4), ...le(0, 4),
    ...a('data'), ...le(dsfData, 8), ...List.filled(64, 0x69),
    ...dsfTag,
  ]);

  // DFF (DSDIFF, DSD128 stereo, 2 ms) with an ID3 chunk.
  final dffTag = id3(3, [frame('TIT2', txt('DFF title'))]);
  final prop = [...a('SND '), ...a('FS  '), ...be(4, 8), ...be(5644800, 4), ...a('CHNL'), ...be(2, 8), ...be(2, 2)];
  final dff = [
    ...a('FVER'), ...be(4, 8), ...be(0x01050000, 4), //
    ...a('PROP'), ...be(prop.length, 8), ...prop,
    ...a('DSD '), ...be(2824, 8), ...List.filled(2824, 0x69), // 2 ms
    ...a('ID3 '), ...be(dffTag.length, 8), ...dffTag, if (dffTag.length.isOdd) 0,
  ];
  w('dsd.dff', [...a('FRM8'), ...be(4 + dff.length, 8), ...a('DSD '), ...dff]);

  // Monkey's Audio 3.99 header, 2 frames (1 s at 44.1 kHz), APEv2 tag with a NUL multi-value (W15).
  final apeHeader = [...le(2000, 2), 0, 0, ...le(73728, 4), ...le(44100, 4), ...le(1, 4), ...le(16, 2), ...le(2, 2), ...le(44100, 4)];
  final items = [
    for (final (k, v) in [
      ('Title', u('T')),
      ('Artist', [...u('Ana'), 0, ...u('Bo')]),
    ]) ...[...le(v.length, 4), ...le(0, 4), ...a(k), 0, ...v],
  ];
  w('multi.ape', [
    ...a('MAC '), ...le(3990, 2), 0, 0, ...le(52, 4), ...le(24, 4), ...List.filled(36, 0), // descriptor: 52 bytes
    ...apeHeader,
    ...items,
    ...a('APETAGEX'), ...le(2000, 4), ...le(items.length + 32, 4), ...le(2, 4), ...le(0, 4), ...List.filled(8, 0),
  ]);
}
