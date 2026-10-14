import 'dart:io';

import 'package:flutter/services.dart';

import '../audio/engine.dart';

/// OS media controls + media keys. Windows: System Media Transport Controls
/// (windows/runner/media_controls.cpp). Other platforms: nothing yet (Android
/// will plug in here).
class MediaControls {
  MediaControls(this.engine) {
    if (!Platform.isWindows) return;
    channel.setMethodCallHandler((call) async {
      switch ((call.method, call.arguments)) {
        case ('button', 'play'):
          await engine.play();
        case ('button', 'pause' || 'stop'):
          await engine.pause();
        case ('button', 'next'):
          await engine.next();
        case ('button', 'previous'):
          await engine.previous();
        case ('seek', final int ms): // dragged on the Windows media overlay
          await engine.seek(Duration(milliseconds: ms));
      }
    });
    engine.addListener(_update);
    engine.position.addListener(_tick);
  }

  final Engine engine;
  static const channel = MethodChannel('music_player/media_controls');
  (int?, bool, int, int)? _last;
  int _sent = -1;

  /// Track, play state, length or a seek changed.
  void _update() {
    final t = engine.current;
    final key = (t?.id, engine.playing, engine.duration.inSeconds, engine.seeks);
    if (key == _last) return;
    final trackChanged = key.$1 != _last?.$1 || key.$3 != _last?.$3;
    _last = key;
    _send(trackChanged);
  }

  /// While playing, the overlay's timeline is refreshed every 5 s.
  void _tick() {
    if (engine.playing && engine.position.value.inSeconds ~/ 5 != _sent) _send(false);
  }

  void _send(bool trackChanged) {
    final t = engine.current;
    _sent = engine.position.value.inSeconds ~/ 5;
    channel.invokeMethod('update', {
      'hasTrack': t != null,
      'trackChanged': trackChanged,
      'playing': engine.playing,
      'title': t?.title ?? '',
      'artist': t?.artist ?? '',
      'album': t?.album ?? '',
      'albumArtist': t?.albumArtist ?? '',
      'art': t?.cover ?? '',
      'positionMs': engine.position.value.inMilliseconds,
      'durationMs': engine.duration.inMilliseconds,
    });
  }
}
