import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_player/audio/engine.dart';
import 'package:music_player/library/lyrics.dart';
import 'package:music_player/library/m3u.dart';
import 'package:music_player/main.dart';
import 'package:music_player/platform/log.dart';
import 'package:music_player/platform/update.dart';
import 'package:music_player/platform/window.dart';
import 'package:music_player/ui/pages/credits.dart';
import 'package:path/path.dart' as p;

void main() {
  test("media_kit's pointer file from an earlier process with this id is dropped; this process's own stays", () {
    final f = File(p.join(Directory.systemTemp.path, 'com.alexmercerind.media_kit.NativeReferenceHolder.$pid'));
    expect(processStart().isBefore(DateTime.now()), isTrue);
    expect(DateTime.now().difference(processStart()), lessThan(const Duration(hours: 1)));
    f.writeAsStringSync('123456'); // a dead process's pointer
    f.setLastModifiedSync(DateTime(2026, 1, 1));
    dropStalePointerFile();
    expect(f.existsSync(), isFalse);
    f.writeAsStringSync('123456'); // written by this process (hot restart): kept
    dropStalePointerFile();
    expect(f.existsSync(), isTrue);
    f.deleteSync();
  });

  test('window restore: only bounds that are on a connected display', () {
    const screens = [Rect.fromLTWH(0, 0, 1920, 1032), Rect.fromLTWH(1920, 0, 2560, 1400)];
    expect(restorableBounds([100, 80, 1360, 860, 0], screens), const Rect.fromLTWH(100, 80, 1360, 860));
    expect(restorableBounds([2000, 50, 1500, 900, 0], screens), isNotNull, reason: 'second monitor');
    expect(restorableBounds([2000, 50, 1500, 900, 0], screens.take(1).toList()), isNull, reason: 'second monitor unplugged');
    expect(restorableBounds([-32000, -32000, 160, 28, 0], screens), isNull, reason: 'closed while minimised (0.1.1)');
    expect(restorableBounds([-1300, 100, 1360, 860, 0], screens), isNull, reason: 'mostly off the left edge');
  });

  test('update check: version order', () {
    expect(isNewer('v0.3.0', '0.2.0-beta+3'), isTrue);
    expect(isNewer('v0.2.0', '0.2.0-beta+3'), isTrue);
    expect(isNewer('v0.2.0-beta', '0.2.0-beta+3'), isFalse);
    expect(isNewer('v0.1.1-beta', '0.2.0-beta+3'), isFalse);
    expect(isNewer('v0.10.0', '0.9.9'), isTrue);
  });

  test('log rotates past 1 MB', () {
    final dir = Directory.systemTemp.createTempSync('lumen_log');
    final (print, onError) = (debugPrint, FlutterError.onError);
    addTearDown(() {
      dir.deleteSync(recursive: true);
      debugPrint = print;
      FlutterError.onError = onError;
      PlatformDispatcher.instance.onError = null;
    });
    File(p.join(dir.path, 'lumen.log')).writeAsStringSync('x' * ((1 << 20) + 1));
    startLog(dir.path);
    log('after rotation');
    expect(File(p.join(dir.path, 'lumen.log.1')).lengthSync(), greaterThan(1 << 20));
    expect(File(p.join(dir.path, 'lumen.log')).readAsStringSync(), contains('after rotation'));
  });

  test('untrusted LRC and M3U do not throw', () {
    expect(parseLyrics('[99999999999999999999:00.00]boom\n[00:01.00]ok').lines.single.$2, 'ok');
    expect(parseLyrics('[offset:+99999999999999999999]\n[00:01.00]x').lines.single.$1, const Duration(seconds: 1));
    expect(parseM3u('file:///C:/Music/Beyonc%C3%A9/a%20b.flac', r'C:\pl'), [r'C:\Music\Beyoncé\a b.flac']);
    final dir = Directory.systemTemp.createTempSync('lumen_m3u');
    addTearDown(() => dir.deleteSync(recursive: true));
    final f = File(p.join(dir.path, 'latin1.m3u'))..writeAsBytesSync(latin1.encode('C:\\Music\\Beyonc\u00e9\\a.flac\r\n'));
    expect(parseM3u(readText(f.path), dir.path), [r'C:\Music\Beyoncé\a.flac']);
  });

  testWidgets('start-up failure: a visible screen, and Start fresh keeps the old library renamed', (tester) async {
    var pressed = false;
    await tester.pumpWidget(StartupScreen.failed('file is not a database\nCausing statement: ...', r'C:\data', () async => pressed = true));
    expect(find.text('Lumen could not start'), findsOneWidget);
    expect(find.textContaining('Causing statement'), findsNothing, reason: 'only the first line; the rest is in the log');
    await tester.tap(find.text('Start fresh'));
    expect(pressed, isTrue);

    final dir = Directory.systemTemp.createTempSync('lumen_fresh');
    addTearDown(() => dir.deleteSync(recursive: true));
    for (final n in ['library.db', 'library.db-wal', 'library.db-shm']) {
      File(p.join(dir.path, n)).writeAsStringSync('broken $n');
    }
    final stamp = setAsideLibrary(dir.path);
    final names = [for (final f in dir.listSync()) p.basename(f.path)]..sort();
    expect(names, ['library.db-shm.broken-$stamp', 'library.db-wal.broken-$stamp', 'library.db.broken-$stamp']);
  });
}
