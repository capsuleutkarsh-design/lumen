// The spinning disc: the album cover with a CD or a vinyl record sliding out from
// behind its right edge, printed with the art, spinning while the music plays.
import 'dart:ffi' hide Size;
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:ffi/ffi.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../art/art_cache.dart';
import 'app.dart';
import 'theme.dart';
import 'widgets.dart';

enum DiscStyle { cd, vinyl, off }

/// Settings → Disc & covers. Saved in the library's settings.
final ValueNotifier<DiscStyle> discStyle = ValueNotifier(DiscStyle.values.asNameMap()[lib.setting('disc')] ?? DiscStyle.cd)
  ..addListener(() => lib.setSetting('disc', discStyle.value.name));

/// Windows' "Show animations in Windows" is off (Settings → Accessibility → Visual effects).
bool get windowsAnimationsOff {
  if (!Platform.isWindows) return false;
  final on = calloc<Int32>();
  try {
    return _spi(0x1042 /* SPI_GETCLIENTAREAANIMATION */, 0, on, 0) != 0 && on.value == 0;
  } finally {
    calloc.free(on);
  }
}

final _spi = DynamicLibrary.open('user32.dll')
    .lookupFunction<Int32 Function(Uint32, Uint32, Pointer<Int32>, Uint32), int Function(int, int, Pointer<Int32>, int)>(
      'SystemParametersInfoW',
    );

/// How far right of the cover the disc reaches, as a share of the cover's side.
const discReach = 0.42;
const _discSize = 0.92; // the disc's diameter, as a share of the cover's side

/// The cover with the disc beside it. [size] is the cover's side; the whole thing is
/// `size * (1 + discReach)` wide (just [size] when the disc is off).
class DiscView extends StatefulWidget {
  const DiscView({
    super.key,
    required this.art,
    this.id,
    required this.playing,
    required this.size,
    required this.style,
    this.onCoverTap,
    this.onCoverMenu,
    this.glow,
  });
  final Art art;

  /// A coloured glow under the cover (the accent from the art), if any.
  final Color? glow;

  /// The song: a new one slides the disc back and out again, even on the same album.
  final Object? id;
  final bool playing;
  final double size;
  final DiscStyle style;
  final VoidCallback? onCoverTap;
  final GestureTapDownCallback? onCoverMenu;

  static double widthFor(double size, DiscStyle style) => style == DiscStyle.off ? size : size * (1 + discReach);

  @override
  State<DiscView> createState() => DiscViewState();
}

class DiscViewState extends State<DiscView> with TickerProviderStateMixin {
  /// Turns per second: 33⅓ rpm for vinyl, a slower, calmer turn for a CD.
  double get _rps => widget.style == DiscStyle.vinyl ? 100 / 3 / 60 : 0.2;

  /// The disc's angle in turns. Only the rotating layer listens to it.
  final turns = ValueNotifier(0.0);
  late final Ticker _ticker = createTicker(_tick);
  double _speed = 0, _from = 0, _to = 0; // share of full speed
  Duration _last = Duration.zero;
  Duration? _rampStart;

  late final _slide = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 450),
    reverseDuration: const Duration(milliseconds: 220),
  );
  ui.Image? _disc;
  int _gen = 0;
  bool _still = false;

  /// True while the disc turns (for tests: no ticker runs while paused).
  bool get spinning => _ticker.isActive;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _still = MediaQuery.disableAnimationsOf(context) || windowsAnimationsOff;
    if (_disc == null && _gen == 0) _load();
    _setPlaying();
  }

  @override
  void didUpdateWidget(DiscView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final o = oldWidget;
    if (o.art != widget.art || o.id != widget.id || o.style != widget.style || _px(o.size) != _px(widget.size)) _load();
    _setPlaying();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _slide.dispose();
    turns.dispose();
    _disc?.dispose();
    super.dispose();
  }

  int _px(double size) => (size * _discSize * MediaQuery.devicePixelRatioOf(context)).round();

  void _setPlaying() {
    if (_still || widget.style == DiscStyle.off) {
      // Animations off: the disc stays still.
      _speed = _to = 0;
      _ticker.stop();
      return;
    }
    final target = widget.playing ? 1.0 : 0.0;
    if (target == _to) return;
    _from = _speed;
    _to = target;
    _rampStart = null;
    if (!_ticker.isActive && (_to > 0 || _speed > 0)) {
      _last = Duration.zero;
      _ticker.start();
    }
  }

  /// Speeds up on play; on pause slows to a stop in 0.6 s (the angle eases out), then the ticker stops.
  void _tick(Duration elapsed) {
    final dt = (elapsed - _last).inMicroseconds / 1e6;
    _last = elapsed;
    _rampStart ??= elapsed;
    final k = ((elapsed - _rampStart!).inMicroseconds / 600000).clamp(0.0, 1.0);
    _speed = _from + (_to - _from) * (_to > _from ? Curves.easeOut.transform(k) : k);
    turns.value = (turns.value + _speed * _rps * dt) % 1;
    if (k >= 1 && _to == 0) _ticker.stop();
  }

  /// Draws this album's disc once (per track and size), then slides the old disc back and the new one out.
  Future<void> _load() async {
    final gen = ++_gen;
    if (widget.style == DiscStyle.off) {
      final old = _disc;
      _disc = null;
      if (old != null) SchedulerBinding.instance.addPostFrameCallback((_) => old.dispose());
      return;
    }
    final px = _px(widget.size);
    final style = widget.style;
    // The old disc tucks away while the new one is drawn, so it never shows the previous album for long.
    final tucked = _disc != null && !_still ? _slide.reverse() : null;
    ui.Image? cover;
    try {
      final file = await ArtCache.ensure(widget.art, px.toDouble());
      if (file != null) {
        final codec = await ui.instantiateImageCodec(await File(file).readAsBytes(), targetWidth: px, targetHeight: px);
        cover = (await codec.getNextFrame()).image;
        codec.dispose();
      }
    } catch (_) {} // no art: a plain disc
    final disc = await renderDisc(style, cover, px);
    cover?.dispose();
    if (!mounted || gen != _gen) {
      disc.dispose();
      return;
    }
    await tucked?.orCancel.catchError((_) {}); // a newer load may take the animation over
    if (!mounted || gen != _gen) {
      disc.dispose();
      return;
    }
    final old = _disc;
    setState(() => _disc = disc);
    if (old != null) SchedulerBinding.instance.addPostFrameCallback((_) => old.dispose());
    _still ? _slide.value = 1 : _slide.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size, d = s * _discSize;
    final radius = (s * 0.035).clamp(R.tiny, R.card);
    final cover = Clickable(
      onTap: widget.onCoverTap,
      onSecondaryTapDown: widget.onCoverMenu,
      radius: radius,
      cursor: widget.onCoverTap == null ? MouseCursor.defer : SystemMouseCursors.click,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(radius),
          boxShadow: [
            BoxShadow(color: C.shadow, blurRadius: s * 0.1, offset: Offset(0, s * 0.04)),
            if (widget.glow != null)
              BoxShadow(
                color: widget.glow!.withValues(alpha: C.isLight ? 0.35 : 0.45),
                blurRadius: s * 0.2,
                spreadRadius: -12,
              ),
          ],
        ),
        child: CoverArt.art(widget.art, size: s, radius: radius),
      ),
    );
    if (widget.style == DiscStyle.off) return SizedBox.square(dimension: s, child: cover);
    final vinyl = widget.style == DiscStyle.vinyl;
    return SizedBox(
      width: DiscView.widthFor(s, widget.style),
      height: s,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          if (_disc != null)
            AnimatedBuilder(
              animation: _slide,
              builder: (context, child) {
                // From hidden behind the cover to reaching [discReach] past its right edge.
                final t = Curves.easeOutCubic.transform(_slide.value);
                return Positioned(
                  left: (s - d) / 2 + t * (s * (1 + discReach) - d - (s - d) / 2),
                  top: (s - d) / 2,
                  width: d,
                  height: d,
                  child: child!,
                );
              },
              child: Stack(
                children: [
                  // Fixed layers (shadow, sheen) never repaint; only the disc layer turns.
                  Positioned.fill(
                    child: RepaintBoundary(child: CustomPaint(painter: _DiscShadow())),
                  ),
                  ValueListenableBuilder(
                    valueListenable: turns,
                    builder: (_, v, child) => Transform.rotate(angle: v * 2 * math.pi, child: child),
                    child: RepaintBoundary(
                      child: RawImage(image: _disc, width: d, height: d, filterQuality: FilterQuality.medium),
                    ),
                  ),
                  Positioned.fill(
                    child: RepaintBoundary(child: CustomPaint(painter: _DiscSheen(vinyl))),
                  ),
                ],
              ),
            ),
          Positioned(key: const ValueKey('cover'), left: 0, top: 0, child: cover), // keeps its state when the disc appears
        ],
      ),
    );
  }
}

/// The disc artwork, drawn once per track: [art] printed on a silver CD, or on the label of a vinyl record.
Future<ui.Image> renderDisc(DiscStyle style, ui.Image? art, int px) {
  final rec = ui.PictureRecorder();
  final c = Canvas(rec);
  final r = px / 2;
  final o = Offset(r, r);
  void artIn(double outer, double inner) {
    if (art == null) return;
    c.save();
    c.clipPath(
      Path()
        ..fillType = PathFillType.evenOdd
        ..addOval(Rect.fromCircle(center: o, radius: outer))
        ..addOval(Rect.fromCircle(center: o, radius: inner)),
    );
    final side = outer * 2;
    c.drawImageRect(
      art,
      Rect.fromLTWH(0, 0, art.width.toDouble(), art.height.toDouble()),
      Rect.fromCenter(center: o, width: side, height: side),
      Paint()..filterQuality = FilterQuality.medium,
    );
    c.restore();
  }

  Paint ring(Color col, double w) => Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = w
    ..color = col;

  if (style == DiscStyle.vinyl) {
    c.drawCircle(o, r, Paint()..color = const Color(0xFF0B0B0C));
    // Fine grooves, a little uneven, with a few quiet gaps between tracks.
    final w = math.max(1.0, px / 900);
    final gaps = [0.52, 0.63, 0.74, 0.86];
    for (var rr = r * 0.36; rr < r * 0.965; rr += w * 1.6) {
      final f = rr / r;
      if (gaps.any((g) => (f - g).abs() < 0.006)) continue;
      final a = 0.035 + 0.03 * (0.5 + 0.5 * math.sin(rr * 0.9)) + (gaps.any((g) => (f - g).abs() < 0.012) ? 0.04 : 0);
      c.drawCircle(o, rr, ring(Color.fromRGBO(255, 255, 255, a), w * 0.6));
    }
    c.drawCircle(o, r * 0.985, ring(const Color(0x22FFFFFF), r * 0.02)); // the lip
    // The label: the album art, with a thin dark edge and the spindle hole.
    c.drawCircle(o, r * 0.345, Paint()..color = const Color(0xFF1A1A1C));
    artIn(r * 0.33, 0);
    if (art == null) c.drawCircle(o, r * 0.33, Paint()..color = C.accent);
    c.drawCircle(o, r * 0.33, ring(const Color(0x40000000), r * 0.008));
    c.drawCircle(o, r * 0.022, Paint()..blendMode = BlendMode.clear);
  } else {
    // Silver, with the art printed from the hub to near the rim.
    c.drawCircle(
      o,
      r,
      Paint()
        ..shader = ui.Gradient.sweep(
          o,
          const [Color(0xFFD7DAE0), Color(0xFFA4A9B2), Color(0xFFE9EBEF), Color(0xFF9AA0A9), Color(0xFFD7DAE0)],
          const [0, .25, .5, .75, 1],
        ),
    );
    artIn(r * 0.975, r * 0.33);
    c.drawCircle(o, r * 0.33, ring(const Color(0x33000000), r * 0.006));
    // The clear plastic hub with its stacking ring, then the hole.
    c.drawCircle(o, r * 0.32, Paint()..color = const Color(0x8CC9CDD3));
    c.drawCircle(o, r * 0.22, ring(const Color(0x40FFFFFF), r * 0.012));
    c.drawCircle(o, r * 0.155, ring(const Color(0x30000000), r * 0.006));
    c.drawCircle(o, r * 0.12, Paint()..blendMode = BlendMode.clear);
    c.drawCircle(o, r * 0.995, ring(const Color(0x40000000), r * 0.01)); // the edge
  }
  final pic = rec.endRecording();
  return pic.toImage(px, px).whenComplete(pic.dispose);
}

/// A soft shadow under the disc (it does not turn).
class _DiscShadow extends CustomPainter {
  @override
  void paint(Canvas c, Size s) {
    final r = s.width / 2;
    c.drawCircle(
      Offset(r, r + r * 0.06),
      r * 0.98,
      Paint()
        ..color = C.shadow
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.08),
    );
  }

  @override
  bool shouldRepaint(_DiscShadow old) => false;
}

/// The light on the disc stays put while the disc turns under it: a rainbow sheen on a CD,
/// two soft specular wedges on vinyl.
class _DiscSheen extends CustomPainter {
  _DiscSheen(this.vinyl);
  final bool vinyl;
  @override
  void paint(Canvas c, Size s) {
    final r = s.width / 2, o = Offset(r, r);
    c.save();
    c.clipPath(
      Path()
        ..fillType = PathFillType.evenOdd
        ..addOval(Rect.fromCircle(center: o, radius: r * 0.995))
        ..addOval(Rect.fromCircle(center: o, radius: vinyl ? r * 0.35 : r * 0.12)),
    );
    if (vinyl) {
      const w = Color(0x00FFFFFF), hi = Color(0x24FFFFFF);
      // Peaks at the lower right and the upper left (sweep stops: 0 = 3 o'clock, clockwise).
      c.drawCircle(o, r, Paint()..shader = ui.Gradient.sweep(o, const [w, hi, w, w, hi, w], const [.03, .125, .22, .53, .625, .72]));
    } else {
      const t = Color(0x00FFFFFF);
      c.drawCircle(
        o,
        r,
        Paint()
          ..blendMode = BlendMode.screen
          ..shader = ui.Gradient.sweep(
            o,
            const [
              t,
              Color(0x3355E6FF),
              Color(0x33FF5FD2),
              Color(0x33FFE45C),
              t,
              t,
              Color(0x3355E6FF),
              Color(0x33FF5FD2),
              Color(0x33FFE45C),
              t,
            ],
            const [0, .06, .12, .18, .26, .5, .56, .62, .68, .76],
          ),
      );
      // A soft white glint across the top left.
      c.drawCircle(
        o,
        r,
        Paint()
          ..shader = ui.Gradient.linear(
            Offset(0, 0),
            Offset(s.width, s.height),
            const [Color(0x2EFFFFFF), Color(0x00FFFFFF), Color(0x00FFFFFF), Color(0x14FFFFFF)],
            const [0, .35, .7, 1],
          ),
      );
    }
    c.restore();
  }

  @override
  bool shouldRepaint(_DiscSheen old) => old.vinyl != vinyl;
}
