// The Sound page as a user drives it: presets, slider drags (sent as live commands),
// the AutoEQ import dialog, Advanced bands. The engine records what it would send to mpv.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_player/audio/engine.dart';
import 'package:music_player/audio/sound.dart';
import 'package:music_player/library/library.dart';
import 'package:music_player/ui/app.dart';
import 'package:music_player/ui/pages/sound.dart';
import 'package:music_player/ui/theme.dart';
import 'package:music_player/ui/widgets.dart';

/// Records the mpv calls instead of making them.
class RecordingEngine extends Engine {
  RecordingEngine(super.lib);
  final sent = <String>[];
  String af = '';
  @override
  Future<void> setOption(String name, String value) async {
    if (name == 'af') af = value;
    sent.add('$name=$value');
  }

  @override
  Future<String> getOption(String name) async => name == 'af' ? af : '';
  @override
  Future<void> command(List<String> args) async => sent.add(args.join(' '));
}

late Directory tmp;

Future<RecordingEngine> pumpPage(WidgetTester tester, {Size size = const Size(1200, 2600)}) async {
  final e = RecordingEngine(lib);
  engine = e;
  await sound.init();
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(theme: buildTheme(), scaffoldMessengerKey: messengerKey, home: const Scaffold(body: SoundPage())),
  );
  return e;
}

/// Lets the debounced apply and save run.
Future<void> flush(WidgetTester tester) => tester.pump(const Duration(milliseconds: 600));

void main() {
  setUp(() {
    tmp = Directory.systemTemp.createTempSync('lumen_sound_ui');
    lib = Library(tmp.path)..load();
  });
  tearDown(() {
    lib.db.close();
    tmp.deleteSync(recursive: true);
  });

  testWidgets('renders every section without overflow, wide and narrow', (tester) async {
    await pumpPage(tester);
    for (final t in ['Signal path', 'Not bit-perfect', 'Output', 'Equalizer', 'Headphones', 'Loudness', 'Best quality on this device']) {
      expect(find.text(t), findsWidgets, reason: t);
    }
    expect(find.byType(Slider), findsNWidgets(11), reason: 'preamp + 10 bands');
    await pumpPage(tester, size: const Size(760, 3200));
    expect(tester.takeException(), isNull);
  });

  testWidgets('a preset from the menu turns the EQ on and builds the chain', (tester) async {
    final e = await pumpPage(tester);
    await tester.tap(find.textContaining('Preset:'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rock').last);
    await tester.pumpAndSettle();
    await flush(tester);
    expect(sound.s.eq.name, 'Rock');
    expect(sound.s.eq.on, isTrue);
    expect(e.af, startsWith('@lumen:lavfi=[aformat=sample_fmts=fltp,volume@pre='));
    expect(e.af, contains('equalizer@b0=f=31:t=q:w=1.41:g=4'));
    expect(find.text('Preset: Rock'), findsOneWidget);
    expect(lib.setting('sound'), contains('"name":"Rock"'), reason: 'saved');
  });

  testWidgets('dragging a graphic slider sends live commands, not a new chain', (tester) async {
    final e = await pumpPage(tester);
    sound.change((s) => s.eq = builtInPresets.first.copy());
    await flush(tester);
    final chains = e.sent.where((x) => x.startsWith('af=')).length;
    await tester.drag(find.byType(Slider).at(6), const Offset(0, -40)); // the 1 kHz slider, upwards
    await flush(tester);
    expect(sound.s.eq.graphic[5], greaterThan(0));
    expect(sound.s.eq.name, 'Custom');
    expect(e.sent.where((x) => x.startsWith('af=')).length, chains, reason: 'no rebuild');
    expect(e.sent.where((x) => x.startsWith('af-command lumen g ')).last, endsWith('equalizer@b5'));
    expect(e.sent.where((x) => x.startsWith('af-command lumen volume ')), isNotEmpty, reason: 'headroom follows');
  });

  testWidgets('AutoEQ import: paste, preview, use; saved as a preset', (tester) async {
    await pumpPage(tester);
    await tester.tap(find.textContaining('Preset:'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Headphone correction (AutoEQ)…'));
    await tester.pumpAndSettle();
    expect(find.text('Open AutoEQ results'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, File('test/fixtures/autoeq_ParametricEQ.txt').readAsStringSync());
    await tester.enterText(find.byType(TextField).at(1), 'Sony WH-1000XM5');
    await tester.pump();
    expect(find.text('10 filters · preamp −6.2 dB'), findsOneWidget);
    await tester.tap(find.text('Use this correction'));
    await tester.pumpAndSettle();
    await flush(tester);
    expect(sound.s.eq.name, 'Sony WH-1000XM5');
    expect(sound.s.eq.advanced, isTrue);
    expect(sound.s.eq.bands.length, 10);
    expect(sound.s.presets.single.name, 'Sony WH-1000XM5');
    expect(find.text('Preset: Sony WH-1000XM5'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3)); // the toast
  });

  testWidgets('Advanced: add a band and type its values', (tester) async {
    await pumpPage(tester);
    await tester.tap(find.text('Advanced'));
    await tester.pump();
    await tester.tap(find.text('Add band'));
    await tester.pump();
    final fields = find.byType(NumField);
    await tester.enterText(find.descendant(of: fields.at(0), matching: find.byType(TextField)), '250');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.enterText(find.descendant(of: fields.at(1), matching: find.byType(TextField)), '-4.5');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.enterText(find.descendant(of: fields.at(2), matching: find.byType(TextField)), '99');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await flush(tester);
    final b = sound.s.eq.bands.single;
    expect([b.type, b.freq, b.gain, b.q], [BandType.peak, 250, -4.5, 20], reason: 'Q is clamped to 20');
    expect(sound.s.eq.on, isTrue);
  });
}
