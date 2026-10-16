import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

class Lyrics {
  Lyrics(this.lines, this.synced);
  final List<(Duration, String)> lines; // time is zero for unsynced lines
  final bool synced;

  /// Index of the line being sung at [pos] (-1 before the first).
  int lineAt(Duration pos) {
    var i = -1;
    for (var k = 0; k < lines.length && lines[k].$1 <= pos; k++) {
      i = k;
    }
    return i;
  }
}

// Bounded digit counts: a garbage 20-digit stamp is not a stamp (and cannot overflow int.parse).
final _stamp = RegExp(r'\[(\d{1,4}):(\d{1,2})(?:[.:](\d{1,3}))?\]');
final _offset = RegExp(r'^\[offset:\s*([+-]?\d{1,7})\]', caseSensitive: false);

/// LRC text (with [mm:ss.xx] stamps) becomes synced lyrics; anything else is
/// shown as plain lines.
Lyrics parseLyrics(String text) {
  final lines = <(Duration, String)>[];
  var offset = 0;
  for (final raw in const LineSplitter().convert(text)) {
    final o = _offset.firstMatch(raw.trim());
    if (o != null) offset = int.tryParse(o.group(1)!) ?? 0;
    final stamps = _stamp.allMatches(raw).toList();
    if (stamps.isEmpty) continue;
    final words = raw.substring(stamps.last.end).trim();
    for (final m in stamps) {
      final frac = m.group(3) ?? '0';
      final (mm, ss) = (int.tryParse(m.group(1)!), int.tryParse(m.group(2)!)); // absurd stamps are skipped, not fatal
      if (mm == null || ss == null) continue;
      final ms = mm * 60000 + ss * 1000 + int.parse(frac.padRight(3, '0').substring(0, 3));
      lines.add((Duration(milliseconds: (ms - offset).clamp(0, 1 << 40)), words));
    }
  }
  if (lines.isNotEmpty) {
    lines.sort((a, b) => a.$1.compareTo(b.$1));
    return Lyrics(lines, true);
  }
  return Lyrics([for (final l in const LineSplitter().convert(text)) (Duration.zero, l.trim())], false);
}

/// A `.lrc` file next to the track wins; otherwise the embedded LYRICS tag.
Lyrics? loadLyrics(String trackPath, String? embedded) {
  final lrc = File('${p.withoutExtension(trackPath)}.lrc');
  if (lrc.existsSync()) {
    return parseLyrics(readText(lrc.path));
  }
  if (embedded != null && embedded.trim().isNotEmpty) return parseLyrics(embedded);
  return null;
}

/// A text file (.lrc, .m3u) decoded by [decodeText], without a byte order mark.
String readText(String path) => decodeText(File(path).readAsBytesSync()).replaceFirst('﻿', '');

/// Text file bytes: UTF-16 with a byte order mark, else UTF-8, else Windows-1252 (old .cue and .lrc files).
String decodeText(List<int> b) {
  if (b.length >= 2 && ((b[0] == 0xFF && b[1] == 0xFE) || (b[0] == 0xFE && b[1] == 0xFF))) {
    final le = b[0] == 0xFF;
    return String.fromCharCodes([for (var i = 2; i + 1 < b.length; i += 2) le ? b[i] | (b[i + 1] << 8) : (b[i] << 8) | b[i + 1]]);
  }
  try {
    return utf8.decode(b);
  } on FormatException {
    return String.fromCharCodes([for (final x in b) x >= 0x80 && x < 0xA0 ? _cp1252[x - 0x80] : x]);
  }
}

/// Windows-1252's 0x80-0x9F (€, curly quotes, dashes...); the rest is Latin-1.
const _cp1252 = [
  0x20AC, 0x81, 0x201A, 0x0192, 0x201E, 0x2026, 0x2020, 0x2021, 0x02C6, 0x2030, 0x0160, 0x2039, 0x0152, 0x8D, 0x017D, 0x8F, //
  0x90, 0x2018, 0x2019, 0x201C, 0x201D, 0x2022, 0x2013, 0x2014, 0x02DC, 0x2122, 0x0161, 0x203A, 0x0153, 0x9D, 0x017E, 0x0178,
];
