import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart' hide Track;

import '../library/library.dart';
import '../library/models.dart';
import '../library/suggestions.dart';
import 'queue.dart';

/// Plays the [PlayQueue] through libmpv. mpv's own playlist only ever holds
/// [current, next]: the next track is preloaded so mpv can join them gaplessly,
/// while every decision about order stays in [PlayQueue].
class Engine extends ChangeNotifier {
  Engine(this.lib, {this.silent = false, this.logLevel = MPVLogLevel.error});
  final Library lib;

  /// No audio output (tests): mpv's null output still runs in real time.
  final bool silent;

  /// mpv log detail (tests read the log to prove gapless joins).
  final MPVLogLevel logLevel;

  late final Player player;
  NativePlayer get _mpv => player.platform as NativePlayer;
  final queue = PlayQueue();
  final position = ValueNotifier(Duration.zero);
  Duration duration = Duration.zero;
  bool playing = false, muted = false, exclusive = false;
  double volume = 100;
  List<AudioDevice> devices = [];
  String device = 'auto';

  /// Real output format, e.g. "s32 96000 Hz" (shows bit-perfect output).
  String outputFormat = '';

  Track? get current => lib.byId[queue.current?.trackId];

  Entry? _mpvNext;
  bool _ended = false;
  Duration _listened = Duration.zero, _lastPos = Duration.zero;
  bool _counted = false;
  Future<void> _ops = Future.value();
  Timer? _saveTimer;

  /// mpv calls run one at a time, in order.
  Future<void> _serial(Future<void> Function() f) => _ops = _ops.then((_) => f()).catchError((Object e) {
    debugPrint('engine: $e');
  });

  Future<void> init() async {
    player = Player(
      configuration: PlayerConfiguration(title: 'Music Player', logLevel: logLevel),
    );
    await _mpv.setProperty('gapless-audio', 'weak'); // gapless whenever formats match; never resample to force it
    await _mpv.setProperty('prefetch-playlist', 'yes');
    await _mpv.setProperty('audio-display', 'no');
    if (silent) await _mpv.setProperty('ao', 'null');
    device = lib.setting('audio_device') ?? 'auto';
    exclusive = lib.setting('exclusive') == '1';
    volume = double.tryParse(lib.setting('volume') ?? '') ?? 100;
    await _mpv.setProperty('audio-device', device);
    await _mpv.setProperty('audio-exclusive', exclusive ? 'yes' : 'no');
    await player.setVolume(volume);

    player.stream.position.listen(_onPosition);
    player.stream.duration.listen((d) {
      if (d <= Duration.zero) return;
      duration = d;
      final t = current;
      if (t != null && t.durationMs == 0) lib.fixDuration(t.id, d.inMilliseconds);
      notifyListeners();
    });
    player.stream.playing.listen((p) {
      playing = p;
      notifyListeners();
    });
    player.stream.completed.listen((c) {
      if (c && _mpvNext == null) {
        _ended = true;
        playing = false;
        notifyListeners();
      }
    });
    player.stream.playlist.listen((pl) {
      if (pl.index == 1 && _mpvNext != null) _serial(_autoAdvanced);
    });
    player.stream.audioDevices.listen((d) {
      devices = d;
      notifyListeners();
    });
    player.stream.audioParams.listen((a) {
      outputFormat = a.format == null ? '' : '${a.format} ${a.sampleRate} Hz';
      notifyListeners();
    });
    _saveTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (playing) _save();
    });
    _restore();
  }

  // ------------------------------------------------------------ queue actions

  Future<void> playTracks(List<Track> list, [int start = 0]) {
    _leaveTrack(manual: true);
    queue.playNow([for (final t in list) t.id], start);
    return _load();
  }

  Future<void> playNext(List<Track> list) => _edit(() => queue.playNext([for (final t in list) t.id]));
  Future<void> addToQueue(List<Track> list) => _edit(() => queue.addToQueue([for (final t in list) t.id]));
  Future<void> moveInQueue(int from, int to) => _edit(() => queue.move(from, to));
  Future<void> removeFromQueue(int i) => _edit(() => queue.remove(i));
  Future<void> setShuffle(bool on) => _edit(() => queue.setShuffle(on));
  Future<void> cycleRepeat() => _edit(() => queue.repeat = Repeat.values[(queue.repeat.index + 1) % 3]);

  Future<void> _edit(void Function() change) {
    final wasEmpty = queue.current == null;
    change();
    notifyListeners();
    if (wasEmpty && queue.current != null) return _load();
    _save();
    return _serial(_syncNext);
  }

  Future<void> jump(int i) {
    if (i == queue.index) return Future.value();
    _leaveTrack(manual: true);
    queue.jump(i);
    return _load();
  }

  Future<void> next() {
    final from = current;
    if (queue.next() == null) return Future.value();
    _leaveTrack(manual: true, track: from);
    return _load();
  }

  /// More than 3 s in: back to the start. Otherwise the previously played track.
  Future<void> previous() {
    if (position.value > PlayQueue.restartAfter) return seek(Duration.zero);
    final from = current;
    if (queue.previous() == null) return seek(Duration.zero);
    _leaveTrack(manual: true, track: from);
    return _load();
  }

  // ------------------------------------------------------------ transport

  Future<void> togglePlay() async {
    if (current == null) return;
    if (_ended) {
      _ended = false;
      await seek(Duration.zero);
      return player.play();
    }
    return player.playOrPause();
  }

  Future<void> seek(Duration d) {
    _ended = false;
    _lastPos = d;
    position.value = d;
    return _serial(() => player.seek(d));
  }

  Future<void> seekBy(Duration d) {
    final to = position.value + d;
    return seek(to < Duration.zero ? Duration.zero : (to > duration ? duration : to));
  }

  Future<void> setVolume(double v) {
    volume = v.clamp(0, 100);
    lib.setSetting('volume', '$volume');
    notifyListeners();
    return player.setVolume(volume);
  }

  Future<void> toggleMute() {
    muted = !muted;
    notifyListeners();
    return _mpv.setProperty('mute', muted ? 'yes' : 'no');
  }

  Future<void> setDevice(String name) {
    device = name;
    lib.setSetting('audio_device', name);
    notifyListeners();
    return _mpv.setProperty('audio-device', name);
  }

  /// WASAPI exclusive mode: mpv owns the device and sends samples unchanged
  /// (keep volume at 100 % for bit-perfect output).
  Future<void> setExclusive(bool on) async {
    exclusive = on;
    lib.setSetting('exclusive', on ? '1' : '0');
    notifyListeners();
    await _mpv.setProperty('audio-exclusive', on ? 'yes' : 'no');
    await _mpv.command(['ao-reload']);
  }

  // ------------------------------------------------------------ mpv sync

  Future<void> _load({bool play = true, Duration start = Duration.zero}) => _serial(() async {
    _mpvNext = null;
    _ended = false;
    _lastPos = start;
    position.value = start;
    final t = current;
    notifyListeners();
    if (t == null) {
      await player.stop();
      return;
    }
    duration = t.duration;
    await player.open(Media(t.path, start: start > Duration.zero ? start : null), play: play);
    await _syncNext();
    _save();
  });

  /// Keeps mpv's preloaded next track equal to what the queue says comes next.
  Future<void> _syncNext() async {
    final want = queue.peekNext();
    if (identical(want, _mpvNext) || queue.current == null) return;
    if (_mpvNext != null) await player.remove(1);
    _mpvNext = want;
    final t = lib.byId[want?.trackId];
    if (t != null) await player.add(Media(t.path));
  }

  /// mpv moved on to the preloaded track by itself: no gap, no reload.
  Future<void> _autoAdvanced() async {
    final expected = _mpvNext;
    _leaveTrack(manual: false);
    final e = queue.next(auto: true);
    _mpvNext = null;
    if (!identical(e, expected)) {
      // The queue changed at the very last moment: just load what it says.
      final t = current;
      if (t != null) await player.open(Media(t.path));
      await _syncNext();
    } else {
      await player.remove(0);
      await _syncNext();
    }
    duration = current?.duration ?? Duration.zero;
    _save();
    notifyListeners();
  }

  // ------------------------------------------------------------ plays and skips

  void _onPosition(Duration pos) {
    final delta = pos - _lastPos;
    _lastPos = pos;
    position.value = pos;
    if (!playing || delta <= Duration.zero || delta > const Duration(milliseconds: 1500)) return; // seeks don't count
    _listened += delta;
    final t = current;
    if (!_counted && t != null && ListenRules.counts(_listened, duration)) {
      _counted = true;
      lib.recordPlay(t.id, skipped: false);
    }
  }

  void _leaveTrack({required bool manual, Track? track}) {
    final t = track ?? current;
    if (t != null && manual && !_counted && ListenRules.isSkip(_listened)) lib.recordPlay(t.id, skipped: true);
    _listened = Duration.zero;
    _counted = false;
  }

  // ------------------------------------------------------------ remember across restarts

  void _save() => lib.setSetting('queue', jsonEncode({...queue.toJson(), 'pos': position.value.inMilliseconds}));

  void _restore() {
    final s = lib.setting('queue');
    if (s == null) return;
    try {
      final j = jsonDecode(s) as Map<String, Object?>;
      queue.restore(j, lib.byId.containsKey);
      if (queue.current != null) _load(play: false, start: Duration(milliseconds: j['pos'] as int? ?? 0));
    } catch (e) {
      debugPrint('queue restore: $e');
    }
  }

  Future<void> shutdown() async {
    _saveTimer?.cancel();
    _save();
    await player.dispose();
  }
}
