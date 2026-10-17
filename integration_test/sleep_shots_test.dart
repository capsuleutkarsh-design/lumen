// The sleep timer on the real Windows app: the player bar's menu, the Custom… dialog, Bedtime on, and
// Settings → Bedtime. Audio goes to mpv's null output; never the real library.
//   flutter test integration_test/sleep_shots_test.dart -d windows --dart-define=MP_DATA=<scratch>\appdata
//     --dart-define=MP_MUSIC=<folder with testlib> --dart-define=MP_SHOTS=<out>
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:gleo/main.dart';
import 'package:gleo/platform/window.dart';
import 'package:gleo/ui/app.dart';
import 'package:gleo/ui/player_bar.dart';
import 'package:path/path.dart' as p;
import 'package:window_manager/window_manager.dart';

const music = String.fromEnvironment('MP_MUSIC');
final shots = p.join(const String.fromEnvironment('MP_SHOTS'), 'windows');

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('sleep timer shots', (tester) async {
    final data = Directory(const String.fromEnvironment('MP_DATA'));
    if (data.existsSync()) data.deleteSync(recursive: true);
    Directory(shots).createSync(recursive: true);
    await boot(silent: true);
    await windowManager.ensureInitialized();
    Future<void> settle([int ms = 700]) async {
      for (var i = 0; i < ms ~/ 50; i++) {
        await tester.pump(const Duration(milliseconds: 50));
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    }

    Future<void> shot(String name) async {
      await settle();
      await captureShot(name, shots);
    }

    await windowManager.setSize(const Size(1280, 800));
    await setupWindow(lib, () async {});
    await tester.pumpWidget(const App());
    lib.folders = [p.join(music, 'testlib')];
    final sw = Stopwatch()..start();
    while (lib.tracks.isEmpty && sw.elapsed < const Duration(minutes: 2)) {
      await settle(200);
    }
    await engine.playTracks(lib.albums.first.tracks);
    nav.go('albums');
    await settle(1500);

    await tester.tap(find.byIcon(LucideIcons.moon));
    await shot('win_01_sleep_menu');
    await tester.tap(find.text('Custom…'));
    await settle();
    await tester.tap(find.byKey(const ValueKey('sleep.more')));
    await tester.tap(find.byKey(const ValueKey('sleep.more')));
    await shot('win_02_custom_dialog');
    await tester.tap(find.byKey(const ValueKey('sleep.start')));
    await settle();
    expect(lib.setting('sleepCustom'), '47');
    await tester.tap(find.byIcon(LucideIcons.moon));
    await shot('win_03_custom_on_menu');
    await tester.tap(find.text('Bedtime · 47 min'));
    await settle();
    expect(engine.bedtime, isTrue);
    await tester.longPress(find.byIcon(LucideIcons.moonStar)); // shows its tooltip
    await shot('win_04_bedtime_on');
    setSleep(0);
    nav.go('settings');
    await settle();
    await Scrollable.ensureVisible(tester.element(find.byKey(const ValueKey('bedtime.auto'))), alignment: 0.4);
    await settle();
    await tester.tap(find.byKey(const ValueKey('bedtime.auto')));
    await shot('win_05_settings_bedtime');
    expect(bedtimeAuto, 23 * 60);
    await engine.pause();
  });
}
