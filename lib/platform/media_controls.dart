import 'dart:io';

import 'package:flutter/services.dart';

import '../audio/engine.dart';

/// OS media controls + media keys. Windows: System Media Transport Controls
/// (windows/runner/media_controls.cpp). Other platforms: nothing yet (Android
/// will plug in here).
class MediaControls {
  MediaControls(this.engine) {
    if (!Platform.isWindows) return;
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'button') return;
      switch (call.arguments as String) {
        case 'play' || 'pause':
          await engine.togglePlay();
        case 'next':
          await engine.next();
        case 'previous':
          await engine.previous();
      }
    });
    engine.addListener(_update);
  }

  final Engine engine;
  static const _channel = MethodChannel('music_player/media_controls');
  (int?, bool, int)? _last;

  void _update() {
    final t = engine.current;
    final key = (t?.id, engine.playing, engine.duration.inSeconds);
    if (key == _last) return;
    final trackChanged = key.$1 != _last?.$1 || key.$3 != _last?.$3;
    _last = key;
    _channel.invokeMethod('update', {
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
