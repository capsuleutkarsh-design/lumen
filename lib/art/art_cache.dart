// Generated covers on disk: drawn once per size, kept as JPEGs in the cache folder,
// so every place that shows a cover (Image.file, the Windows media overlay, the disc)
// just gets a file path.
import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

import 'generative_cover.dart';

/// A cover to show: the album's own image [file], or art Gleo draws, named by [key]:
/// `<style>@<seed in hex>` (a code style) or `pack:<pack>/<image>` (a bundled image, see art_sources.dart).
@immutable
class Art {
  const Art.file(String this.file) : key = null;
  const Art.drawn(String this.key) : file = null;
  final String? file, key;
  bool get generated => file == null;
  @override
  bool operator ==(Object other) => other is Art && other.file == file && other.key == key;
  @override
  int get hashCode => Object.hash(file, key);
  @override
  String toString() => 'Art(${file ?? key})';
}

/// A request for generated art. [done] gives the file (null if drawing failed).
class ArtJob {
  ArtJob._(this.key, this.px, this.path);
  final String key;
  final int px;
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

  /// Where pack images are read from (a test can hand in its own bundle).
  static AssetBundle assets = rootBundle;

  /// Bump when the art code changes, so files drawn by older code are not shown (or kept).
  static const version = 3;
  static const sizes = [128, 384, 1024];

  static int bucket(double px) => sizes.firstWhere((s) => s >= px, orElse: () => sizes.last);

  static String _path(String key, int px) => p.join(dir!, 'v${version}_${key.replaceAll(RegExp(r'[^\w@.-]'), '_')}_$px.jpg');

  /// The cache is kept under this size (at start): the files used longest ago go first.
  static const maxBytes = 300 << 20;

  /// Sets the folder and tidies it in the background (see [trim]).
  static void init(String folder) {
    dir = folder;
    Directory(folder).createSync(recursive: true);
    unawaited(trim(folder));
  }

  /// Removes files drawn by an older [version], then the least recently used ones while the
  /// folder is over [max] bytes. "Used" is the file's last-access time, which [file] sets.
  static Future<void> trim(String folder, [int max = maxBytes]) async {
    final keep = <(File, FileStat)>[];
    await for (final f in Directory(folder).list()) {
      if (f is! File) continue;
      final name = p.basename(f.path);
      if (!name.startsWith('v${version}_') || name.endsWith('.tmp')) {
        await f.delete().catchError((_) => f);
      } else {
        keep.add((f, await f.stat()));
      }
    }
    var total = keep.fold(0, (n, e) => n + e.$2.size);
    keep.sort((a, b) => a.$2.accessed.compareTo(b.$2.accessed));
    for (final (f, st) in keep) {
      if (total <= max) break;
      _ready.remove(f.path);
      await f.delete().catchError((_) => f);
      total -= st.size;
    }
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
    final path = _path(art.key!, bucket(px));
    if (_ready.contains(path)) return path;
    if (!_jobs.containsKey(path) && File(path).existsSync()) {
      _ready.add(path);
      File(path).setLastAccessed(DateTime.now()).ignore(); // used: [trim] keeps it longer (once per run is enough)
      return path;
    }
    return null;
  }

  /// Asks for generated art to be drawn. Call [ArtJob.release] when it is no longer wanted.
  static ArtJob want(Art art, double px) {
    final b = bucket(px);
    final path = _path(art.key!, b);
    final job = _jobs.putIfAbsent(path, () {
      final j = ArtJob._(art.key!, b, path);
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
      final im = await _render(job.key, job.px);
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

  /// Draws a code style (recording it is the only part on the UI thread), or decodes a pack image
  /// at about [px] (off the UI thread) and crops it square.
  static Future<ui.Image> _render(String key, int px) async {
    final rec = ui.PictureRecorder();
    final c = Canvas(rec);
    if (key.startsWith('pack:')) {
      final data = await assets.load('assets/covers/${key.substring(5)}');
      final codec = await ui.instantiateImageCodecWithSize(
        await ui.ImmutableBuffer.fromUint8List(data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes)),
        getTargetSize: (w, h) {
          final k = px / (w < h ? w : h);
          return k >= 1 ? ui.TargetImageSize(width: w, height: h) : ui.TargetImageSize(width: (w * k).ceil(), height: (h * k).ceil());
        },
      );
      final im = (await codec.getNextFrame()).image;
      codec.dispose();
      final side = (im.width < im.height ? im.width : im.height).toDouble();
      c.drawImageRect(
        im,
        Rect.fromCenter(center: Offset(im.width / 2, im.height / 2), width: side, height: side),
        Rect.fromLTWH(0, 0, px.toDouble(), px.toDouble()),
        Paint()..filterQuality = FilterQuality.high,
      );
      im.dispose();
    } else {
      final at = key.indexOf('@');
      GenerativeCover(
        int.parse(key.substring(at + 1), radix: 16),
        style: CoverStyle.values.byName(key.substring(0, at)),
      ).draw(c, px.toDouble());
    }
    final pic = rec.endRecording();
    return pic.toImage(px, px).whenComplete(pic.dispose);
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

/// Generated art as an [ImageProvider]: read from the cache, or drawn first when it isn't there.
class GeneratedArtImage extends ImageProvider<GeneratedArtImage> {
  const GeneratedArtImage(this.art, this.px);
  final Art art;
  final int px;

  @override
  Future<GeneratedArtImage> obtainKey(ImageConfiguration configuration) => SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(GeneratedArtImage key, ImageDecoderCallback decode) => OneFrameImageStreamCompleter(_load(decode));

  Future<ImageInfo> _load(ImageDecoderCallback decode) async {
    final file = await ArtCache.ensure(art, px.toDouble());
    if (file == null) throw StateError('no cover cache');
    final codec = await decode(await ui.ImmutableBuffer.fromFilePath(file), getTargetSize: (_, _) => ui.TargetImageSize(width: px));
    return ImageInfo(image: (await codec.getNextFrame()).image);
  }

  @override
  bool operator ==(Object other) => other is GeneratedArtImage && other.art == art && other.px == px;
  @override
  int get hashCode => Object.hash(art, px);
}
