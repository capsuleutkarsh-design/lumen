// Prints what the tag reader sees for every audio file under the given folders.
// Usage: dart run tool/dump_tags.dart <folder> [...]
import 'dart:io';

import 'package:gleo/library/tags.dart';
import 'package:path/path.dart' as p;

void main(List<String> dirs) {
  for (final d in dirs) {
    for (final f in Directory(d).listSync(recursive: true).whereType<File>()) {
      if (!audioExtensions.contains(p.extension(f.path).toLowerCase())) continue;
      final t = readTags(f.path);
      stdout.writeln(
        '${p.relative(f.path, from: d)}\n'
        '   ${t.codec} ${t.bitDepth}/${t.sampleRate} ch${t.channels} ${t.bitrate}k ${t.durationMs}ms | '
        '${t.title} | ${t.artist} | aa=${t.albumArtist} | ${t.album} | #${t.track} d${t.disc} | ${t.year} | '
        '${t.genre} | comp=${t.compilation} | pic=${t.picture?.length} | lyr=${t.lyrics?.length}',
      );
    }
  }
}
