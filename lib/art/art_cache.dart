// Generated covers on disk: drawn once per size, kept as JPEGs in the cache folder,
// so every place that shows a cover (Image.file, the Windows media overlay, the disc)
// just gets a file path.
import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

import 'generative_cover.dart';

/// A cover to show: the album's own image [file], or generated art from [seed] when [file] is null.
@immutable
class Art {
  const Art(this.file, this.seed);
  final String? file;
  final int seed;
  bool get generated => file == null;
  @override
  bool operator ==(Object other) => other is Art && other.file == file && other.seed == seed;
  @override
  int get hashCode => Object.hash(file, seed);
}

/// A request for generated art. [done] gives the file (null if drawing failed).
class ArtJob {
  ArtJob._(this.seed, this.px, this.path);
  final int seed, px;
  final String path;
  final _done = Completer<String?>();
  Future<String?> get done => _done.future;
  int _wants = 0;

  /// Not needed any more (e.g. the row scrolled away): it is skipped if not drawn yet.
  void release() => _wants--;
}

/// Draws generated covers on the UI isolate (dart:ui needs it), at most one per frame and
/// the newest request first, so scrolling never waits; the JPEG encode runs in an isolate.
abstract final class ArtCache {
  /// The cache folder (Local AppData\...\art). Null in widget tests: generated art stays a placeholder.
  static String? dir;

  /// Bump when the art code changes, so files drawn by older code are not shown (or kept).
  static const version = 2;
  static const sizes = [128, 384, 1024];

  static int bucket(double px) => sizes.firstWhere((s) => s >= px, orElse: () => sizes.last);

  static String _path(int seed, int px) => p.join(dir!, 'v${version}_${seed.toRadixString(16)}_$px.jpg');

  /// Sets the folder and removes files drawn by an older [version] (in the background).
  static void init(String folder) {
    dir = folder;
    Directory(folder).createSync(recursive: true);
    unawaited(() async {
      await for (final f in Directory(folder).list()) {
        final name = p.basename(f.path);
        if (f is File && (!name.startsWith('v${version}_') || name.endsWith('.tmp'))) await f.delete().catchError((_) => f);
      }
    }());
  }

  static final _ready = <String>{};
  static final _jobs = <String, ArtJob>{};
  static final _queue = <ArtJob>[];
  static bool _running = false;
  static int _encoding = 0;
  static Completer<void>? _encoded;

  /// The file for [art] at about [px] pixels: the album's own cover, or generated art
  /// that is already drawn. Null while it still has to be drawn (see [want]).
  static String? file(Art art, double px) {
    if (art.file != null) return art.file;
    if (dir == null) return null;
    final path = _path(art.seed, bucket(px));
    if (_ready.contains(path)) return path;
    if (!_jobs.containsKey(path) && File(path).existsSync()) {
      _ready.add(path);
      return path;
    }
    return null;
  }

  /// Asks for generated art to be drawn. Call [ArtJob.release] when it is no longer wanted.
  static ArtJob want(Art art, double px) {
    final b = bucket(px);
    final path = _path(art.seed, b);
    final job = _jobs.putIfAbsent(path, () {
      final j = ArtJob._(art.seed, b, path);
      _queue.add(j);
      return j;
    });
    job._wants++;
    // Newest first: what is on screen now.
    if (_queue.remove(job)) _queue.add(job);
    _run();
    return job;
  }

  /// The file for [art], drawing it first if needed. Null without a cache folder.
  static Future<String?> ensure(Art art, double px) async {
    final ready = file(art, px);
    if (ready != null || dir == null) return ready;
    final job = want(art, px);
    try {
      return await job.done;
    } finally {
      job.release();
    }
  }

  static Future<void> _run() async {
    if (_running) return;
    _running = true;
    try {
      while (true) {
        _queue.removeWhere((j) => j._wants <= 0 && _jobs.remove(j.path) != null);
        if (_queue.isEmpty) break;
        // One cover per frame: let a frame in flight finish first (a minimised window has no frames).
        if (SchedulerBinding.instance.hasScheduledFrame) {
          await SchedulerBinding.instance.endOfFrame.timeout(const Duration(milliseconds: 100), onTimeout: () {});
        }
        // A few encodes at a time.
        while (_encoding >= 3) {
          await (_encoded ??= Completer()).future;
        }
        if (_queue.isEmpty) continue;
        final job = _queue.removeLast();
        if (job._wants <= 0) {
          _jobs.remove(job.path);
          continue;
        }
        await _draw(job);
      }
    } finally {
      _running = false;
    }
  }

  static Future<void> _draw(ArtJob job) async {
    Uint8List rgba;
    try {
      final pic = GenerativeCover(job.seed).record(job.px); // the only part on the UI thread
      final im = await pic.toImage(job.px, job.px);
      pic.dispose();
      final data = await im.toByteData(format: ui.ImageByteFormat.rawRgba);
      im.dispose();
      rgba = data!.buffer.asUint8List();
    } catch (_) {
      _finish(job, null);
      return;
    }
    _encoding++;
    _encodeJpg(rgba, job.px, job.path).then((ok) => ok, onError: (_) => false).then((ok) {
      _encoding--;
      _encoded?.complete();
      _encoded = null;
      _finish(job, ok ? job.path : null);
    });
  }

  static void _finish(ArtJob job, String? path) {
    if (path != null) _ready.add(path);
    _jobs.remove(job.path);
    job._done.complete(path);
  }
}

/// RGBA pixels to a JPEG file, in a background isolate. Written to a temporary name first,
/// so a half-written file is never shown.
Future<bool> _encodeJpg(Uint8List rgba, int px, String path) => Isolate.run(() {
  final im = img.Image.fromBytes(width: px, height: px, bytes: rgba.buffer, numChannels: 4);
  final tmp = '$path.$pid.tmp';
  File(tmp).writeAsBytesSync(img.encodeJpg(im, quality: 90));
  File(tmp).renameSync(path);
  return true;
});
