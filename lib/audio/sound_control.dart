import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../library/library.dart';
import 'engine.dart';
import 'sound.dart';

/// Applies the [SoundSettings] to the engine: live (slider drags become filter
/// commands, so nothing is rebuilt), debounced, saved in the settings table
/// (key `sound`) and applied again on start.
class Sound extends ChangeNotifier {
  Sound(this.lib, this.engine);
  final Library lib;
  final Engine engine;
  SoundSettings s = SoundSettings();

  /// The lavfi chain mpv runs now ('' = none).
  String chain = '';
  final _opts = <String, String>{};
  Timer? _applyTimer, _saveTimer;
  String _device = '', _sourceKey = '';

  Future<void> init() async {
    s = SoundSettings.parse(lib.setting('sound'));
    _device = engine.device;
    engine.addListener(_onEngine);
    await apply();
  }

  DeviceInfo get device {
    final d = engine.devices.where((d) => d.name == engine.device).firstOrNull;
    return DeviceInfo(
      id: engine.device,
      name: engine.device == 'auto' || d == null ? 'System default' : d.description,
      exclusive: engine.exclusive,
      volume: engine.volume,
      muted: engine.muted,
      outFormat: engine.outFormat,
      outRate: engine.outRate,
      outChannels: engine.outChannels,
    );
  }

  SourceInfo get source {
    final t = engine.current;
    return SourceInfo(
      badge: t?.badge ?? '',
      format: engine.srcFormat,
      rate: engine.srcRate > 0 ? engine.srcRate : (t?.sampleRate ?? 0),
      bits: engine.srcBits,
      channels: engine.srcChannels,
      rg: t?.rgTrackGain == null ? null : (t!.rgTrackGain!, t.rgTrackPeak ?? 1, t.rgAlbumGain, t.rgAlbumPeak),
      albumInOrder: _albumInOrder,
    );
  }

  /// Not shuffled, and the song next to this one comes from the same album.
  bool get _albumInOrder {
    final q = engine.queue;
    String? album(int i) => i < 0 || i >= q.items.length ? null : lib.byId[q.items[i].trackId]?.albumKey;
    final k = album(q.index);
    return !q.shuffle && k != null && (album(q.index - 1) == k || album(q.index + 1) == k);
  }

  ({List<String> steps, List<String> why}) get path => signalPath(s, device, source);

  /// The player bar's tooltip: the verdict, then the path.
  String get summary {
    final x = path;
    return '${x.why.isEmpty ? 'Bit-perfect ✓' : 'Not bit-perfect: ${x.why.join(', ')}'}\n${x.steps.join(' → ')}';
  }

  /// Changes the settings: applied after a short pause (slider drags), saved a little later.
  void change(void Function(SoundSettings s) edit) {
    edit(s);
    if (s.perDevice) s.deviceEq[engine.device] = s.eq.copy();
    notifyListeners();
    _applyTimer?.cancel();
    _applyTimer = Timer(const Duration(milliseconds: 40), apply);
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 500), save);
  }

  void save() => lib.setSetting('sound', jsonEncode(s.toJson()));

  /// Sends the current settings to mpv: only what changed, one apply at a time.
  Future<void> apply() => _applying = _applying.then((_) => _apply()).catchError((Object e) => debugPrint('sound: $e'));
  Future<void> _applying = Future.value();

  Future<void> _apply() async {
    final c = buildAudioChain(s, device, source);
    for (final e in c.options.entries) {
      if (_opts[e.key] == e.value) continue;
      final changed = _opts.containsKey(e.key);
      _opts[e.key] = e.value;
      await engine.setOption(e.key, e.value);
      // The buffer size is read when the output opens.
      if (changed && e.key == 'audio-buffer') await engine.command(['ao-reload']);
    }
    if (c.chain == chain) return;
    var cmds = liveCommands(chain, c.chain);
    // mpv dropped a chain it couldn't build: rebuild instead of commanding nothing.
    if (cmds != null && (await engine.getOption('af')).isEmpty) cmds = null;
    chain = c.chain;
    if (cmds == null) return engine.setAudioFilters(c.chain);
    for (final x in cmds) {
      await engine.command(['af-command', 'lumen', ...x]);
    }
  }

  void _onEngine() {
    if (engine.device != _device) {
      _device = engine.device;
      final eq = s.deviceEq[_device];
      if (s.perDevice && eq != null) {
        s.eq = eq.copy();
        engine.say("Using '${eq.name}' EQ for ${device.name}");
        save();
        notifyListeners();
      }
      apply();
    }
    // Upsampling, ReplayGain Auto and levelling depend on the song.
    final key = '${engine.current?.id}|${engine.srcRate}|${engine.exclusive}|${engine.queue.shuffle}|${engine.queue.index}';
    if (key == _sourceKey) return;
    _sourceKey = key;
    apply();
  }

  @override
  void dispose() {
    engine.removeListener(_onEngine);
    _applyTimer?.cancel();
    _saveTimer?.cancel();
    super.dispose();
  }
}
