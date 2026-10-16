import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:gleo/library/db.dart';
import 'package:gleo/library/scanner.dart';
import 'package:path/path.dart' as p;

import 'scanner_test.dart' show writeFlac;

void main() {
  test('P1: a UI write waits less than 100 ms while the scanner decodes big covers', () async {
    final tmp = Directory.systemTemp.createTempSync('mp_lock');
    final lib = p.join(tmp.path, 'lib'), dbPath = p.join(tmp.path, 'library.db');
    // 16 files, each with its own 2000 x 2000 cover (slow to decode, like real 3000 px scans).
    final rnd = Random(1);
    final noise = img.Image(width: 2000, height: 2000);
    for (final px in noise) {
      px.setRgb(rnd.nextInt(256), rnd.nextInt(256), rnd.nextInt(256));
    }
    final jpg = img.encodeJpg(noise);
    for (var i = 0; i < 16; i++) {
      writeFlac(p.join(lib, '$i.flac'), {'TITLE': 'T$i'}, picture: [...jpg, i]); // a trailing byte: a new image to decode
    }
    openDb(dbPath).close();
    final ui = openDb(dbPath);
    var done = false;
    final scanned = scanInBackground(dbPath, p.join(tmp.path, 'covers'), [lib], (_, _) {}).whenComplete(() => done = true);
    var worst = 0, writes = 0;
    while (!done) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
      final sw = Stopwatch()..start();
      ui.execute("INSERT INTO settings(key, value) VALUES('queue', 'x') ON CONFLICT(key) DO UPDATE SET value = excluded.value");
      worst = max(worst, sw.elapsedMilliseconds);
      writes++;
    }
    final r = await scanned;
    ui.close();
    tmp.deleteSync(recursive: true);
    expect(r.added, 16);
    expect(writes, greaterThan(10));
    expect(worst, lessThan(100), reason: 'longest UI write during the scan');
  }, timeout: const Timeout(Duration(minutes: 3)));
}
