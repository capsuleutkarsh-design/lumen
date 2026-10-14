// Renders the painterly cover sheets, headless.
//   flutter test tool/art_painted.dart
// Writes to ../_scratch_art3 (next to the worktree), or to $ART_OUT:
//   painted_<style>.png   24 seeds per painted style, labelled
//   painted_sizes.png     the same covers at 512 and 64 px
//   grid_mix.png          24 albums mixing the masterpieces pack and the painted styles, on black
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_player/art/generative_cover.dart';
import 'package:path/path.dart' as p;

import 'art_gallery.dart' show loadInter, text;

final out = Platform.environment['ART_OUT'] ?? p.join(Directory.current.parent.path, '_scratch_art3');

Future<void> save(ui.Picture pic, int w, int h, String name) async {
  final im = await pic.toImage(w, h);
  final png = await im.toByteData(format: ui.ImageByteFormat.png);
  File(p.join(out, name)).writeAsBytesSync(png!.buffer.asUint8List());
  stdout.writeln('wrote ${p.join(out, name)} (${w}x$h)');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('painted gallery', () async {
    Directory(out).createSync(recursive: true);
    await loadInter();
    const styles = GenerativeCover.painted;

    // 1. 24 seeds per style.
    const cell = 300.0, gap = 14.0, label = 24.0, cols = 6, rows = 4;
    for (final style in styles) {
      final rec = ui.PictureRecorder();
      final c = Canvas(rec);
      final w = cols * (cell + gap) + gap, h = rows * (cell + label + gap) + gap;
      c.drawRect(Rect.fromLTWH(0, 0, w, h), Paint()..color = Colors.black);
      for (var i = 0; i < cols * rows; i++) {
        final seed = GenerativeCover.seedFor('painted/${style.name}/$i');
        final im = await GenerativeCover(seed, style: style).toImage(cell.toInt());
        final x = gap + (i % cols) * (cell + gap), y = gap + (i ~/ cols) * (cell + label + gap);
        c.drawImage(im, Offset(x, y), Paint());
        im.dispose();
        text(c, '${style.name}  $seed', Offset(x, y + cell + 5), size: 12);
      }
      await save(rec.endRecording(), w.toInt(), h.toInt(), 'painted_${style.name}.png');
    }

    // 2. Sizes: 4 seeds per style at 512 and at 64 px (shown 1:1).
    {
      const big = 512.0, g = 16.0;
      final w = 4 * (big + g) + g, h = styles.length * (big + 64 + 3 * g) + g;
      final rec = ui.PictureRecorder();
      final c = Canvas(rec);
      c.drawRect(Rect.fromLTWH(0, 0, w, h), Paint()..color = Colors.black);
      for (var si = 0; si < styles.length; si++) {
        for (var i = 0; i < 4; i++) {
          final cov = GenerativeCover(GenerativeCover.seedFor('painted/${styles[si].name}/$i'), style: styles[si]);
          final y = g + si * (big + 64 + 3 * g), x = g + i * (big + g);
          final a = await cov.toImage(512), b = await cov.toImage(64);
          c
            ..drawImage(a, Offset(x, y), Paint())
            ..drawImage(b, Offset(x, y + big + g), Paint());
          a.dispose();
          b.dispose();
        }
      }
      await save(rec.endRecording(), w.toInt(), h.toInt(), 'painted_sizes.png');
    }

    // 3. A mock album grid mixing the masterpieces pack with the painted styles.
    {
      final pack = Directory('assets/covers/masterpieces').listSync().whereType<File>().where((f) => f.path.endsWith('.jpg')).toList()
        ..sort((a, b) => a.path.compareTo(b.path));
      const names = [
        ('Low Tide', 'Marlo Vance'), ('Glass Animals', 'Paper Kites'), ('Night Drive', 'Ostra'),
        ('Unknown Album', 'Various Artists'), ('Hymns for Nobody', 'Elsa Brandt'), ('Field Recordings', 'K. Moreau'),
        ('Saturn Return', 'Juno Park'), ('Soft Machines', 'Holloway'), ('Ashes, Rising', 'The Quiet Hours'),
        ('Lumen Sessions', 'Arun Mehta'), ('Coastlines', 'Fennel'), ('Midnight Static', 'Velvet Ions'),
        ('Ghost Notes', 'Iris & the Owls'), ('Polaroid Summer', 'Teddy Lowe'), ('Monsoon Tapes', 'Ravi Shankar Jr.'),
        ('After Hours', 'Neon Coast'), ('Analog Heart', 'Mira'), ('Slow Fade', 'Dune Theory'),
        ('Blue Hour', 'Okafor'), ('Wild Grass', 'Pine & Ash'), ('Satellites', 'Lark'),
        ('Small Rooms', 'Hannah Ree'), ('Gold Leaf', 'Sora'), ('Echo Park', 'Ventura'),
      ];
      const cw = 196.0, cov = 180.0, pad = 8.0, cols = 6, g = 8.0;
      final w = 24 + cols * (cw + g), h = 70 + 4 * (cov + 78 + g) + 16;
      final rec = ui.PictureRecorder();
      final c = Canvas(rec);
      c.drawRect(Rect.fromLTWH(0, 0, w, h), Paint()..color = Colors.black);
      text(c, 'Albums', const Offset(24, 20), size: 26, color: const Color(0xFFF4F4F5), w: FontWeight.w600);
      for (var i = 0; i < 24; i++) {
        final (title, artist) = names[i];
        final seed = GenerativeCover.seedFor('$artist/$title');
        final ui.Image im;
        if (i % 2 == 0) {
          final codec = await ui.instantiateImageCodec(pack[seed % pack.length].readAsBytesSync());
          im = (await codec.getNextFrame()).image;
        } else {
          im = await GenerativeCover(seed, style: GenerativeCover.painted[(seed >>> 8) % GenerativeCover.painted.length]).toImage((cov * 2).toInt());
        }
        final x = 24 + (i % cols) * (cw + g), y = 70 + (i ~/ cols) * (cov + 78 + g);
        c
          ..save()
          ..clipRRect(RRect.fromRectAndRadius(Rect.fromLTWH(x + pad, y + pad, cov, cov), const Radius.circular(8)))
          ..drawImageRect(im, Rect.fromLTWH(0, 0, im.width.toDouble(), im.height.toDouble()), Rect.fromLTWH(x + pad, y + pad, cov, cov), Paint()..filterQuality = FilterQuality.medium)
          ..restore();
        text(c, title, Offset(x + pad + 4, y + pad + cov + 12), color: const Color(0xFFF4F4F5), w: FontWeight.w500);
        text(c, artist, Offset(x + pad + 4, y + pad + cov + 31));
      }
      await save(rec.endRecording(), w.toInt(), h.toInt(), 'grid_mix.png');
    }

    // 4. Timing in this (debug, software) test run; release numbers come from tool/art_bench.dart.
    final lines = <String>[];
    for (final style in styles) {
      final sw = Stopwatch()..start();
      for (var i = 0; i < 10; i++) {
        (await GenerativeCover(GenerativeCover.seedFor('t/$i'), style: style).toImage(512)).dispose();
      }
      lines.add('${style.name.padRight(10)} ${(sw.elapsedMicroseconds / 10000).toStringAsFixed(1)} ms / 512 px');
    }
    File(p.join(out, 'painted_timing_test.txt')).writeAsStringSync('${lines.join('\n')}\n');
    stdout.writeln(lines.join('\n'));
  }, timeout: Timeout.none);
}
