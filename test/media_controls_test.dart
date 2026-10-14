// Media keys and the Windows media overlay, against the real engine (see mpv_harness.dart).
@Tags(['mpv']) // run one file at a time: see dart_test.yaml
library;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_player/platform/media_controls.dart';

import 'mpv_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  setUpAll(() async {
    if (noMpv == null) await setUpLibrary();
  });
  tearDown(() async {
    if (noMpv == null) await resetAll();
  });

  test('W8: Play only plays, Pause and Stop only pause; overlay seek works and the timeline follows', () async {
    final e = await newEngine();
    final sent = <Map<Object?, Object?>>[];
    messenger.setMockMethodCallHandler(MediaControls.channel, (c) async {
      if (c.method == 'update') sent.add(c.arguments as Map<Object?, Object?>);
      return null;
    });
    MediaControls(e);
    Future<void> os(String method, Object arg) async {
      await messenger.handlePlatformMessage(
        MediaControls.channel.name,
        MediaControls.channel.codec.encodeMethodCall(MethodCall(method, arg)),
        (_) {},
      );
      await wait(300);
    }

    await e.playTracks(album('Northern Lights'));
    await playingPast(e);
    await os('button', 'play');
    expect(e.playing, isTrue, reason: 'Play while playing keeps playing');
    await os('button', 'pause');
    expect(e.playing, isFalse);
    await os('button', 'pause');
    expect(e.playing, isFalse, reason: 'Pause while paused stays paused');
    await os('button', 'play');
    expect(e.playing, isTrue);
    await os('button', 'stop');
    expect(e.playing, isFalse);
    sent.clear();
    await os('seek', 20000);
    expect(e.position.value.inSeconds, inInclusiveRange(19, 21));
    expect(sent.map((m) => m['positionMs'] as int), contains(greaterThanOrEqualTo(19000)), reason: 'the overlay hears about seeks');
    messenger.setMockMethodCallHandler(MediaControls.channel, null);
  }, skip: noMpv);
}
