// Release-mode timing for the generative covers. Build and run as the app's
// entry point, then read the file it writes:
//   flutter build windows --release -t tool/art_bench.dart --dart-define=ART_OUT=<dir>
//   build\windows\x64\runner\Release\<exe>
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:music_player/art/generative_cover.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  const out = String.fromEnvironment('ART_OUT', defaultValue: '.');
  final lines = <String>['style       record  draw(512)  png(512)  draw(64)   (ms per cover, mean of 20; draw = record + GPU raster)'];
  for (final st in CoverStyle.values) {
    (await GenerativeCover(1, style: st).toImage(512)).dispose(); // warm up
  }
  var worst = 0.0;
  for (final st in CoverStyle.values) {
    final rec = Stopwatch(), ras = Stopwatch(), png = Stopwatch(), thumb = Stopwatch();
    for (var i = 0; i < 20; i++) {
      final c = GenerativeCover(GenerativeCover.seedFor('bench/$i'), style: st);
      rec.start();
      c.record(512).dispose();
      rec.stop();
      ras.start();
      final im = await c.toImage(512);
      await im.toByteData(); // wait for the GPU to finish
      ras.stop();
      im.dispose();
      png.start();
      await c.toPng(512);
      png.stop();
      thumb.start();
      final t = await c.toImage(64);
      await t.toByteData();
      thumb.stop();
      t.dispose();
    }
    String ms(Stopwatch s) => (s.elapsedMicroseconds / 20000).toStringAsFixed(1).padLeft(6);
    worst = [worst, ras.elapsedMicroseconds / 20000].reduce((a, b) => a > b ? a : b);
    lines.add('${st.name.padRight(10)} ${ms(rec)}  ${ms(ras)}   ${ms(png)}   ${ms(thumb)}');
  }
  lines.add('slowest style at 512 px: ${worst.toStringAsFixed(1)} ms');
  File('$out/timing_release.txt').writeAsStringSync('${lines.join('\n')}\n');
  exit(0);
}
