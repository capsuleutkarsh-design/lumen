// Shared setup for the tests that drive the real libmpv. They need the DLL from
// `flutter build windows` and the test music in _scratch\testlib
// (tool\make_testlib.ps1, or point MP_TESTLIB at a copy); without them they skip.
// Data goes to a temp folder, never the real library.
import 'dart:convert';
import 'dart:io';

import 'package:media_kit/media_kit.dart' hide Track;
import 'package:music_player/audio/engine.dart';
import 'package:music_player/library/library.dart';
import 'package:music_player/library/models.dart';
import 'package:path/path.dart' as p;

final root = Directory.current.path;
final dll = p.join(root, 'build', 'windows', 'x64', 'runner', 'Release', 'libmpv-2.dll');
final testlib = Platform.environment['MP_TESTLIB'] ?? p.join(root, '_scratch', 'testlib');

/// Why the mpv tests are skipped, or null when they can run.
final String? noMpv = !File(dll).existsSync()
    ? 'needs libmpv-2.dll: run flutter build windows first'
    : !Directory(testlib).existsSync()
    ? 'needs the test music in _scratch/testlib'
    : null;

late Library lib;
late String data;
final _engines = <Engine>[];
final _moved = <int, String>{};

Future<void> setUpLibrary() async {
  MediaKit.ensureInitialized(libmpv: dll);
  data = Directory.systemTemp.createTempSync('lumen_test_').path;
  lib = Library(data)..load();
  lib.setSetting('folders', jsonEncode([testlib]));
  await lib.rescan();
}

/// A fresh engine on the shared library: null audio output unless [silent] is false
/// (then the real device in shared mode, at volume 0).
Future<Engine> newEngine({bool silent = true}) async {
  lib.setSetting('volume', '0');
  final e = Engine(lib, silent: silent);
  await e.init();
  _engines.add(e);
  return e;
}

Future<void> closeEngine(Engine e) async {
  _engines.remove(e);
  await e.shutdown();
}

/// After each test: engines closed, moved files put back, saved state and plays cleared.
Future<void> resetAll() async {
  for (final e in List.of(_engines)) {
    await closeEngine(e);
  }
  for (final m in _moved.entries) {
    lib.db.execute('UPDATE tracks SET path = ? WHERE id = ?', [m.value, m.key]);
  }
  _moved.clear();
  lib.db.execute("DELETE FROM settings WHERE key IN ('queue', 'queue_pos', 'muted', 'audio_device', 'exclusive')");
  lib.db.execute('DELETE FROM plays');
  lib.load();
}

/// Points a track at another file for this test only.
Track repoint(Track t, String path) {
  _moved.putIfAbsent(t.id, () => t.path);
  lib.db.execute('UPDATE tracks SET path = ? WHERE id = ?', [path, t.id]);
  lib.load();
  return lib.byId[t.id]!;
}

/// A file mpv can't make sense of.
String corruptFile() {
  final f = p.join(data, 'corrupt.flac');
  File(f).writeAsBytesSync(List.generate(200000, (i) => (i * 7919) & 0xFF));
  return f;
}

List<Track> album(String title) => lib.albums.firstWhere((a) => a.title == title).tracks;

/// (track id, skipped) rows of the play log.
List<(int, bool)> plays() => [for (final r in lib.db.select('SELECT track_id, skipped FROM plays')) (r['track_id'] as int, r['skipped'] == 1)];

NativePlayer mpvOf(Engine e) => e.player.platform as NativePlayer;

Future<void> wait(int ms) => Future<void>.delayed(Duration(milliseconds: ms));

Future<void> waitFor(bool Function() ok, {Duration timeout = const Duration(seconds: 10)}) async {
  final sw = Stopwatch()..start();
  while (!ok() && sw.elapsed < timeout) {
    await wait(20);
  }
}

Future<void> playingPast(Engine e, [Duration d = const Duration(milliseconds: 300)]) =>
    waitFor(() => e.playing && e.position.value > d);
