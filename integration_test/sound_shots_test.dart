// Screenshots of the Sound page. Audio goes to mpv's null output: nothing is audible and no
// device is opened, so "exclusive mode" here is simulated. Run:
//   flutter test integration_test/sound_shots_test.dart -d windows
//     --dart-define=MP_DATA=<scratch>\appdata --dart-define=MP_ROOT=<repo>
//     --dart-define=MP_MUSIC=<folder holding testlib> --dart-define=MP_SHOTS=<out folder>
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:gleo/audio/sound.dart';
import 'package:gleo/main.dart';
import 'package:gleo/ui/app.dart';
import 'package:gleo/ui/widgets.dart';
import 'package:path/path.dart' as p;
import 'package:window_manager/window_manager.dart';

const root = String.fromEnvironment('MP_ROOT');
const _music = String.fromEnvironment('MP_MUSIC');
const _shots = String.fromEnvironment('MP_SHOTS');
final music = _music.isEmpty ? p.join(root, '_scratch') : _music;
final shots = _shots.isEmpty ? p.join(root, '_scratch', 'shots') : _shots;

Future<void> waitFor(bool Function() ok, {Duration timeout = const Duration(seconds: 60)}) async {
  final sw = Stopwatch()..start();
  while (!ok()) {
    if (sw.elapsed > timeout) throw TimeoutException('waitFor');
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('sound page screenshots', (tester) async {
    expect(root, isNotEmpty, reason: 'pass --dart-define=MP_ROOT=<repo>');
    final data = Directory(const String.fromEnvironment('MP_DATA'));
    if (data.existsSync()) data.deleteSync(recursive: true);
    Directory(shots).createSync(recursive: true);
    final errors = <String>[];
    final old = FlutterError.onError;
    FlutterError.onError = (d) {
      errors.add(d.exceptionAsString().split('\n').first);
      old?.call(d);
    };
    await boot(silent: true);
    expect(await engine.getOption('ao'), 'null', reason: 'never a real device');
    await windowManager.ensureInitialized();
    await windowManager.setSize(const Size(1440, 1000));

    Future<void> settle([int ms = 700]) async {
      for (var i = 0; i < ms ~/ 50; i++) {
        await tester.pump(const Duration(milliseconds: 50));
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    }

    final log = StringBuffer();
    Future<void> shot(String name) async {
      await settle();
      await captureShot(name, shots);
      log.writeln('$name: ${errors.isEmpty ? 'ok' : 'ERRORS ${errors.toSet().join(' | ')}'}');
      File(p.join(shots, 'sound_shots_log.txt')).writeAsStringSync(log.toString());
    }

    Future<void> show(String text) async {
      await Scrollable.ensureVisible(tester.element(find.text(text).first), alignment: 0.02);
      await settle(300);
    }

    await tester.pumpWidget(const App());
    lib.folders = [p.join(music, 'testlib')];
    await waitFor(() => lib.scan.value == null && lib.tracks.length >= 20, timeout: const Duration(minutes: 3));
    final song = lib.tracks.firstWhere((t) => t.path.endsWith(r'Northern Lights (2017)\01 First Light.flac')); // 16/44.1
    await engine.playTracks(lib.albumByKey[song.albumKey]!.tracks);
    await waitFor(() => engine.outRate > 0 && engine.position.value > const Duration(milliseconds: 300));

    // 1. Defaults: shared mode, Best quality on, EQ off.
    nav.go('sound');
    await shot('sound_01_path_shared');

    // 2. The graphic EQ with a preset.
    sound.change((s) => s.eq = builtInPresets.firstWhere((x) => x.name == 'Rock').copy());
    await show('Equalizer');
    await shot('sound_02_graphic_rock');

    // 3. The preset menu.
    await tester.tap(find.textContaining('Preset:'));
    await shot('sound_03_presets_menu');
    await tester.tap(find.text('Headphone correction (AutoEQ)…'));
    await settle(300);

    // 4. The AutoEQ import dialog with a pasted ParametricEQ.txt.
    await tester.enterText(find.byType(TextField).first, File(p.join(root, 'test', 'fixtures', 'autoeq_ParametricEQ.txt')).readAsStringSync());
    await tester.enterText(find.byType(TextField).at(1), 'Sony WH-1000XM5');
    await shot('sound_04_autoeq_dialog');
    await tester.tap(find.text('Use this correction'));
    await settle(300);

    // 5. Advanced: the imported correction as draggable points on the real response curve.
    await show('Equalizer');
    await shot('sound_05_advanced_autoeq');
    sound.change((s) => s.eq = Eq(on: true, advanced: true, bands: [
      Band(BandType.highPass, 40, 0, 0.71),
      Band(BandType.lowShelf, 120, 4, 0.71),
      Band(BandType.peak, 900, -3, 2.5),
      Band(BandType.peak, 3200, 2.5, 1.2),
      Band(BandType.notch, 6000, 0, 8),
      Band(BandType.highShelf, 11000, -2, 0.71),
    ], name: 'Custom'));
    await show('Equalizer');
    await shot('sound_06_advanced_bands');

    // 6. Headphones and loudness.
    sound.change((s) => s
      ..crossfeed = Crossfeed.medium
      ..replayGain = ReplayGain.auto);
    await show('Headphones');
    await shot('sound_07_headphones_loudness');

    // 7. Bit-perfect: exclusive (simulated on the null output), 100 %, nothing on.
    sound.change((s) => s
      ..eq.on = false
      ..crossfeed = Crossfeed.off
      ..replayGain = ReplayGain.off);
    await engine.setVolume(100);
    await engine.setExclusive(true);
    await waitFor(() => engine.outRate > 0 && sound.chain.isEmpty);
    await settle(600);
    expect(sound.path.why, isEmpty, reason: '${sound.path.why}');
    expect(find.byKey(const ValueKey('bitperfect')), findsOneWidget);
    await shot('sound_08_bitperfect');

    // 8. The player bar's format badge tooltip.
    final tip = find.ancestor(of: find.byType(FormatBadge), matching: find.byType(Tooltip)).first;
    tester.state<TooltipState>(tip).ensureTooltipVisible();
    await shot('sound_09_badge_tooltip_bitperfect');
    Tooltip.dismissAllToolTips();
    await engine.setVolume(60);
    sound.change((s) => s.eq.on = true);
    await settle(600);
    tester.state<TooltipState>(tip).ensureTooltipVisible();
    await shot('sound_10_badge_tooltip_not');
    Tooltip.dismissAllToolTips();
    await engine.setExclusive(false);

    // 9. Settings now points to the Sound page.
    nav.go('settings');
    await shot('sound_11_settings_after');

    // 10. The light theme: the path card, the graphic EQ and the advanced curve.
    setAppearance('light');
    nav.go('sound');
    await shot('sound_12_light_path');
    sound.change((s) => s.eq = builtInPresets.firstWhere((x) => x.name == 'Rock').copy());
    await show('Equalizer');
    await shot('sound_13_light_graphic');
    sound.change((s) => s.eq = Eq(on: true, advanced: true, bands: [
      Band(BandType.lowShelf, 120, 4, 0.71),
      Band(BandType.peak, 900, -3, 2.5),
      Band(BandType.peak, 3200, 2.5, 1.2),
      Band(BandType.highShelf, 11000, -2, 0.71),
    ], name: 'Custom'));
    await show('Equalizer');
    await shot('sound_14_light_advanced');
    setAppearance('dark');

    await engine.shutdown();
    FlutterError.onError = old;
    expect(errors, isEmpty, reason: errors.toSet().join('\n'));
  });
}
