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
    if (o != null) offset = int.parse(o.group(1)!);
    final stamps = _stamp.allMatches(raw).toList();
    if (stamps.isEmpty) continue;
    final words = raw.substring(stamps.last.end).trim();
    for (final m in stamps) {
      final frac = m.group(3) ?? '0';
      final ms = int.parse(m.group(1)!) * 60000 + int.parse(m.group(2)!) * 1000 + int.parse(frac.padRight(3, '0').substring(0, 3));
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
    return parseLyrics(decodeText(lrc.readAsBytesSync()).replaceFirst('\uFEFF', ''));
  }
  if (embedded != null && embedded.trim().isNotEmpty) return parseLyrics(embedded);
  return null;
}

/// Text file bytes: UTF-16 with a byte order mark, else UTF-8, else Latin-1.
String decodeText(List<int> b) {
  if (b.length >= 2 && ((b[0] == 0xFF && b[1] == 0xFE) || (b[0] == 0xFE && b[1] == 0xFF))) {
    final le = b[0] == 0xFF;
    return String.fromCharCodes([for (var i = 2; i + 1 < b.length; i += 2) le ? b[i] | (b[i + 1] << 8) : (b[i] << 8) | b[i + 1]]);
  }
  try {
    return utf8.decode(b);
  } on FormatException {
    return latin1.decode(b);
  }
}
