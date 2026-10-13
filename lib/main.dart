import 'dart:io';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:path_provider/path_provider.dart';

import 'audio/engine.dart';
import 'library/library.dart';
import 'platform/media_controls.dart';
import 'platform/window.dart';
import 'ui/app.dart';

/// Where the database and cover cache live. Tests point it elsewhere with
/// `--dart-define=MP_DATA=<folder>` so they never touch the real library.
Future<String> dataDir() async {
  const override = String.fromEnvironment('MP_DATA');
  final dir = override.isNotEmpty ? Directory(override) : await getApplicationSupportDirectory();
  dir.createSync(recursive: true);
  return dir.path;
}

Future<void> boot({bool silent = false, MPVLogLevel logLevel = MPVLogLevel.error}) async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  lib = Library(await dataDir())..load();
  engine = Engine(lib, silent: silent, logLevel: logLevel);
  await engine.init();
  MediaControls(engine);
  lib.watch();
  lib.rescan(); // background: picks up anything changed while the app was closed
}

Future<void> main() async {
  await boot();
  await setupWindow(lib, engine.shutdown);
  runApp(const App());
}
