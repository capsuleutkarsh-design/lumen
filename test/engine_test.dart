// The engine with the real libmpv (see mpv_harness.dart). Audio goes to mpv's
// null output; the device tests use the real device in shared mode at volume 0.
@Tags(['mpv']) // run one file at a time: see dart_test.yaml
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:gleo/audio/engine.dart';
import 'package:path/path.dart' as p;

import 'mpv_harness.dart';

const fakeDevice = 'wasapi/{00000000-0000-0000-0000-000000000000}';

void main() {
  setUpAll(() async {
    if (noMpv == null) await setUpLibrary();
  });
  tearDown(() async {
    if (noMpv == null) await resetAll();
  });

  group('songs that cannot be played', skip: noMpv, () {
    test('W2: a missing song in the middle is skipped with a message; playback goes on', () async {
      final e = await newEngine();
      final said = <String>[];
      e.messages.listen(said.add);
      final t = album('Northern Lights');
      final gone = repoint(t[1], p.join(data, 'gone.flac'));
      await e.playTracks([t[0], gone, t[2]]);
      await playingPast(e);
      expect(e.current!.id, t[0].id, reason: 'the song before it plays to its end');
      await e.seek(e.duration - const Duration(milliseconds: 800));
      await waitFor(() => e.current?.id == t[2].id && e.position.value > const Duration(milliseconds: 500));
      expect(e.current!.id, t[2].id);
      expect(e.playing, isTrue);
      expect(said, ["Can't play “${gone.title}” — skipped"]);
    });

    test('W2: a missing last/only song stops (not "playing" at 0:00 forever) and says so', () async {
      final e = await newEngine();
      final said = <String>[];
      e.messages.listen(said.add);
      final gone = repoint(album('Northern Lights')[3], p.join(data, 'gone2.flac'));
      await e.playTracks([gone]);
      await waitFor(() => said.isNotEmpty);
      await wait(300);
      expect(e.playing, isFalse);
      expect(said, ["Can't play “${gone.title}”"]);
    });

    test('a corrupt first song: the next one plays', () async {
      final e = await newEngine();
      final t = album('Deep Water');
      final bad = repoint(t[0], corruptFile());
      await e.playTracks([bad, t[1]]);
      await waitFor(() => e.current?.id == t[1].id && e.position.value > const Duration(milliseconds: 500));
      expect(e.current!.id, t[1].id);
      expect(e.playing, isTrue);
    });

    test('a corrupt only song stops and says so', () async {
      final e = await newEngine();
      final said = <String>[];
      e.messages.listen(said.add);
      final bad = repoint(album('Deep Water')[0], corruptFile());
      await e.playTracks([bad]);
      await waitFor(() => said.isNotEmpty);
      await wait(300);
      expect(e.playing, isFalse);
      expect(said, ["Can't play “${bad.title}”"]);
    });
  });

  group('the gapless hand-over', skip: noMpv, () {
    Future<Engine> nearEnd(List<int> which) async {
      final e = await newEngine();
      final t = album('Northern Lights');
      await e.playTracks([for (final i in which) t[i]]);
      await playingPast(e, const Duration(milliseconds: 200));
      await e.seek(e.duration - const Duration(milliseconds: 1500));
      return e;
    }

    test('W4a: Next pressed after mpv switched but before the engine caught up moves ONE song', () async {
      final e = await nearEnd([0, 1, 2, 3]);
      final done = Completer<void>();
      final sub = e.player.stream.playlist.listen((pl) {
        if (pl.index == 1 && !done.isCompleted) {
          e.next(); // lands before the engine's queued hand-over runs
          done.complete();
        }
      });
      await done.future.timeout(const Duration(seconds: 5));
      await wait(800);
      await sub.cancel();
      expect(e.queue.index, 1);
    });

    test('W4b: queue edits racing the hand-over: mpv plays what the queue says, and keeps playing', () async {
      final t = album('Northern Lights');
      for (var run = 0; run < 5; run++) {
        final e = await nearEnd([0, 1, 2, 3, 4, 5, 6, 7]);
        final sw = Stopwatch()..start();
        while (sw.elapsedMilliseconds < 2500) {
          e.playNext([t[7 - (sw.elapsedMilliseconds % 3)]]);
          await wait(3);
        }
        await wait(600);
        final p1 = e.position.value;
        await wait(400);
        final pl = e.player.state.playlist;
        final now = pl.index >= 0 && pl.index < pl.medias.length ? p.basename(pl.medias[pl.index].uri) : '-';
        expect(now, p.basename(e.current!.path), reason: 'run $run');
        expect(e.playing && e.position.value > p1, isTrue, reason: 'run $run: still playing');
        await closeEngine(e);
      }
    }, timeout: const Timeout(Duration(minutes: 2)));

    test("after a gapless hand-over the clock is the new song's at once, never the old song's end", () async {
      final t = album('Northern Lights');
      for (var run = 0; run < 3; run++) {
        final e = await nearEnd([0, 1]);
        Duration? at;
        void l() {
          if (e.current?.id == t[1].id) at ??= e.position.value;
        }
        e.addListener(l);
        await waitFor(() => at != null, timeout: const Duration(seconds: 5));
        e.removeListener(l);
        expect(at, lessThan(const Duration(seconds: 1)), reason: 'run $run');
        await closeEngine(e);
      }
    });

    test('W4c: removing the last upcoming song during the hand-over ends playback (no replay of the old song)', () async {
      final e = await nearEnd([0, 1]);
      final done = Completer<void>();
      final sub = e.player.stream.playlist.listen((pl) {
        if (pl.index == 1 && !done.isCompleted) {
          e.removeFromQueue(1);
          done.complete();
        }
      });
      await done.future.timeout(const Duration(seconds: 5));
      await wait(1000);
      await sub.cancel();
      expect(e.current!.id, album('Northern Lights')[0].id);
      expect(e.playing, isFalse);
    });

    test('P3: six fast Next presses open one file, not six', () async {
      final e = await newEngine();
      final t = album('Deep Water');
      await e.playTracks(t);
      await playingPast(e);
      var opens = 0;
      final sub = e.player.stream.playlist.listen((pl) {
        if (pl.medias.length == 1) opens++; // each player.open() starts a one-file playlist
      });
      for (var i = 0; i < 6; i++) {
        e.next();
      }
      await playingPast(e);
      await wait(300);
      await sub.cancel();
      expect(e.current!.id, t[6].id);
      expect(opens, 1, reason: 'without the generation check the last song opens six times');
    });

    test('stop after this song: it ends there; Play goes on with the next one', () async {
      final e = await newEngine();
      final t = album('Northern Lights');
      await e.playTracks([t[0], t[1]]);
      await playingPast(e);
      await e.setStopAfter(StopAfter.song);
      await e.seek(e.duration - const Duration(seconds: 1));
      await wait(300);
      await waitFor(() => !e.playing, timeout: const Duration(seconds: 5));
      await wait(500);
      expect(e.current!.id, t[0].id);
      expect(e.playing, isFalse);
      expect(e.stopAfter, StopAfter.none, reason: 'one-shot');
      await e.togglePlay();
      await playingPast(e);
      expect(e.current!.id, t[1].id);
    });
  });

  group('plays and skips', skip: noMpv, () {
    List<int> skips() => [for (final (id, s) in plays()) if (s) id];

    test('W5: the restored song is not a skip; quick Next presses are not skips; 2 s heard is', () async {
      final first = await newEngine();
      final h = album('Hi-Res Sketches');
      await first.playTracks([h[0]]);
      await playingPast(first);
      await first.seek(const Duration(seconds: 8));
      await wait(300);
      await first.pause();
      await closeEngine(first); // saves the queue, like closing the app
      final e = await newEngine(); // restores h[0] paused at 8 s
      await waitFor(() => e.current != null);
      await wait(300);
      lib.db.execute('DELETE FROM plays');
      await e.playTracks([h[1]]);
      await wait(300);
      expect(skips(), isEmpty, reason: 'the restored song was never played this session');
      final t = album('Northern Lights');
      await e.playTracks(t);
      await e.next();
      await e.next();
      await playingPast(e, const Duration(milliseconds: 2200));
      expect(skips(), isEmpty, reason: '0 s heard is not a skip');
      await e.next();
      expect(skips(), [t[2].id]);
    });

    test('W6: listening before a restart counts; a replay after the end counts again', () async {
      final first = await newEngine();
      final t = album('Northern Lights');
      await first.playTracks([t[0]]);
      await playingPast(first);
      await first.seek(const Duration(seconds: 20));
      await wait(300);
      await first.pause();
      await closeEngine(first);
      final e = await newEngine(); // restores t[0] at ~20 s
      await waitFor(() => e.current != null);
      await wait(300);
      await e.togglePlay();
      // 20 s before + 4 s now passes half of the 47 s song.
      await waitFor(() => plays().isNotEmpty, timeout: const Duration(seconds: 8));
      expect(plays(), [(t[0].id, false)]);
      await e.seek(e.duration - const Duration(seconds: 1));
      await waitFor(() => !e.playing, timeout: const Duration(seconds: 5));
      await e.togglePlay(); // the replay: a new listen
      await playingPast(e, const Duration(milliseconds: 2200));
      await e.playTracks([t[1]]);
      expect(plays(), [(t[0].id, false), (t[0].id, true)]);
    });
  });

  group('output device and format', skip: noMpv, () {
    test('W1: a saved device that is gone falls back to the system default at start', () async {
      lib.setSetting('audio_device', fakeDevice);
      final e = await newEngine(silent: false); // real device, shared mode, volume 0
      await e.playTracks(album('Hi-Res Sketches'));
      await playingPast(e, const Duration(seconds: 1));
      expect(await mpvOf(e).getProperty('audio-device'), 'auto');
      expect(e.queue.index, 0, reason: 'no racing through the queue');
      expect(e.device, fakeDevice, reason: 'the saved choice stays for when it comes back');
    });

    test('W1: the device failing mid-song pauses, switches to the default and says so', () async {
      final e = await newEngine(silent: false);
      final said = <String>[];
      e.messages.listen(said.add);
      await e.playTracks(album('Hi-Res Sketches'));
      await playingPast(e);
      await e.setDevice(fakeDevice);
      await waitFor(() => said.isNotEmpty);
      await wait(500);
      expect(said.single, startsWith("Can't open the output device"));
      expect(e.playing, isFalse);
      expect(await mpvOf(e).getProperty('audio-device'), 'auto');
      await e.togglePlay();
      await playingPast(e);
      expect(e.playing, isTrue);
    });

    test('W7: the output format is what the device gets (audio-out-params), not the decoder format', () async {
      final e = await newEngine(silent: false);
      final t = lib.tracks.firstWhere((t) => t.sampleRate == 192000);
      await e.playTracks([t]);
      await playingPast(e);
      await waitFor(() => e.outRate > 0);
      final mpv = mpvOf(e);
      expect(e.outFormat, await mpv.getProperty('audio-out-params/format'));
      expect(e.outRate, int.parse(await mpv.getProperty('audio-out-params/samplerate')));
      expect(e.outChannels, int.parse(await mpv.getProperty('audio-out-params/channel-count')));
      expect((e.srcRate, e.srcBits), (192000, t.bitDepth));
    });
  });

  group('small upgrades', skip: noMpv, () {
    test('sleep timer fades out, pauses, and puts the volume back; mute and volume are remembered', () async {
      final e = await newEngine();
      await e.setVolume(50);
      expect(lib.setting('volume'), '0', reason: 'P2: dragging does not write');
      e.saveVolume();
      expect(lib.setting('volume'), '50.0');
      await e.playTracks(album('Northern Lights'));
      await playingPast(e);
      e.sleepIn(const Duration(seconds: 2));
      await wait(1200);
      expect(e.player.state.volume, lessThan(50));
      expect(e.playing, isTrue);
      await waitFor(() => e.sleepAt == null, timeout: const Duration(seconds: 5));
      await wait(300);
      expect(e.playing, isFalse);
      expect(e.player.state.volume, 50);
      await e.toggleMute();
      await closeEngine(e);
      final again = await newEngine();
      expect(again.muted, isTrue);
      expect(await mpvOf(again).getProperty('mute'), 'yes');
    });

    test('out of sight: mpv stops sending positions, a poll keeps the clock while playing, none while paused', () async {
      final e = await newEngine();
      await e.playTracks(album('Northern Lights'));
      await playingPast(e);
      var events = 0;
      final sub = e.player.stream.position.listen((_) => events++);
      await wait(1000);
      expect(events, greaterThan(5), reason: 'in view: mpv sends many a second');
      e.setHidden(true);
      await wait(200);
      events = 0;
      final from = e.position.value;
      await wait(1500);
      expect(events, lessThanOrEqualTo(1), reason: 'hidden: none (one may be on its way)');
      expect(e.position.value - from, greaterThan(const Duration(milliseconds: 800)), reason: 'the poll moves the clock');
      await e.pause();
      await wait(700);
      final paused = e.position.value;
      await wait(1100);
      expect(e.position.value, paused);
      e.setHidden(false);
      await e.play();
      await wait(1000);
      expect(events, greaterThan(5), reason: 'back in view: updates again');
      await sub.cancel();
      await closeEngine(e);
    });

    test('audio filters: a chain applies, empty clears, a broken one is dropped with a message', () async {
      final e = await newEngine();
      final said = <String>[];
      e.messages.listen(said.add);
      final mpv = mpvOf(e);
      await e.playTracks(album('Northern Lights'));
      await playingPast(e);
      await e.setAudioFilters('equalizer=f=100:t=q:w=1:g=3');
      expect(await mpv.getProperty('af'), contains('equalizer'));
      await e.setAudioFilters('');
      expect(await mpv.getProperty('af'), '');
      await e.setAudioFilters('no_such_filter=x');
      await waitFor(() => said.isNotEmpty);
      await wait(300);
      expect(await mpv.getProperty('af'), '');
      expect(e.playing, isTrue);
      await e.setOption('replaygain', 'track');
      expect(await mpv.getProperty('replaygain'), 'track');
    });

    test('queue: save as playlist, clear; the song keeps showing when it leaves the library; seek and end details', () async {
      final e = await newEngine();
      final t = album('Northern Lights');
      await e.playTracks(t, 2);
      await playingPast(e);
      final id = e.saveQueueAsPlaylist('From the queue');
      expect(lib.playlists.firstWhere((x) => x.id == id).trackIds, [for (final x in t) x.id]);
      await e.clearQueue();
      expect([for (final x in e.queue.items) x.trackId], [t[2].id]);
      expect(e.player.state.playlist.medias.length, 1, reason: 'nothing preloaded any more');
      final playing = e.current!;
      lib.byId.remove(playing.id);
      expect(e.current, same(playing), reason: 'the player bar keeps its buttons');
      e.duration = Duration.zero; // length not known yet
      final before = e.position.value;
      await e.seekBy(const Duration(seconds: 5));
      expect(e.position.value, before + const Duration(seconds: 5));
      lib.load();
      await e.seek(playing.duration - const Duration(milliseconds: 500));
      await waitFor(() => !e.playing, timeout: const Duration(seconds: 5));
      await wait(200);
      expect(lib.setting('queue_pos'), '0', reason: 'a queue saved at the end restores at the start');
    });
  });
}
