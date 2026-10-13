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

final _stamp = RegExp(r'\[(\d+):(\d+)(?:[.:](\d+))?\]');
final _offset = RegExp(r'^\[offset:\s*([+-]?\d+)\]', caseSensitive: false);

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
    final bytes = lrc.readAsBytesSync();
    String text;
    try {
      text = utf8.decode(bytes);
    } on FormatException {
      text = latin1.decode(bytes);
    }
    return parseLyrics(text.replaceFirst('\uFEFF', ''));
  }
  if (embedded != null && embedded.trim().isNotEmpty) return parseLyrics(embedded);
  return null;
}
