// Builds _scratch/shots/v1.png: Wora's screenshots above ours, then every other page.
// Usage: dart run tool/contact_sheet.dart
import 'dart:io';

import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

const tileW = 720, tileH = 450, gap = 24, label = 36, cols = 4;

void main() {
  final root = p.dirname(p.dirname(Platform.script.toFilePath()));
  final shots = p.join(root, '_scratch', 'shots');
  final wora = p.join(root, 'docs', 'study', 'wora');
  img.Image load(String f) => img.decodePng(File(f).readAsBytesSync())!;

  final compare = [
    ('Home', 'Home_Page.png', '01_home.png'),
    ('Album', 'Album_Page.png', '03_album_two_discs.png'),
    ('Synced lyrics', 'Synced_Lyrics.png', '13_lyrics_synced.png'),
    ('Search', 'Search_Console.png', '15_search.png'),
  ];
  final used = {for (final c in compare) c.$3};
  final rest =
      (Directory(shots)
            .listSync()
            .whereType<File>()
            .map((f) => p.basename(f.path))
            .where((n) => RegExp(r'^\d\d\w?_.*\.png$').hasMatch(n) && !used.contains(n))
            .toList())
        ..sort();

  final rows = 2 + (rest.length / cols).ceil();
  final sheet = img.Image(width: cols * tileW + (cols + 1) * gap, height: 90 + rows * (tileH + label + gap) + gap);
  img.fill(sheet, color: img.ColorRgb8(0, 0, 0));
  img.drawString(
    sheet,
    'Music Player v1 - Wora (top row, reference) vs v1 (second row), then every other page',
    font: img.arial24,
    x: gap,
    y: 30,
    color: img.ColorRgb8(240, 240, 240),
  );

  void tile(img.Image src, String text, int col, int row) {
    final x = gap + col * (tileW + gap), y = 90 + row * (tileH + label + gap);
    // Fit inside the tile, keeping the aspect ratio.
    final scale = [tileW / src.width, tileH / src.height].reduce((a, b) => a < b ? a : b);
    final s = img.copyResize(
      src,
      width: (src.width * scale).round(),
      height: (src.height * scale).round(),
      interpolation: img.Interpolation.average,
    );
    img.compositeImage(sheet, s, dstX: x + (tileW - s.width) ~/ 2, dstY: y + label + (tileH - s.height) ~/ 2);
    img.drawString(sheet, text, font: img.arial14, x: x, y: y + 10, color: img.ColorRgb8(170, 170, 178));
  }

  for (var i = 0; i < compare.length; i++) {
    final (name, w, ours) = compare[i];
    tile(load(p.join(wora, w)), 'Wora: $name', i, 0);
    tile(load(p.join(shots, ours)), 'v1: $name', i, 1);
  }
  for (var i = 0; i < rest.length; i++) {
    tile(load(p.join(shots, rest[i])), 'v1: ${rest[i].replaceFirst(RegExp(r'^\d\d\w?_'), '').replaceAll('.png', '').replaceAll('_', ' ')}', i % cols, 2 + i ~/ cols);
  }
  final out = p.join(shots, 'v1.png');
  File(out).writeAsBytesSync(img.encodePng(sheet, level: 6));
  stdout.writeln('wrote $out (${sheet.width}x${sheet.height})');
}
