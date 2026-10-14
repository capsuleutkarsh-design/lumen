// Renders generative cover contact sheets, headless.
//   flutter test tool/art_gallery.dart
// Writes to ../_scratch_art (next to the worktree), or to $ART_OUT:
//   gallery_1..3.png  110 covers: 11 styles x 10 seeds, labelled
//   sizes.png         one cover per style at 48, 128 and 512 px
//   grid.png          24 albums in a mock Lumen album grid on black
//   timing.txt        render time per style (debug test mode: slower than release)
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_player/art/generative_cover.dart';
import 'package:path/path.dart' as p;

final out = Platform.environment['ART_OUT'] ?? p.join(Directory.current.parent.path, '_scratch_art');

Future<void> loadInter() async {
  final l = FontLoader('Inter');
  for (final w in ['Regular', 'Medium', 'SemiBold']) {
    l.addFont(Future.value(ByteData.sublistView(File('assets/fonts/Inter-$w.ttf').readAsBytesSync())));
  }
  await l.load();
}

void text(Canvas c, String s, Offset at, {double size = 13, Color color = const Color(0xFFA1A1AA), FontWeight w = FontWeight.w400}) {
  final tp = TextPainter(
    text: TextSpan(text: s, style: TextStyle(fontFamily: 'Inter', fontSize: size, color: color, fontWeight: w)),
    textDirection: TextDirection.ltr,
    maxLines: 1,
    ellipsis: '…',
  )..layout(maxWidth: 400);
  tp.paint(c, at);
}

Future<void> save(ui.Picture pic, int w, int h, String name) async {
  final im = await pic.toImage(w, h);
  final png = await im.toByteData(format: ui.ImageByteFormat.png);
  File(p.join(out, name)).writeAsBytesSync(png!.buffer.asUint8List());
  stdout.writeln('wrote ${p.join(out, name)} (${w}x$h)');
}

Future<ui.Image> cover(int seed, int px, {CoverStyle? style}) => GenerativeCover(seed, style: style).toImage(px);

int albumSeed(int i) => GenerativeCover.seedFor('album/$i');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('art gallery', () async {
    Directory(out).createSync(recursive: true);
    await loadInter();
    const styles = CoverStyle.values;

    // 1. Ten samples per style, four styles per sheet.
    const cell = 240.0, gap = 16.0, label = 26.0, cols = 10;
    for (var sheet = 0; sheet < 3; sheet++) {
      final rec = ui.PictureRecorder();
      final c = Canvas(rec);
      final w = cols * (cell + gap) + gap, h = 4 * (cell + label + gap) + gap;
      c.drawRect(Rect.fromLTWH(0, 0, w, h), Paint()..color = Colors.black);
      for (var row = 0; row < 4 && sheet * 4 + row < styles.length; row++) {
        final style = styles[sheet * 4 + row];
        for (var col = 0; col < cols; col++) {
          final seed = albumSeed(style.index * 100 + col);
          final im = await cover(seed, cell.toInt(), style: style);
          final x = gap + col * (cell + gap), y = gap + row * (cell + label + gap);
          c.drawImage(im, Offset(x, y), Paint());
          text(c, '${style.name}  $seed', Offset(x, y + cell + 6), size: 12);
        }
      }
      await save(rec.endRecording(), w.toInt(), h.toInt(), 'gallery_${sheet + 1}.png');
    }

    // 2. One cover per style at 48, 128 and 512 px.
    {
      final rec = ui.PictureRecorder();
      final c = Canvas(rec);
      const big = 512.0, g = 16.0;
      final w = 6 * (big + g) + g, h = 40 + 48 + g + 128 + g * 2 + 2 * (big + g) + g + 30;
      c.drawRect(Rect.fromLTWH(0, 0, w, h), Paint()..color = Colors.black);
      text(c, 'Same ${styles.length} covers at 48, 128 and 512 px', const Offset(g, 12), size: 16, color: Colors.white);
      for (var i = 0; i < styles.length; i++) {
        final seed = albumSeed(styles[i].index * 100);
        c.drawImage(await cover(seed, 48, style: styles[i]), Offset(g + i * (48 + g), 40), Paint());
        c.drawImage(await cover(seed, 128, style: styles[i]), Offset(g + i * (128 + g), 40 + 48 + g), Paint());
        final bx = g + (i % 6) * (big + g), by = 40 + 48 + g + 128 + g * 2 + (i ~/ 6) * (big + g);
        c.drawImage(await cover(seed, 512, style: styles[i]), Offset(bx, by), Paint());
      }
      await save(rec.endRecording(), w.toInt(), h.toInt(), 'sizes.png');
    }

    // 3. A mock album grid: the seed picks the style, as in the app.
    {
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
        final x = 24 + (i % cols) * (cw + g), y = 70 + (i ~/ cols) * (cov + 78 + g);
        final im = await cover(GenerativeCover.seedFor('$artist/$title'), (cov * 2).toInt());
        c
          ..save()
          ..clipRRect(RRect.fromRectAndRadius(Rect.fromLTWH(x + pad, y + pad, cov, cov), const Radius.circular(8)))
          ..drawImageRect(im, Rect.fromLTWH(0, 0, cov * 2, cov * 2), Rect.fromLTWH(x + pad, y + pad, cov, cov), Paint()..filterQuality = FilterQuality.medium)
          ..restore();
        text(c, title, Offset(x + pad + 4, y + pad + cov + 12), color: const Color(0xFFF4F4F5), w: FontWeight.w500);
        text(c, artist, Offset(x + pad + 4, y + pad + cov + 31));
      }
      await save(rec.endRecording(), w.toInt(), h.toInt(), 'grid.png');
    }

    // 4. The optional initials and Lumen mark (both off by default).
    {
      final rec = ui.PictureRecorder();
      final c = Canvas(rec);
      const sz = 256.0, g = 16.0;
      c.drawRect(const Rect.fromLTWH(0, 0, 6 * (sz + g) + g, 2 * (sz + g) + g), Paint()..color = Colors.black);
      const words = ['Low Tide', 'Night Drive', 'Blue Hour', 'Gold Leaf', 'Echo Park', 'Slow Fade'];
      for (var i = 0; i < 12; i++) {
        final title = words[i % 6];
        final initials = title.split(' ').map((w) => w[0]).join();
        final cov = GenerativeCover(GenerativeCover.seedFor('x/$title/$i'), initials: i < 6 ? initials : null, mark: i >= 6);
        c.drawImage(await cov.toImage(sz.toInt()), Offset(g + (i % 6) * (sz + g), g + (i ~/ 6) * (sz + g)), Paint());
      }
      await save(rec.endRecording(), (6 * (sz + g) + g).toInt(), (2 * (sz + g) + g).toInt(), 'extras.png');
    }

    // 5. Timing (this is a debug-mode test; release numbers come from tool/art_bench.dart).
    final lines = <String>[];
    for (final style in styles) {
      final sw = Stopwatch()..start();
      for (var i = 0; i < 10; i++) {
        (await cover(albumSeed(i), 512, style: style)).dispose();
      }
      lines.add('${style.name.padRight(10)} ${(sw.elapsedMicroseconds / 10000).toStringAsFixed(1)} ms / 512 px');
    }
    File(p.join(out, 'timing_test.txt')).writeAsStringSync('${lines.join('\n')}\n');
    stdout.writeln(lines.join('\n'));
  }, timeout: Timeout.none);
}
