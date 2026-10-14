import 'dart:io';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'audio/engine.dart';
import 'library/library.dart';
import 'platform/licence.dart';
import 'platform/log.dart';
import 'platform/media_controls.dart';
import 'platform/tray.dart';
import 'platform/update.dart';
import 'platform/window.dart';
import 'ui/app.dart';
import 'ui/pages/credits.dart';
import 'ui/theme.dart';

/// Where the database, cover cache and log live:
/// - `--dart-define=MP_DATA=<folder>` (tests, so they never touch the real library);
/// - `userdata\` next to lumen.exe when a `portable.txt` is there (the portable zip);
/// - otherwise `%APPDATA%\Utkarsh Tripathi\Lumen` (from CompanyName and ProductName in Runner.rc).
Future<String> dataPath() async {
  const override = String.fromEnvironment('MP_DATA');
  if (override.isNotEmpty) return override;
  final exeDir = p.dirname(Platform.resolvedExecutable);
  if (File(p.join(exeDir, 'portable.txt')).existsSync()) return p.join(exeDir, 'userdata');
  return (await getApplicationSupportDirectory()).path;
}

Future<String> dataDir() async {
  final dir = Directory(await dataPath())..createSync(recursive: true);
  return dir.path;
}

Future<void> boot({bool silent = false, MPVLogLevel logLevel = MPVLogLevel.error}) async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  // Cover thumbnails are a cache: Local AppData, except under MP_DATA where test data stays in one folder.
  final cache = const String.fromEnvironment('MP_DATA').isEmpty ? (await getApplicationCacheDirectory()).path : null;
  lib = Library(await dataDir(), cacheDir: cache)..load();
  engine = Engine(lib, silent: silent, logLevel: logLevel);
  await engine.init();
  MediaControls(engine);
  lib.watch();
  lib.rescan(); // background: picks up anything changed while the app was closed
}

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  // main.cpp passes the version from pubspec.yaml, as baked into lumen.exe.
  for (final a in args) {
    if (a.startsWith('--app-version=')) appVersion = a.substring(14);
  }
  final data = await dataPath();
  startLog(data);
  log('Lumen $appVersion starting; data in $data');
  final problems = await checkLicence();
  if (problems.isNotEmpty) {
    log('Licence check failed: ${problems.join('; ')}');
    return runApp(StartupScreen.refused(problems));
  }
  registerLicences();
  await start(data);
}

/// Starts the app; when anything fails, shows what went wrong instead of an invisible window.
Future<void> start(String data) async {
  try {
    await boot();
    loadAppearance();
    await setupWindow(lib, engine.shutdown, background: C.bg);
    runApp(const App());
    setupTray(lib, engine).catchError((Object e) => log('Tray icon: $e')); // Lumen works without it
    if (lib.setting('updateCheck') == '1') checkForUpdate();
  } catch (e, s) {
    log('Start-up failed: $e\n$s');
    runApp(StartupScreen.failed('$e', data, () => startFresh(data)));
  }
}

/// Sets the library aside (renamed, never deleted) and starts again with an empty one.
/// ponytail: if the failure came after the engine started, a second engine starts; restart Lumen if that ever matters.
Future<void> startFresh(String data) async {
  try {
    lib.db.close(); // the library may have opened before something else failed
  } catch (_) {}
  log('Started fresh; the old library is kept as library.db.broken-${setAsideLibrary(data)}');
  await start(data);
}

/// Renames library.db and its -wal/-shm files to `*.broken-<date>`; nothing is deleted. Returns the date part.
String setAsideLibrary(String data) {
  final stamp = DateTime.now().toIso8601String().replaceAll(RegExp(r'[:.]'), '-').substring(0, 19);
  for (final name in ['library.db', 'library.db-wal', 'library.db-shm']) {
    final f = File(p.join(data, name));
    if (f.existsSync()) f.renameSync('${f.path}.broken-$stamp');
  }
  return stamp;
}
