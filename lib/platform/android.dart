import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../art/art_cache.dart';
import '../audio/engine.dart';
import '../library/library.dart';

/// Android's music folder on the phone's own storage (the default library folder there).
const androidMusic = '/storage/emulated/0/Music';

const _channel = MethodChannel('lumen/android'); // android/app/src/main/kotlin/.../MainActivity.kt

/// Lumen may read the music files (always true off Android).
final musicAccess = ValueNotifier(true);

/// Where Android plays the sound now (null off Android, or before it is known).
final audioRoute = ValueNotifier<AudioRoute?>(null);

class AudioRoute {
  const AudioRoute({required this.kind, this.product = '', this.rates = const [], this.mixerRate = 0, this.sdk = 0});
  factory AudioRoute.from(Map m) => AudioRoute(
    kind: m['kind'] as String? ?? 'speaker',
    product: m['product'] as String? ?? '',
    rates: [for (final r in m['rates'] as List? ?? const []) r as int],
    mixerRate: m['mixerRate'] as int? ?? 0,
    sdk: m['sdk'] as int? ?? 0,
  );

  /// 'bluetooth', 'wired', 'usb' or 'speaker'.
  final String kind, product;

  /// The rates the device lists (often none: it takes any), and the rate Android's mixer runs at.
  final List<int> rates;
  final int mixerRate, sdk;

  bool get bluetooth => kind == 'bluetooth';

  String get name => switch (kind) {
    'bluetooth' => 'Bluetooth headphones',
    'wired' => 'Wired headphones',
    'usb' => 'USB audio',
    _ => 'Phone speaker',
  };

  /// The rate the output really runs at: the highest the device lists (up to 96 kHz), else Android's mixer rate.
  int get nativeRate {
    final listed = rates.where((r) => r <= 96000);
    return listed.isEmpty ? mixerRate : listed.reduce((a, b) => a > b ? a : b);
  }
}

/// The app's version name from the APK (pubspec.yaml's version without the build number).
Future<String?> androidVersion() => _channel.invokeMethod<String>('version');

/// Reads the permission and the output, and follows output changes. Off Android: nothing.
Future<void> initAndroid() async {
  if (!Platform.isAndroid) return;
  _channel.setMethodCallHandler((call) async {
    if (call.method == 'route') audioRoute.value = AudioRoute.from(call.arguments as Map);
  });
  musicAccess.value = await _channel.invokeMethod<bool>('hasMusic') ?? false;
  audioRoute.value = AudioRoute.from(await _channel.invokeMethod<Map>('route') ?? const {});
}

/// Android's folder picker, on the phone's storage or an SD card / USB stick: the folder's plain path,
/// null when cancelled. Throws a PlatformException for places with no path (cloud apps, Downloads shortcuts).
Future<String?> pickAndroidFolder() => _channel.invokeMethod<String>('pickFolder');

/// Saves [text] as a file the user places and names (Windows' Save dialog, Android's "Save to" screen).
/// Returns where it went (the path; on Android the file name), or null when cancelled.
Future<String?> saveText(String name, String text, XTypeGroup type) async {
  if (Platform.isAndroid) return _channel.invokeMethod<String>('save', {'name': name, 'text': text});
  final loc = await getSaveLocation(suggestedName: name, acceptedTypeGroups: [type]);
  if (loc == null) return null;
  File(loc.path).writeAsStringSync(text);
  return loc.path;
}

/// Asks Android for the music files (and, on Android 13+, images for folder covers, and the notification).
Future<bool> askMusicAccess(Library lib) async {
  final ok = await _channel.invokeMethod<bool>('askMusic') ?? false;
  musicAccess.value = ok;
  useMusicFolder(lib);
  return ok;
}

/// With access and no library folder ever chosen, the phone's Music folder becomes the library
/// (also when the permission was given in Android's settings). Removing every folder later is respected.
void useMusicFolder(Library lib) {
  if (musicAccess.value && lib.setting('folders') == null) lib.folders = [androidMusic];
}

/// The media notification, lock screen, headphone and Bluetooth buttons (audio_service), audio focus
/// and "becoming noisy" (audio_session), all driving [engine].
Future<void> startAndroidMedia(Engine engine) async {
  await AudioService.init(
    builder: () => _Session(engine),
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'com.capsuleutkarsh.lumen.playback',
      androidNotificationChannelName: 'Playback',
      androidNotificationIcon: 'drawable/ic_launcher_foreground',
      androidStopForegroundOnPause: true,
    ),
  );
  final session = await AudioSession.instance;
  await session.configure(const AudioSessionConfiguration.music());
  var resume = false, was = false;
  // Calls and other players: pause, and play again after a short interruption (a call, a voice note).
  // Ducking needs nothing: Android 8+ lowers the volume itself.
  session.interruptionEventStream.listen((e) {
    if (e.type == AudioInterruptionType.duck) return;
    if (e.begin) {
      resume = engine.playing && e.type == AudioInterruptionType.pause;
      if (engine.playing) engine.pause();
    } else if (resume) {
      resume = false;
      engine.play();
    }
  });
  session.becomingNoisyEventStream.listen((_) => engine.pause()); // headphones unplugged
  engine.addListener(() {
    if (engine.playing == was) return;
    was = engine.playing;
    if (was) {
      session.setActive(true).then((ok) {
        if (!ok) engine.pause(); // a call holds the audio
      });
    }
  });
}

class _Session extends BaseAudioHandler with SeekHandler {
  _Session(this.engine) {
    engine.addListener(_update);
    engine.lib.addListener(_update);
    _update();
  }

  final Engine engine;
  (int?, bool, int, int, String?)? _last;

  void _update() {
    final t = engine.current;
    final art = t == null ? null : engine.lib.artFor(t.albumKey, t.cover);
    final file = art == null ? null : ArtCache.file(art, 384);
    final key = (t?.id, engine.playing, engine.duration.inMilliseconds, engine.seeks, file);
    if (key == _last) return;
    final trackChanged = key.$1 != _last?.$1 || key.$3 != _last?.$3 || key.$5 != _last?.$5;
    _last = key;
    if (file == null && art != null) ArtCache.ensure(art, 384).then((_) => _update()); // drawn art: sent once ready
    if (trackChanged) {
      mediaItem.add(
        t == null
            ? null
            : MediaItem(
                id: '${t.id}',
                title: t.title,
                artist: t.artist,
                album: t.album,
                duration: engine.duration > Duration.zero ? engine.duration : null,
                artUri: file == null ? null : Uri.file(file),
              ),
      );
    }
    playbackState.add(
      PlaybackState(
        controls: [MediaControl.skipToPrevious, engine.playing ? MediaControl.pause : MediaControl.play, MediaControl.skipToNext],
        systemActions: const {MediaAction.seek, MediaAction.playPause},
        androidCompactActionIndices: const [0, 1, 2],
        processingState: t == null ? AudioProcessingState.idle : AudioProcessingState.ready,
        playing: engine.playing,
        updatePosition: engine.position.value,
      ),
    );
  }

  @override
  Future<void> play() => engine.play();
  @override
  Future<void> pause() => engine.pause();
  @override
  Future<void> stop() => engine.pause();
  @override
  Future<void> skipToNext() => engine.next();
  @override
  Future<void> skipToPrevious() => engine.previous();
  @override
  Future<void> seek(Duration position) => engine.seek(position);
}
