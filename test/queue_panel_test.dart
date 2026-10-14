// W10: the queue panel acts on the song the user clicked, even when the queue
// moved under it since it was drawn.
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_player/audio/engine.dart';
import 'package:music_player/library/library.dart';
import 'package:music_player/library/models.dart';
import 'package:music_player/ui/app.dart';
import 'package:music_player/ui/queue_panel.dart';
import 'package:music_player/ui/theme.dart';

/// Records what the panel asks for (no mpv needed).
class _Engine extends Engine {
  _Engine(super.lib);
  final calls = <String>[];
  @override
  Future<void> jump(int i) async => calls.add('jump $i');
  @override
  Future<void> removeFromQueue(int i) async => calls.add('remove $i');
  @override
  Future<void> moveInQueue(int from, int to) async => calls.add('move $from $to');
}

void main() {
  testWidgets('remove and double-click use the position at click time', (tester) async {
    lib = Library(Directory.systemTemp.createTempSync('lumen_panel_').path)..load();
    lib.byId = {for (var i = 1; i <= 9; i++) i: Track(id: i, title: 'Song $i')};
    final e = _Engine(lib);
    engine = e;
    e.queue.playNow([1, 2, 3, 4, 5], 0);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(),
        home: const Scaffold(body: SizedBox(width: 340, height: 700, child: QueuePanel())),
      ),
    );
    e.queue.playNext([9]); // the queue changes; the panel has not redrawn yet
    await tester.tap(find.byTooltip('Remove from queue').at(2)); // "Song 4" as drawn
    await tester.pump(const Duration(milliseconds: 500)); // the row's double-click waits first
    expect(e.calls.last, 'remove 4', reason: 'Song 4 is now at 4 (it was drawn at 3)');
    await tester.pump(const Duration(seconds: 5)); // the toast goes away
    e.queue.playNext([8]);
    final song5 = find.text('Song 5');
    await tester.tap(song5);
    await tester.pump(kDoubleTapMinTime);
    await tester.tap(song5);
    await tester.pump(const Duration(milliseconds: 500));
    expect(e.calls.last, 'jump 6');
  });
}
