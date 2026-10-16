import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart' hide Track;
import 'package:path/path.dart' as p;

import '../library/library.dart';
import '../library/models.dart';
import '../library/suggestions.dart';
import 'queue.dart';

/// MediaKit.ensureInitialized, minus a crash at start in debug builds (tests, `flutter run`).
/// media_kit keeps a pointer file per process id in %TEMP% (to free its players on hot restart)
/// and never deletes it. A later process that gets the same id reads the dead process's pointer
/// and crashes with an access violation: the flaky "setUpAll did not complete" test runs. So a
/// file older than this process is dropped first; one written by this process (hot restart) stays.
void initMediaKit({String? libmpv}) {
  if (kDebugMode && Platform.isWindows) dropStalePointerFile();
  MediaKit.ensureInitialized(libmpv: libmpv);
}

/// Deletes media_kit's pointer file for this process id if an earlier process wrote it.
void dropStalePointerFile() {
  final f = File(p.join(Directory.systemTemp.path, 'com.alexmercerind.media_kit.NativeReferenceHolder.$pid'));
  if (f.existsSync() && f.lastModifiedSync().isBefore(processStart())) f.deleteSync();
}

/// When this process started (Windows).
DateTime processStart() {
  final k32 = DynamicLibrary.open('kernel32.dll');
  final self = k32.lookupFunction<IntPtr Function(), int Function()>('GetCurrentProcess')();
  final times = calloc<Uint64>(4); // creation, exit, kernel, user (FILETIME: 100 ns since 1601)
  try {
    k32.lookupFunction<
      Int32 Function(IntPtr, Pointer<Uint64>, Pointer<Uint64>, Pointer<Uint64>, Pointer<Uint64>),
      int Function(int, Pointer<Uint64>, Pointer<Uint64>, Pointer<Uint64>, Pointer<Uint64>)
    >('GetProcessTimes')(self, times, times + 1, times + 2, times + 3);
    return DateTime.utc(1601).add(Duration(microseconds: times.value ~/ 10));
  } finally {
    calloc.free(times);
  }
}

/// Stop after the current song, or at the end of the queue (even with repeat on).
enum StopAfter { none, song, queue }

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

  /// What the device really gets (mpv `audio-out-params`), e.g. s32 / 96000 / 2.
  String outFormat = '';
  int outRate = 0, outChannels = 0;

  /// What the decoder gives (mpv `audio-params`; bits from the file's tags).
  String srcFormat = '';
  int srcRate = 0, srcBits = 0, srcChannels = 0;

  /// e.g. "s32 96000 Hz": the real output format (bit-perfect check).
  String get outputFormat => outFormat.isEmpty ? '' : '$outFormat $outRate Hz';

  /// One-line messages for the user (the player bar shows them as toasts).
  Stream<String> get messages => _messages.stream;
  final _messages = StreamController<String>.broadcast();
  void _say(String m) {
    debugPrint('engine: $m'); // in gleo.log too, for bug reports
    if (!_messages.isClosed) _messages.add(m);
  }

  /// A message from elsewhere (the Sound page's per-device EQ switch).
  void say(String m) => _say(m);

  /// Songs that could not be played this session (their rows are marked), and the last one.
  final cantPlay = <int>{};
  int? lastFailed;

  /// Sleep timer: the volume fades out over the last 10 s, then playback pauses.
  DateTime? sleepAt;
  StopAfter stopAfter = StopAfter.none;
  Timer? _sleep;
  static const sleepFade = Duration(seconds: 10);

  /// Counts seeks, so the OS media overlay can follow them.
  int seeks = 0;

  /// The playing track. It stays known when it leaves the library mid-song.
  Track? get current {
    final id = queue.current?.trackId;
    final t = lib.byId[id];
    if (t != null) return _lastTrack = t;
    return _lastTrack?.id == id ? _lastTrack : null;
  }

  Track? _lastTrack;
  Entry? _mpvNext;
  bool _ended = false, _deviceFailed = false;
  Duration _listened = Duration.zero, _before = Duration.zero, _lastPos = Duration.zero;
  bool _counted = false;
  int _fails = 0;
  Future<void> _ops = Future.value();
  Timer? _saveTimer;

  /// Bumped by every manual load: hand-overs and loads queued before it are stale.
  int _gen = 0;

  /// mpv calls run one at a time, in order.
  Future<void> _serial(Future<void> Function() f) => _ops = _ops.then((_) => f()).catchError((Object e) {
    debugPrint('engine: $e');
  });

  Future<void> init() async {
    player = Player(
      configuration: PlayerConfiguration(title: 'Gleo', logLevel: logLevel),
    );
    await _mpv.setProperty('gapless-audio', 'weak'); // gapless whenever formats match; never resample to force it
    await _mpv.setProperty('prefetch-playlist', 'yes');
    await _mpv.setProperty('audio-display', 'no');
    if (silent) {
      await _mpv.setProperty('ao', 'null');
    } else if (Platform.isAndroid) {
      // AudioTrack first (media_kit picks OpenSL ES, which runs at a fixed rate); AAudio and OpenSL ES as fallbacks.
      await _mpv.setProperty('ao', 'audiotrack,aaudio,opensles');
      await _mpv.setProperty('cache-on-disk', 'no'); // no cache folder there ("Failed to create file cache")
      // Float to AudioTrack: otherwise it gets 16 bits, and 24-bit files would lose theirs.
      await _mpv.setProperty('audiotrack-pcm-float', 'yes');
      await _mpv.setProperty('audio-format', 'float');
    }
    device = lib.setting('audio_device') ?? 'auto';
    exclusive = !Platform.isAndroid && lib.setting('exclusive') == '1'; // WASAPI only
    volume = double.tryParse(lib.setting('volume') ?? '') ?? 100;
    muted = lib.setting('muted') == '1';
    // The saved device is gone (USB DAC unplugged): the system default for this session.
    final there = (await _mpv.getProperty('audio-device-list')).contains(jsonEncode(device));
    await _mpv.setProperty('audio-device', there ? device : 'auto');
    await _mpv.setProperty('audio-exclusive', exclusive ? 'yes' : 'no');
    await player.setVolume(volume);
    await _mpv.setProperty('mute', muted ? 'yes' : 'no');

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
      if (c && _mpvNext == null) _end();
    });
    player.stream.playlist.listen((pl) {
      if (pl.index < 1 || _mpvNext == null) return;
      final g = _gen;
      _serial(() async {
        if (g != _gen) return; // a manual load since made it stale
        await _autoAdvanced();
        await _verify();
      });
    });
    player.stream.error.listen(_onError);
    player.stream.audioDevices.listen((d) {
      devices = d;
      notifyListeners();
    });
    player.stream.audioParams.listen((a) {
      srcFormat = a.format ?? '';
      srcRate = a.sampleRate ?? 0;
      srcChannels = a.channelCount ?? 0;
      srcBits = current?.bitDepth ?? 0;
      notifyListeners();
    });
    await _mpv.observeProperty('audio-out-params', (_) async {
      outFormat = await _mpv.getProperty('audio-out-params/format');
      outRate = int.tryParse(await _mpv.getProperty('audio-out-params/samplerate')) ?? 0;
      outChannels = int.tryParse(await _mpv.getProperty('audio-out-params/channel-count')) ?? 0;
      notifyListeners();
    });
    _saveTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (playing) _savePos();
    });
    _restore();
  }

  /// mpv errors: a lost output device, or a file that can't be opened.
  void _onError(String e) {
    if (e.startsWith('Could not open/initialize audio device')) {
      if (_deviceFailed) return;
      _deviceFailed = true;
      _mpv.setProperty('audio-device', 'auto'); // this session only; the saved choice stays
      _load(play: false);
      _say("Can't open the output device. Switched to the system default — press Play.");
      return;
    }
    if (e.startsWith('Audio filter initialized failed')) {
      setOption('af', ''); // a chain mpv can't build: back to the clean path
      _say("Can't apply the sound settings — playing without them");
      return;
    }
    final open = e.startsWith('Failed to open ');
    if (!open && !e.startsWith('Failed to recognize file format')) return;
    // "Failed to recognize file format" names no file, and its log line can arrive after mpv
    // moved on: it can only mean the current song when mpv stopped (idle).
    final path = (open ? e.substring(15, e.length - 1) : '').replaceFirst(r'\\?\', '');
    final g = _gen;
    _serial(() async {
      if (g != _gen) return; // a newer manual load replaced it
      final idle = await _mpv.getProperty('idle-active') == 'yes';
      bool failed(Entry? x) =>
          x != null && (open ? p.equals(lib.byId[x.trackId]?.path ?? '', path) : idle && identical(x, queue.current));
      final bad = queue.items.where(failed).firstOrNull;
      if ((lastFailed = bad?.trackId) != null) cantPlay.add(bad!.trackId);
      final title = bad == null && !open ? 'a song' : '“${lib.byId[bad?.trackId]?.title ?? p.basenameWithoutExtension(path)}”';
      if (failed(_mpvNext) && !failed(queue.current)) {
        // The preloaded next song can't be opened (found while the current one plays): drop it.
        queue.remove(queue.items.indexOf(_mpvNext!), undoable: false);
        _say("Can't play $title — skipped");
        notifyListeners();
        _save();
        return _syncNext();
      }
      if (!failed(queue.current)) return _say("Can't play $title — skipped"); // mpv already went past it
      if (_mpvNext != null && !idle) {
        return _say("Can't play $title — skipped"); // mpv moves on to the preloaded song by itself
      }
      _leaveTrack(manual: false);
      final n = ++_fails <= queue.items.length ? queue.next() : null;
      if (n == null || identical(n, bad) || (open && failed(n))) {
        _mpvNext = null;
        await player.stop();
        _end();
        _say("Can't play $title");
      } else {
        _say("Can't play $title — skipped");
        _load();
      }
    });
  }

  /// The queue ran out (or stop-after): nothing plays until the user says so.
  void _end() {
    _ended = true;
    playing = false;
    stopAfter = StopAfter.none;
    _leaveTrack(manual: false);
    _savePos();
    notifyListeners();
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
  Future<void> undoRemove() => _edit(queue.undoRemove);
  Future<void> setShuffle(bool on) => _edit(() => queue.setShuffle(on));
  Future<void> cycleRepeat() => _edit(() => queue.repeat = Repeat.values[(queue.repeat.index + 1) % 3]);

  /// Everything but the playing song leaves the queue.
  Future<void> clearQueue() => _edit(queue.clear);
  Future<void> undoClearQueue() => _edit(queue.undoClear);

  /// A new playlist with the queue in play order; returns its id.
  int saveQueueAsPlaylist(String name) => lib.createPlaylist(name, [for (final e in queue.items) e.trackId]);

  Future<void> _edit(void Function() change) {
    final wasEmpty = queue.current == null;
    change();
    notifyListeners();
    if (wasEmpty && queue.current != null) return _load();
    _save();
    return _serial(() async {
      await _syncNext();
      await _verify();
    });
  }

  Future<void> jump(int i) {
    if (i == queue.index || i < 0 || i >= queue.items.length) return Future.value();
    _leaveTrack(manual: true);
    queue.jump(i);
    return _load();
  }

  Future<void> next() {
    final from = current;
    if (from == null) return Future.value();
    if (queue.next() == null) {
      _say('End of the queue');
      return Future.value();
    }
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
      queue.next(); // songs added after the end play next; otherwise the last one again
      return _load();
    }
    return player.playOrPause();
  }

  /// Media keys: Play only plays; Pause and Stop only pause.
  Future<void> play() async {
    if (current == null) return;
    return _ended ? togglePlay() : player.play();
  }

  Future<void> pause() => player.pause();

  Future<void> seek(Duration d) {
    _ended = false;
    _lastPos = d;
    position.value = d;
    seeks++;
    notifyListeners();
    return _serial(() => player.seek(d));
  }

  Future<void> seekBy(Duration d) {
    final to = position.value + d;
    final max = duration > Duration.zero ? duration : to;
    return seek(to < Duration.zero ? Duration.zero : (to > max ? max : to));
  }

  /// Live volume (slider drag); [saveVolume] stores it when the drag ends.
  Future<void> setVolume(double v) {
    volume = v.clamp(0, 100);
    notifyListeners();
    return player.setVolume(volume);
  }

  void saveVolume() => lib.setSetting('volume', '$volume');

  Future<void> toggleMute() {
    muted = !muted;
    lib.setSetting('muted', muted ? '1' : '0');
    notifyListeners();
    return _mpv.setProperty('mute', muted ? 'yes' : 'no');
  }

  /// Pauses after [d], fading the volume out over the last 10 s; null cancels.
  void sleepIn(Duration? d) {
    _sleep?.cancel();
    sleepAt = d == null ? null : DateTime.now().add(d);
    if (d != null) {
      final fade = d < sleepFade ? d : sleepFade;
      _sleep = Timer(d - fade, () => _fadeOut(fade));
    }
    notifyListeners();
  }

  Future<void> _fadeOut(Duration fade) async {
    const steps = 20;
    final at = sleepAt;
    for (var i = 1; i <= steps && sleepAt == at; i++) {
      await player.setVolume(volume * (steps - i) / steps);
      await Future<void>.delayed(fade ~/ steps);
    }
    if (sleepAt == at) {
      await player.pause();
      sleepAt = null;
    }
    await player.setVolume(volume);
    notifyListeners();
  }

  Future<void> setStopAfter(StopAfter s) {
    stopAfter = s;
    notifyListeners();
    return _serial(_syncNext);
  }

  /// An mpv `af` chain in lavfi syntax, e.g. "equalizer=f=100:t=q:w=1:g=3".
  /// Empty = no filters: the clean bit-perfect path. The caller persists it.
  /// A chain mpv can't build is dropped (filters off) with a message.
  /// Labelled `@gleo`, so `af-command gleo ...` can change a running filter without rebuilding the chain.
  Future<void> setAudioFilters(String lavfiChain) {
    final chain = lavfiChain.trim();
    return setOption('af', chain.isEmpty ? '' : '@gleo:lavfi=[$chain]');
  }

  /// Any mpv option or property (e.g. "replaygain"). The caller persists it.
  Future<void> setOption(String name, String value) => _serial(() => _mpv.setProperty(name, value));

  /// Reads an mpv property ('' when it is unavailable).
  Future<String> getOption(String name) => _mpv.getProperty(name);

  /// An mpv command, in order with the other mpv calls (e.g. af-command).
  Future<void> command(List<String> args) => _serial(() => _mpv.command(args));

  Future<void> setDevice(String name) {
    _deviceFailed = false;
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

  Future<void> _load({bool play = true, Duration start = Duration.zero}) {
    final g = ++_gen;
    return _serial(() async {
      if (g == _gen) await _open(play: play, start: start); // else a newer load replaces it (fast Next presses)
    });
  }

  Future<void> _open({bool play = true, Duration start = Duration.zero}) async {
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
  }

  /// Keeps mpv's preloaded next track equal to what the queue says comes next.
  Future<void> _syncNext() async {
    final last = queue.index >= queue.items.length - 1;
    final want = stopAfter == StopAfter.song || (stopAfter == StopAfter.queue && last) ? null : queue.peekNext();
    if (identical(want, _mpvNext) || queue.current == null) return;
    final old = _mpvNext;
    if (old != null) {
      final at = await _playingPos();
      // mpv already moved on to the preloaded track: hand over now. Its playlist event may be
      // long gone (a hand-over that ran while mpv was between files had nothing to do).
      if (at != 0) return at > 0 ? _autoAdvanced() : null;
    }
    final t = lib.byId[want?.trackId];
    _mpvNext = t == null ? null : want;
    // Add before removing, so mpv never meets the end of its list in between.
    if (t != null) await player.add(Media(t.path));
    if (old != null) await player.remove(1);
  }

  Future<int> _playingPos() async => (await _mpvList()).$1;

  /// mpv's playlist in one read, so its two parts belong together: (the entry playing, every file).
  /// Between two files (just after the playing entry was removed, say) no entry plays for a
  /// moment: wait for the next one to start instead of reading that moment as "nothing plays".
  Future<(int, List<String>)> _mpvList() async {
    for (var i = 0; ; i++) {
      final list = (jsonDecode(await _mpv.getProperty('playlist')) as List).cast<Map<String, dynamic>>();
      final at = list.indexWhere((e) => e['playing'] == true);
      if (at >= 0 || i == 100 || await _mpv.getProperty('idle-active') == 'yes') return (at, [for (final e in list) '${e['filename']}']);
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  }

  /// After every queue edit and hand-over: mpv plays the queue's current song as entry 0 and
  /// holds exactly the preload the engine expects. A lost race is put right here.
  Future<void> _verify() async {
    if (current == null || _ended) return;
    var (at, files) = await _mpvList();
    if (at > 0 && _mpvNext != null) {
      await _autoAdvanced();
      (at, files) = await _mpvList();
    }
    final t = current;
    if (at < 0 || t == null || _ended) return; // nothing plays: the end and error paths own that
    bool same(String file, String? path) => path != null && p.equals(file.replaceFirst(r'\\?\', ''), path);
    if (at != 0 || !same(files[0], t.path)) {
      debugPrint("engine: mpv played '${files[at]}', the queue says '${t.path}': reloading");
      return _open(play: playing, start: position.value);
    }
    final next = lib.byId[_mpvNext?.trackId]?.path;
    if (files.length != (next == null ? 1 : 2) || (next != null && !same(files[1], next))) {
      debugPrint('engine: mpv preloaded ${files.skip(1).toList()}, the queue says $next: preloading again');
      for (var i = files.length - 1; i >= 1; i--) {
        await player.remove(i);
      }
      _mpvNext = null;
      await _syncNext();
    }
  }

  /// mpv moved on to the preloaded track by itself: no gap, no reload.
  Future<void> _autoAdvanced() async {
    // Stale or repeated playlist events: act only while mpv really is past the current track.
    if (_mpvNext == null || await _playingPos() < 1) return;
    final expected = _mpvNext;
    _leaveTrack(manual: false);
    final e = queue.next(auto: true);
    _mpvNext = null;
    // The new song's clock from now on, not the old song's end (until mpv's next update).
    _lastPos = Duration.zero;
    position.value = Duration.zero;
    if (e == null) {
      // The song mpv moved on to was removed and nothing follows: the end.
      await player.stop();
      _end();
      return;
    }
    if (identical(e, expected)) {
      await player.remove(0);
      await _syncNext();
    } else {
      await _open(); // the queue changed at the very last moment: load what it says
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
    _fails = 0;
    final t = current;
    if (!_counted && t != null && ListenRules.counts(_before + _listened, duration)) {
      _counted = true;
      lib.recordPlay(t.id, skipped: false);
    }
  }

  void _leaveTrack({required bool manual, Track? track}) {
    final t = track ?? current;
    if (t != null && manual && !_counted && ListenRules.isSkip(_listened, _before)) lib.recordPlay(t.id, skipped: true);
    _listened = _before = Duration.zero;
    _counted = false;
  }

  // ------------------------------------------------------------ remember across restarts

  /// The queue is written when it changes; the position every 5 s while playing.
  void _save() {
    lib.setSetting('queue', jsonEncode(queue.toJson()));
    _savePos();
  }

  void _savePos() => lib.setSetting('queue_pos', '${_ended ? 0 : position.value.inMilliseconds}');

  void _restore() {
    final s = lib.setting('queue');
    if (s == null) return;
    try {
      final j = jsonDecode(s) as Map<String, Object?>;
      final kept = queue.restore(j, lib.byId.containsKey);
      final ms = int.tryParse(lib.setting('queue_pos') ?? '') ?? j['pos'] as int? ?? 0;
      final start = kept ? Duration(milliseconds: ms) : Duration.zero;
      if (queue.current != null) _load(play: false, start: start);
      _before = start; // listening before the restart still counts toward a play
    } catch (e) {
      debugPrint('queue restore: $e');
    }
  }

  Future<void> shutdown() async {
    _saveTimer?.cancel();
    _sleep?.cancel();
    _save();
    await _messages.close();
    await player.dispose();
  }
}
