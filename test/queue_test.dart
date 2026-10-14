import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:music_player/audio/queue.dart';

List<int> ids(Iterable<Entry> es) => [for (final e in es) e.trackId];

void main() {
  final album = List.generate(10, (i) => i + 1); // track ids 1..10

  test('play now starts at the chosen track and plays the list in order', () {
    final q = PlayQueue()..playNow(album, 3);
    expect(q.current!.trackId, 4);
    expect([q.next()!.trackId, q.next()!.trackId], [5, 6]);
  });

  test('play next goes right after the current track; add to queue goes last', () {
    final q = PlayQueue()..playNow(album, 0);
    q.addToQueue([99]);
    q.playNext([50, 51]);
    expect(ids(q.items).take(4), [1, 50, 51, 2]);
    expect(q.items.last.trackId, 99);
    expect(q.next()!.trackId, 50);
  });

  test('previous goes back through history, then steps back in the list', () {
    final q = PlayQueue()..playNow(album, 4); // track 5
    q.jump(8); // track 9
    expect(q.previous()!.trackId, 5); // the track we actually came from
    expect(q.previous()!.trackId, 4); // no more history: previous in list
    expect(q.next()!.trackId, 5);
    expect(PlayQueue.restartAfter, const Duration(seconds: 3));
  });

  test('shuffle never repeats a track until all have played, also across cycles', () {
    final q = PlayQueue(random: Random(7))..playNow(List.generate(20, (i) => i), 5);
    q.setShuffle(true);
    q.repeat = Repeat.all;
    expect(q.current!.trackId, 5); // the playing track stays
    final cycle1 = [q.current!.trackId];
    for (var i = 0; i < 19; i++) {
      cycle1.add(q.next(auto: true)!.trackId);
    }
    expect(cycle1.toSet().length, 20);
    final peek = q.peekNext()!;
    final first2 = q.next(auto: true)!;
    expect(first2, peek, reason: 'gapless preload must match what actually plays');
    expect(first2.trackId, isNot(cycle1.last));
    final cycle2 = [first2.trackId];
    for (var i = 0; i < 19; i++) {
      cycle2.add(q.next(auto: true)!.trackId);
    }
    expect(cycle2.toSet().length, 20);
  });

  test('turning shuffle off returns to the original order at the current track', () {
    final q = PlayQueue(random: Random(1))..playNow(album, 0);
    q.setShuffle(true);
    q.next();
    q.next();
    final playing = q.current!.trackId;
    q.setShuffle(false);
    expect(ids(q.items), album);
    expect(q.current!.trackId, playing);
    expect(q.next()?.trackId, playing == 10 ? null : playing + 1);
  });

  test('repeat off, all and one', () {
    final q = PlayQueue()..playNow([1, 2], 1);
    expect(q.next(auto: true), isNull); // off: stops at the end
    expect(q.peekNext(), isNull);
    q.repeat = Repeat.all;
    expect(q.peekNext()!.trackId, 1);
    expect(q.next(auto: true)!.trackId, 1);
    q.repeat = Repeat.one;
    expect(q.peekNext()!.trackId, 1);
    expect(q.next(auto: true)!.trackId, 1); // track ended: same track again
    expect(q.next()!.trackId, 2); // pressing Next still moves on
  });

  test('drag to reorder and remove keep the current track', () {
    final q = PlayQueue()..playNow(album, 2); // track 3 playing
    q.move(9, 3); // drag track 10 to play next
    expect(ids(q.items).take(5), [1, 2, 3, 10, 4]);
    expect(q.current!.trackId, 3);
    q.move(2, 0); // drag the playing track to the top
    expect(q.index, 0);
    expect(q.current!.trackId, 3);
    q.remove(1);
    expect(ids(q.items).take(3), [3, 2, 10]);
    expect(q.current!.trackId, 3);
    q.remove(0); // the current track cannot be removed
    expect(q.current!.trackId, 3);
  });

  test('saves and restores, dropping tracks that left the library', () {
    final q = PlayQueue()..playNow(album, 4);
    final r = PlayQueue()..restore(q.toJson(), (id) => id != 2);
    expect(ids(r.items), [1, 3, 4, 5, 6, 7, 8, 9, 10]);
    expect(r.current!.trackId, 5);
  });

  // ---- 0.2.0 review fixes

  test('W3: playing something new drops the cached repeat-all cycle (unshuffled)', () {
    final q = PlayQueue()..repeat = Repeat.all;
    q.playNow([1, 2, 3], 2);
    q.peekNext(); // the engine preloads: caches the next cycle
    q.playNow([10, 11, 12], 2);
    expect(q.peekNext()!.trackId, 10, reason: 'the preload wraps to the NEW queue');
  });

  test('W3: ... and with shuffle the old list never comes back', () {
    final q = PlayQueue(random: Random(3))
      ..shuffle = true
      ..repeat = Repeat.all;
    q.playNow([1, 2, 3], 0);
    q.next();
    q.next();
    q.peekNext();
    q.playNow([10], 0);
    expect(q.peekNext()!.trackId, 10);
    expect(q.next(auto: true)!.trackId, 10);
    expect(ids(q.items), [10]);
  });

  test('W9: restore when the current track left the library: the song after it, not song 1', () {
    final q = PlayQueue()..playNow([1, 2, 3, 4, 5], 3);
    final r = PlayQueue();
    expect(r.restore(q.toJson(), (id) => id != 4), isFalse, reason: 'tells the engine to start at 0:00');
    expect(r.current!.trackId, 5);
    expect(PlayQueue().restore(q.toJson(), (id) => id != 1), isTrue);
  });

  test('P1: saving a 20 000-song shuffled queue is fast (no indexOf per entry)', () {
    final q = PlayQueue(random: Random(1))..playNow(List.generate(20000, (i) => i));
    q.setShuffle(true);
    final sw = Stopwatch()..start();
    final j = q.toJson();
    expect(sw.elapsedMilliseconds, lessThan(50));
    final r = PlayQueue()..restore(j, (_) => true);
    expect(ids(r.original), List.generate(20000, (i) => i));
  });

  test('clear keeps only the playing song; undo puts the last removed song back in place', () {
    final q = PlayQueue()..playNow([1, 2, 3, 4, 5], 2);
    q.remove(0); // before the current one
    expect(q.current!.trackId, 3);
    q.undoRemove();
    expect(ids(q.items), [1, 2, 3, 4, 5]);
    expect(q.current!.trackId, 3);
    q.remove(4);
    q.undoRemove();
    expect(ids(q.items), [1, 2, 3, 4, 5]);
    expect(q.canUndo, isFalse);
    q.clear();
    expect(ids(q.items), [3]);
    expect(q.current!.trackId, 3);
    expect(q.peekNext(), isNull);
  });
}
