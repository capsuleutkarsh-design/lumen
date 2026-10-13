// Test-library helper: ffmpeg writes FLAC without a SEEKTABLE, so this adds one
// (a seek point every 10 s) inside the existing PADDING block, keeping audio offsets.
// Usage: dart run tool/add_seektable.dart file.flac [...]
import 'dart:io';
import 'dart:typed_data';

int crc8(Uint8List b, int start, int end) {
  var c = 0;
  for (var i = start; i < end; i++) {
    c ^= b[i];
    for (var k = 0; k < 8; k++) {
      c = (c & 0x80) != 0 ? ((c << 1) ^ 0x07) & 0xFF : (c << 1) & 0xFF;
    }
  }
  return c;
}

/// Returns the frame number if a valid fixed-blocksize frame header starts at [i].
int? frameAt(Uint8List b, int i) {
  if (i + 16 > b.length || b[i] != 0xFF || b[i + 1] != 0xF8) return null;
  final bs = b[i + 2] >> 4, sr = b[i + 2] & 0xF;
  if (bs == 0 || sr == 0xF) return null;
  var p = i + 4;
  // UTF-8 style coded frame number.
  final lead = b[p];
  var n = 0, extra = 0;
  if (lead < 0x80) {
    n = lead;
  } else if (lead >= 0xC0 && lead < 0xE0) {
    n = lead & 0x1F; extra = 1;
  } else if (lead >= 0xE0 && lead < 0xF0) {
    n = lead & 0x0F; extra = 2;
  } else if (lead >= 0xF0 && lead < 0xF8) {
    n = lead & 0x07; extra = 3;
  } else {
    return null;
  }
  p++;
  for (var k = 0; k < extra; k++) {
    if (b[p] & 0xC0 != 0x80) return null;
    n = (n << 6) | (b[p++] & 0x3F);
  }
  if (bs == 6) p += 1;
  if (bs == 7) p += 2;
  if (sr == 12) p += 1;
  if (sr == 13 || sr == 14) p += 2;
  return crc8(b, i, p) == b[p] ? n : null;
}

void main(List<String> files) {
  for (final f in files) {
    final b = File(f).readAsBytesSync();
    final d = ByteData.sublistView(b);
    final rate = (d.getUint32(18) >> 12);
    final block = d.getUint16(8);
    // Walk metadata blocks to find PADDING and the first frame.
    var i = 4, pad = -1;
    while (true) {
      final last = b[i] & 0x80 != 0, type = b[i] & 0x7F;
      final len = (b[i + 1] << 16) | (b[i + 2] << 8) | b[i + 3];
      if (type == 3) throw '$f already has a SEEKTABLE';
      if (type == 1) pad = i;
      i += 4 + len;
      if (last) break;
    }
    final audio = i;
    final points = <List<int>>[]; // [sample, offset]
    var nextSec = 0;
    for (var p = audio; p < b.length - 16; p++) {
      final n = frameAt(b, p);
      if (n == null) continue;
      final sample = n * block;
      if (sample >= nextSec * rate) {
        points.add([sample, p - audio]);
        nextSec += 10;
      }
    }
    final padLen = (b[pad + 1] << 16) | (b[pad + 2] << 8) | b[pad + 3];
    final stLen = points.length * 18;
    final wasLast = b[pad] & 0x80;
    final out = BytesBuilder()..add(b.sublist(0, pad));
    final st = ByteData(4 + stLen)..setUint32(0, (3 << 24) | stLen);
    for (var k = 0; k < points.length; k++) {
      st.setUint64(4 + k * 18, points[k][0]);
      st.setUint64(12 + k * 18, points[k][1]);
      st.setUint16(20 + k * 18, block);
    }
    out.add(st.buffer.asUint8List());
    final rest = padLen - stLen - 4;
    out.add((ByteData(4)..setUint32(0, ((wasLast | 1) << 24) | rest)).buffer.asUint8List());
    out.add(Uint8List(rest));
    out.add(b.sublist(audio));
    File(f).writeAsBytesSync(out.toBytes());
    stdout.writeln('$f: ${points.length} seek points');
  }
}
