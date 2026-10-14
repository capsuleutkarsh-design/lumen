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

/// A text file in UTF-8, or Latin-1 when it is not valid UTF-8 (older .lrc and .m3u files).
String readText(String path) {
  final bytes = File(path).readAsBytesSync();
  try {
    return utf8.decode(bytes).replaceFirst('\uFEFF', '');
  } on FormatException {
    return latin1.decode(bytes);
  }
}
