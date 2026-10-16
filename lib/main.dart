import 'dart:io';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'art/art_cache.dart';
import 'art/art_sources.dart';
import 'audio/engine.dart';
import 'library/library.dart';
import 'platform/android.dart';
import 'platform/licence.dart';
import 'platform/log.dart';
import 'platform/media_controls.dart';
import 'platform/tray.dart';
import 'platform/update.dart';
import 'platform/window.dart';
import 'ui/app.dart';
import 'ui/mini_player.dart';
import 'ui/pages/credits.dart';
import 'ui/theme.dart';

/// Where the database, cover cache and log live:
/// - `--dart-define=MP_DATA=<folder>` (tests, so they never touch the real library);
/// - `userdata\` next to gleo.exe when a `portable.txt` is there (the portable zip);
/// - otherwise `%APPDATA%\Utkarsh Tripathi\Gleo` (from CompanyName and ProductName in Runner.rc).
///   The first time, Lumen's data (the app's old name) is copied there from `...\Lumen`.
Future<String> dataPath() async {
  const override = String.fromEnvironment('MP_DATA');
  if (override.isNotEmpty) return override;
  final exeDir = p.dirname(Platform.resolvedExecutable);
  if (File(p.join(exeDir, 'portable.txt')).existsSync()) return p.join(exeDir, 'userdata');
  final data = (await getApplicationSupportDirectory()).path;
  if (Platform.isWindows) _copyFromLumen(p.join(p.dirname(data), 'Lumen'), data);
  return data;
}

/// Notes made before the log starts (see [main]).
final _early = <String>[];

bool _copyFromLumen(String from, String to) {
  void note(String s) => logPath == null ? _early.add(s) : log(s);
  try {
    final copied = copyOldFolder(from, to);
    if (copied) note('Copied $from to $to (the old folder is kept)');
    return copied;
  } catch (e) {
    // ponytail: not retried (the app then writes into the new folder); the old folder is untouched.
    note('Could not copy $from to $to: $e');
    return false;
  }
}

/// Copies the folder [from] to [to] when [from] exists and [to] is missing or empty; [from] is kept.
/// It copies into `<to>.copying` first, so a copy cut short never looks finished. Returns whether it copied.
bool copyOldFolder(String from, String to) {
  final old = Directory(from), now = Directory(to);
  if (!old.existsSync() || (now.existsSync() && now.listSync().isNotEmpty)) return false;
  final tmp = Directory('$to.copying');
  if (tmp.existsSync()) tmp.deleteSync(recursive: true); // only our own copy, cut short last time
  tmp.createSync(recursive: true);
  for (final e in old.listSync(recursive: true, followLinks: false)) {
    final dest = p.join(tmp.path, p.relative(e.path, from: from));
    if (e is Directory) {
      Directory(dest).createSync(recursive: true);
    } else if (e is File) {
      Directory(p.dirname(dest)).createSync(recursive: true);
      e.copySync(dest);
    }
  }
  if (now.existsSync()) now.deleteSync(); // the empty folder path_provider made (not recursive)
  tmp.renameSync(to);
  return true;
}

Future<String> dataDir() async {
  final dir = Directory(await dataPath())..createSync(recursive: true);
  return dir.path;
}

Future<void> boot({bool silent = false, MPVLogLevel logLevel = MPVLogLevel.error}) async {
  WidgetsFlutterBinding.ensureInitialized();
  initMediaKit();
  // Cover thumbnails are a cache: Local AppData, except under MP_DATA where test data stays in one folder.
  final cache = const String.fromEnvironment('MP_DATA').isEmpty ? (await getApplicationCacheDirectory()).path : null;
  // Lumen's cover thumbnails come along too, and the library's cover paths follow them.
  final oldCovers = cache != null && Platform.isWindows ? p.join(p.dirname(cache), 'Lumen', 'covers') : null;
  final coversCopied = oldCovers != null && _copyFromLumen(oldCovers, p.join(cache!, 'covers'));
  lib = Library(await dataDir(), cacheDir: cache)..load();
  if (coversCopied) lib.repointCovers(oldCovers);
  ArtCache.init(p.join(p.dirname(lib.coverDir), 'art')); // generated covers, next to the thumbnails
  await loadArtPacks();
  engine = Engine(lib, silent: silent, logLevel: logLevel);
  await engine.init();
  await sound.init();
  MediaControls(engine);
  if (Platform.isAndroid) {
    // ponytail: AudioService.init runs once per process; Start fresh after it would throw (restart Gleo).
    await initAndroid();
    useMusicFolder(lib);
    await startAndroidMedia(engine);
    AppLifecycleListener(onResume: lib.rescan); // Android has no recursive folder watch: rescan on return
  }
  lib.watch();
  lib.rescan(); // background: picks up anything changed while the app was closed
}

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  // main.cpp passes the version from pubspec.yaml, as baked into gleo.exe.
  for (final a in args) {
    if (a.startsWith('--app-version=')) appVersion = a.substring(14);
  }
  if (Platform.isAndroid) appVersion = await androidVersion() ?? appVersion;
  final data = await dataPath();
  startLog(data);
  log('Gleo $appVersion starting; data in $data');
  _early.forEach(log);
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
    await setupWindow(lib, () {
      sound.save();
      return engine.shutdown();
    }, background: C.bg);
    runApp(const App());
    trayItems.add((() => nav.mini ? 'Full window' : 'Mini player', () => setMini(!nav.mini)));
    var mini = nav.mini;
    nav.addListener(() {
      if (nav.mini == mini) return;
      mini = nav.mini;
      trayMenu().catchError((Object e) => log('Tray menu: $e'));
    });
    setupTray(lib, engine).catchError((Object e) => log('Tray icon: $e')); // Gleo works without it
    if (lib.setting('updateCheck') == '1') checkForUpdate();
  } catch (e, s) {
    log('Start-up failed: $e\n$s');
    runApp(StartupScreen.failed('$e', data, () => startFresh(data)));
  }
}

/// Sets the library aside (renamed, never deleted) and starts again with an empty one.
/// ponytail: if the failure came after the engine started, a second engine starts; restart Gleo if that ever matters.
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
