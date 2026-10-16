// Android's first start (A-05, A-23), the lock-screen view and its gating: headless, with the
// "gleo/android" channel answered by the test.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gleo/library/library.dart';
import 'package:gleo/platform/android.dart';
import 'package:gleo/ui/app.dart';
import 'package:gleo/ui/lock_view.dart';
import 'package:gleo/ui/phone.dart';
import 'package:gleo/ui/player_bar.dart';

import 'ui_test.dart' show FakeEngine, addTracks, pumpOne, tmp;

void main() {
  final calls = <(String, Object?)>[];
  var askAnswer = 'denied';
  var hasMusic = false;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('gleo_android_ui');
    lib = Library(tmp.path)..load();
    lib.setSetting('folders', '[]'); // a folder chosen: no scan starts in the test
    calls.clear();
    musicAccess.value = false;
    musicBlocked.value = false;
    photosStep.value = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('gleo/android'), (
      call,
    ) async {
      calls.add((call.method, call.arguments));
      return switch (call.method) {
        'askMusic' => askAnswer,
        'hasMusic' => hasMusic,
        _ => null,
      };
    });
  });
  tearDown(() {
    lib.db.close();
    tmp.deleteSync(recursive: true);
  });

  Future<void> tap(WidgetTester tester, String key) async {
    await tester.tap(find.byKey(ValueKey(key)));
    await tester.pump();
  }

  testWidgets('A-05: after "Don\'t allow" twice the button opens Settings; coming back with access carries on', (tester) async {
    await pumpOne(tester, const MusicAccess(), size: const Size(412, 900));
    askAnswer = 'denied'; // the first refusal: Android will ask again
    await tap(tester, 'allowMusic');
    expect(find.byKey(const ValueKey('allowMusic')), findsOneWidget);
    askAnswer = 'blocked'; // the second: only Settings can give it now
    await tap(tester, 'allowMusic');
    expect(find.text('Open settings'), findsOneWidget);
    expect(find.text('Gleo needs Music and audio access. Turn it on in Settings → Permissions.'), findsOneWidget);
    await tap(tester, 'openSettings');
    expect(calls.last.$1, 'openSettings');

    hasMusic = true; // turned on in Settings, then back in Gleo (main.dart re-checks on resume)
    await recheckMusic(lib);
    expect((musicAccess.value, musicBlocked.value), (true, false));
    expect(MusicAccess.permissionName(30), 'Files and media'); // the owner's Android 11
  });

  testWidgets('A-23: Android 13+ asks for music first, then offers photos, which can be skipped', (tester) async {
    await pumpOne(tester, const MusicAccess(), size: const Size(412, 900));
    askAnswer = 'photos';
    await tap(tester, 'allowMusic');
    expect([for (final c in calls) c.$1], ['askMusic']); // no photos or notifications in the same go
    expect((musicAccess.value, photosStep.value), (true, true));
    expect(find.text('Album covers'), findsOneWidget);
    await tap(tester, 'skipPhotos');
    expect(photosStep.value, isFalse);

    photosStep.value = true;
    await tester.pump();
    await tap(tester, 'allowPhotos');
    expect(calls.last.$1, 'askPhotos');
    expect(photosStep.value, isFalse);
  });

  testWidgets('the lock-screen view: on by default, allowed only while music plays, and Open Gleo unlocks', (tester) async {
    engine = FakeEngine(lib);
    addTracks();
    engine.queue.playNow([lib.tracks.first.id]);
    expect(lockViewOn(lib), isTrue);
    bool? allowed() => calls.lastWhere((c) => c.$1 == 'lockAllowed').$2 as bool?;
    engine.playing = true;
    sendLockAllowed(engine);
    expect(allowed(), isTrue);
    lib.setSetting('lockView', '0'); // Settings → Show on lock screen: off
    sendLockAllowed(engine);
    expect(allowed(), isFalse);
    lib.setSetting('lockView', '1');
    engine.playing = false;
    sendLockAllowed(engine);
    expect(allowed(), isFalse);

    await pumpOne(tester, const LockView(), size: const Size(412, 915));
    expect(tester.takeException(), isNull);
    expect(find.text(engine.current!.title), findsOneWidget);
    expect(find.byType(SeekBar), findsOneWidget);
    expect(find.byType(Transport), findsOneWidget);
    await tap(tester, 'unlock');
    expect(calls.last.$1, 'unlock');

    // In the app: over the lock screen only the lock-screen view is there, also for TalkBack; unlocked, the app is back.
    final semantics = tester.ensureSemantics();
    musicAccess.value = true;
    lockView.value = false;
    await pumpOne(tester, const Shell());
    expect(find.bySemanticsLabel(RegExp('Open Gleo')), findsNothing);
    expect(find.bySemanticsLabel(RegExp('Settings')), findsWidgets);
    lockView.value = true;
    await tester.pump(const Duration(seconds: 1));
    expect(find.bySemanticsLabel(RegExp('Open Gleo')), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('Settings')), findsNothing);
    lockView.value = false;
    await tester.pump(const Duration(seconds: 1));
    expect(find.bySemanticsLabel(RegExp('Open Gleo')), findsNothing);
    expect(find.bySemanticsLabel(RegExp('Settings')), findsWidgets);
    semantics.dispose();
  });
}
