// Generative album covers: drawn by code, offline, deterministic per seed.
//
//   final seed = GenerativeCover.seedFor(album.key);
//   CustomPaint(painter: GenerativeCover(seed));          // live, any size
//   final png = await GenerativeCover(seed).toPng(512);   // for a disk cache
//
// The seed picks the style, the palette and every parameter, so the same album
// always gets the same art. Everything is drawn in "unit" coordinates (0..1)
// scaled by the cover size, so a 48 px thumbnail and a 1024 px hero match.
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';

import 'palettes.dart';

enum CoverStyle { mesh, halftone, contours, bauhaus, riso, bokeh, flow, rings, stripes, paper, glitch, aurora }

class GenerativeCover extends CustomPainter {
  GenerativeCover(this.seed, {CoverStyle? style, this.initials, this.mark = false})
    : style = style ?? styleOf(seed);

  final int seed;
  final CoverStyle style;

  /// Optional initials (e.g. the album title's) set small in the corner.
  final String? initials;

  /// Optional tiny Lumen mark in the corner.
  final bool mark;

  /// A stable 32-bit hash (FNV-1a) of an album key: the cover's seed.
  static int seedFor(String key) {
    var h = 0x811C9DC5;
    for (final c in key.codeUnits) {
      h = ((h ^ c) * 0x01000193) & 0xFFFFFFFF;
    }
    return h;
  }

  static CoverStyle styleOf(int seed) => CoverStyle.values[_Rng(seed ^ 0x5bd1e995).i(CoverStyle.values.length)];

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    canvas.save();
    canvas.translate((size.width - s) / 2, (size.height - s) / 2);
    draw(canvas, s);
    canvas.restore();
  }

  @override
  bool shouldRepaint(GenerativeCover old) =>
      old.seed != seed || old.style != style || old.initials != initials || old.mark != mark;

  ui.Picture record(int px) {
    final rec = ui.PictureRecorder();
    draw(Canvas(rec), px.toDouble());
    return rec.endRecording();
  }

  Future<ui.Image> toImage(int px) {
    final pic = record(px);
    return pic.toImage(px, px).whenComplete(pic.dispose);
  }

  /// PNG bytes of a [px] square cover, for a disk cache.
  Future<Uint8List> toPng(int px) async {
    final im = await toImage(px);
    try {
      return (await im.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();
    } finally {
      im.dispose();
    }
  }

  /// Draws the cover into the square (0,0)-(s,s).
  void draw(Canvas c, double s) {
    final r = _Rng(seed);
    final k = _K(c, s, r, _palette(r), _Noise(r));
    c.save();
    c.clipRect(Rect.fromLTWH(0, 0, s, s));
    switch (style) {
      case CoverStyle.mesh:
        _mesh(k);
      case CoverStyle.halftone:
        _halftone(k);
      case CoverStyle.contours:
        _contours(k);
      case CoverStyle.bauhaus:
        _bauhaus(k);
      case CoverStyle.riso:
        _riso(k);
      case CoverStyle.bokeh:
        _bokeh(k);
      case CoverStyle.flow:
        _flow(k);
      case CoverStyle.rings:
        _rings(k);
      case CoverStyle.stripes:
        _stripes(k);
      case CoverStyle.paper:
        _paper(k);
      case CoverStyle.glitch:
        _glitch(k);
      case CoverStyle.aurora:
        _aurora(k);
    }
    if (initials != null && initials!.isNotEmpty) _initials(k, initials!);
    if (mark) _mark(k);
    c.restore();
  }

  // How often each style takes a bright palette (the rest are dark and moody).
  static const _bright = {
    CoverStyle.bauhaus: .45,
    CoverStyle.riso: .5,
    CoverStyle.paper: .3,
    CoverStyle.halftone: .25,
    CoverStyle.stripes: .3,
    CoverStyle.rings: .2,
    CoverStyle.mesh: .2,
    CoverStyle.flow: .15,
    CoverStyle.contours: .1,
  };

  List<Color> _palette(_Rng r) {
    final list = r.d() < (_bright[style] ?? 0) ? brightPalettes : darkPalettes;
    return paletteColors(list[r.i(list.length)]);
  }
}

// ---------------------------------------------------------------- helpers

/// xorshift32 seeded through a murmur finaliser: ours, so the art never
/// changes with an SDK update.
class _Rng {
  _Rng(int seed) : _s = _mix(seed) | 1;
  int _s;
  static int _mix(int h) {
    h &= 0xFFFFFFFF;
    h ^= h >> 16;
    h = (h * 0x85EBCA6B) & 0xFFFFFFFF;
    h ^= h >> 13;
    h = (h * 0xC2B2AE35) & 0xFFFFFFFF;
    return h ^ (h >> 16);
  }

  double d() {
    var x = _s;
    x ^= (x << 13) & 0xFFFFFFFF;
    x ^= x >> 17;
    x ^= (x << 5) & 0xFFFFFFFF;
    _s = x;
    return x / 4294967296.0;
  }

  double r(double a, double b) => a + (b - a) * d();
  int i(int n) => (d() * n).floor() % n;
  bool p(double chance) => d() < chance;
  T pick<T>(List<T> l) => l[i(l.length)];
}

/// 2D Perlin noise, seeded.
class _Noise {
  _Noise(_Rng r) {
    final p = List<int>.generate(256, (i) => i);
    for (var i = 255; i > 0; i--) {
      final j = r.i(i + 1), t = p[i];
      p[i] = p[j];
      p[j] = t;
    }
    for (var i = 0; i < 512; i++) {
      _p[i] = p[i & 255];
    }
  }
  final _p = Int32List(512);

  static double _g(int h, double x, double y) => switch (h & 7) {
    0 => x + y,
    1 => -x + y,
    2 => x - y,
    3 => -x - y,
    4 => x,
    5 => -x,
    6 => y,
    _ => -y,
  };

  /// Roughly -1..1.
  double at(double x, double y) {
    final xf0 = x.floorToDouble(), yf0 = y.floorToDouble();
    final xi = xf0.toInt() & 255, yi = yf0.toInt() & 255;
    final xf = x - xf0, yf = y - yf0;
    final u = xf * xf * xf * (xf * (xf * 6 - 15) + 10), v = yf * yf * yf * (yf * (yf * 6 - 15) + 10);
    final a = _p[xi] + yi, b = _p[xi + 1] + yi;
    final x1 = _g(_p[a], xf, yf) + u * (_g(_p[b], xf - 1, yf) - _g(_p[a], xf, yf));
    final x2 = _g(_p[a + 1], xf, yf - 1) + u * (_g(_p[b + 1], xf - 1, yf - 1) - _g(_p[a + 1], xf, yf - 1));
    return (x1 + v * (x2 - x1)) * 1.3;
  }

  double fbm(double x, double y, [int oct = 3]) {
    var sum = 0.0, amp = 0.5, f = 1.0;
    for (var o = 0; o < oct; o++) {
      sum += amp * at(x * f, y * f);
      amp *= .5;
      f *= 2.03;
    }
    return sum * 1.15;
  }
}

/// Drawing context: canvas, size, randomness, palette and noise.
class _K {
  _K(this.c, this.s, this.r, List<Color> pal, this.n)
    : bg = pal[0],
      ink = pal[4],
      cols = [pal[1], pal[2], pal[3]],
      dark = pal[0].computeLuminance() < .3;
  final Canvas c;
  final double s;
  final _Rng r;
  final _Noise n;
  final Color bg, ink;
  final List<Color> cols; // a, b, c: dark-to-light on dark palettes
  final bool dark;

  Offset o(double x, double y) => Offset(x * s, y * s);
  Rect get all => Rect.fromLTWH(0, 0, s, s);

  /// A colour along a..c (t 0..1), optionally running on to ink.
  Color ramp(double t, {bool toInk = false}) {
    final l = toInk ? [...cols, ink] : cols;
    t = t.clamp(0.0, 1.0) * (l.length - 1);
    final i = t.floor().clamp(0, l.length - 2);
    return Color.lerp(l[i], l[i + 1], t - i)!;
  }

  /// A palette colour other than the background; the brighter ones more often.
  Color accent() => r.p(.15) ? ink : cols[dark ? 1 + r.i(2) : r.i(3)];

  /// Pixel-ish width that stays visible on thumbnails.
  double px(double unit, [double min = .7]) => math.max(unit * s, min);

  void fill(Color col) => c.drawRect(all, Paint()..color = col);

  void vgradient(Color top, Color bottom) => c.drawRect(
    all,
    Paint()..shader = ui.Gradient.linear(Offset.zero, Offset(0, s), [top, bottom]),
  );

  void vignette([double a = .45]) => c.drawRect(
    all,
    Paint()
      ..shader = ui.Gradient.radial(o(.5, .5), s * .75, [
        const Color(0x00000000),
        Color.fromRGBO(0, 0, 0, a),
      ], [.45, 1]),
  );

  /// Film grain: a noise tile overlaid at device-pixel scale. Lighter on
  /// thumbnails, where grain only reads as dirt.
  void grain(double amount) {
    final a = amount * (.25 + .75 * ((s - 64) / 400).clamp(0.0, 1.0));
    if (a <= 0) return;
    c.drawRect(
      all,
      Paint()
        ..shader = ImageShader(_grainTile(), TileMode.repeated, TileMode.repeated, Float64List.fromList(_identity))
        ..blendMode = BlendMode.overlay
        ..color = Color.fromRGBO(0, 0, 0, a.clamp(0.0, 1.0)),
    );
  }
}

const _identity = <double>[1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1];

ui.Image? _grain;

/// A 256 px grey noise tile, made once (centred on mid grey, which overlay
/// leaves unchanged).
ui.Image _grainTile() => _grain ??= () {
  const n = 256, levels = 24;
  final r = _Rng(1234567);
  final buckets = List.generate(levels, (_) => <double>[]);
  for (var y = 0; y < n; y++) {
    for (var x = 0; x < n; x++) {
      final g = (r.d() + r.d() + r.d() + r.d()) / 4; // ~gaussian, 0..1
      buckets[(g * levels).floor().clamp(0, levels - 1)]
        ..add(x + .5)
        ..add(y + .5);
    }
  }
  final rec = ui.PictureRecorder();
  final c = Canvas(rec)..drawRect(const Rect.fromLTWH(0, 0, 256, 256), Paint()..color = const Color(0xFF808080));
  for (var i = 0; i < levels; i++) {
    final v = (((i + .5) / levels - .5) * 1.0 * 255 + 128).round().clamp(0, 255);
    c.drawRawPoints(
      ui.PointMode.points,
      Float32List.fromList(buckets[i]),
      Paint()
        ..color = Color.fromARGB(255, v, v, v)
        ..strokeWidth = 1
        ..strokeCap = StrokeCap.square
        ..isAntiAlias = false,
    );
  }
  final pic = rec.endRecording();
  final im = pic.toImageSync(n, n);
  pic.dispose();
  return im;
}();

Paint _blur(Color col, double sigma) => Paint()
  ..color = col
  ..maskFilter = sigma > 0 ? MaskFilter.blur(BlurStyle.normal, sigma) : null;

// ---------------------------------------------------------------- styles

/// Grainy mesh gradient: big soft blobs of colour.
void _mesh(_K k) {
  final r = k.r, s = k.s;
  k.vgradient(Color.lerp(k.bg, k.cols[0], r.r(0, .6))!, k.bg);
  final n = 4 + r.i(4);
  for (var i = 0; i < n; i++) {
    final col = i == 0 ? k.cols[r.i(2)] : (r.p(.15) ? k.ink : k.cols[1 + r.i(2)]);
    final rx = r.r(.22, .5), ry = rx * r.r(.5, 1.2);
    k.c
      ..save()
      ..translate(r.r(-.05, 1.05) * s, r.r(-.05, 1.05) * s)
      ..rotate(r.r(0, math.pi))
      ..drawOval(
        Rect.fromCenter(center: Offset.zero, width: rx * 2 * s, height: ry * 2 * s),
        _blur(col.withValues(alpha: r.r(.55, .95)), s * r.r(.09, .16)),
      )
      ..restore();
  }
  if (r.p(.5)) k.vignette(.35);
  k.grain(.55);
}

/// Halftone dot field over a gradient, one or two inks at different angles.
void _halftone(_K k) {
  final r = k.r, s = k.s;
  k.fill(k.bg);
  final layers = r.p(.45) ? 2 : 1;
  final fieldType = r.i(4);
  final cx = r.r(.2, .8), cy = r.r(.2, .8), dir = r.r(0, math.pi * 2), fs = r.r(1.5, 3.5), freq = r.r(10, 22);
  final spacing = 1 / r.r(22, 40), gamma = r.r(.8, 1.6);
  var angle = r.pick([15.0, 30.0, 45.0, 75.0]) * math.pi / 180;
  for (var l = 0; l < layers; l++) {
    final col = k.accent();
    final ox = l * r.r(.05, .15), oy = l * r.r(-.1, .1);
    final ca = math.cos(angle), sa = math.sin(angle);
    const levels = 14;
    final buckets = List.generate(levels, (_) => <double>[]);
    final m = (1.5 / spacing).ceil();
    for (var j = -m; j <= m; j++) {
      for (var i = -m; i <= m; i++) {
        final u = i * spacing, v = j * spacing;
        final x = .5 + u * ca - v * sa, y = .5 + u * sa + v * ca;
        if (x < -spacing || x > 1 + spacing || y < -spacing || y > 1 + spacing) continue;
        final fx = x - ox, fy = y - oy;
        var f = switch (fieldType) {
          0 => .5 + ((fx - .5) * math.cos(dir) + (fy - .5) * math.sin(dir)) * 1.1,
          1 => 1 - math.sqrt((fx - cx) * (fx - cx) + (fy - cy) * (fy - cy)) / .55,
          2 => .5 + k.n.fbm(fx * fs, fy * fs) * 1.6,
          _ => .5 + .5 * math.sin(math.sqrt((fx - cx) * (fx - cx) + (fy - cy) * (fy - cy)) * freq),
        };
        f = math.pow(f.clamp(0.0, 1.0), gamma).toDouble();
        final b = (f * levels).floor();
        if (b <= 0) continue;
        buckets[math.min(b, levels - 1)]
          ..add(x * s)
          ..add(y * s);
      }
    }
    final mode = layers == 2 && l == 1 ? (k.dark ? BlendMode.screen : BlendMode.multiply) : BlendMode.srcOver;
    for (var b = 1; b < levels; b++) {
      if (buckets[b].isEmpty) continue;
      k.c.drawRawPoints(
        ui.PointMode.points,
        Float32List.fromList(buckets[b]),
        Paint()
          ..color = col
          ..blendMode = mode
          ..strokeCap = StrokeCap.round
          ..strokeWidth = spacing * s * 1.15 * b / (levels - 1),
      );
    }
    angle += math.pi / 6;
  }
  k.grain(.3);
}

/// Topographic contour lines over a noise height field.
void _contours(_K k) {
  final r = k.r, s = k.s;
  k.fill(k.bg);
  final glow = k.cols[r.i(3)];
  k.c.drawRect(
    k.all,
    Paint()
      ..shader = ui.Gradient.radial(k.o(r.r(.2, .8), r.r(.2, .8)), s * .7, [
        glow.withValues(alpha: .35),
        glow.withValues(alpha: 0),
      ]),
  );
  final g = k.s < 160 ? 40 : 110; // thumbnails need far fewer cells
  final fs = r.r(1.4, 3.2), ox = r.r(0, 50), oy = r.r(0, 50);
  final peak = r.p(.5), px = r.r(.25, .75), py = r.r(.25, .75), pk = r.r(.6, 1.4);
  final v = Float64List((g + 1) * (g + 1));
  var lo = double.infinity, hi = -double.infinity;
  for (var j = 0; j <= g; j++) {
    for (var i = 0; i <= g; i++) {
      final x = i / g, y = j / g;
      var h = k.n.fbm(x * fs + ox, y * fs + oy);
      if (peak) h -= pk * math.sqrt((x - px) * (x - px) + (y - py) * (y - py));
      v[j * (g + 1) + i] = h;
      lo = math.min(lo, h);
      hi = math.max(hi, h);
    }
  }
  final levels = 12 + r.i(16), hero = r.i(levels);
  final w = k.px(r.r(.0018, .0032));
  for (var l = 1; l < levels; l++) {
    final lvl = lo + (hi - lo) * l / levels;
    final seg = _iso(v, g, lvl, s);
    if (seg.isEmpty) continue;
    final isHero = l == hero;
    k.c.drawRawPoints(
      ui.PointMode.lines,
      seg,
      Paint()
        ..color = isHero ? k.ink : k.ramp(l / levels, toInk: true).withValues(alpha: .9)
        ..strokeWidth = isHero ? w * 2.2 : w
        ..strokeCap = StrokeCap.butt,
    );
  }
  k.grain(.3);
}

/// Marching squares: line segments (x0,y0,x1,y1,...) where [v] crosses [lvl].
Float32List _iso(Float64List v, int g, double lvl, double s) {
  final out = <double>[];
  final cs = s / g, w = g + 1;
  for (var j = 0; j < g; j++) {
    for (var i = 0; i < g; i++) {
      final a = v[j * w + i], b = v[j * w + i + 1], c = v[(j + 1) * w + i + 1], d = v[(j + 1) * w + i];
      final idx = (a > lvl ? 8 : 0) | (b > lvl ? 4 : 0) | (c > lvl ? 2 : 0) | (d > lvl ? 1 : 0);
      if (idx == 0 || idx == 15) continue;
      final x = i * cs, y = j * cs;
      double t(double p, double q) => (lvl - p) / (q - p);
      void seg(int e1, int e2) {
        for (final e in [e1, e2]) {
          switch (e) {
            case 0: // top
              out
                ..add(x + cs * t(a, b))
                ..add(y);
            case 1: // right
              out
                ..add(x + cs)
                ..add(y + cs * t(b, c));
            case 2: // bottom
              out
                ..add(x + cs * t(d, c))
                ..add(y + cs);
            default: // left
              out
                ..add(x)
                ..add(y + cs * t(a, d));
          }
        }
      }

      switch (idx) {
        case 1 || 14:
          seg(3, 2);
        case 2 || 13:
          seg(2, 1);
        case 3 || 12:
          seg(3, 1);
        case 4 || 11:
          seg(0, 1);
        case 5:
          seg(0, 1);
          seg(3, 2);
        case 6 || 9:
          seg(0, 2);
        case 7 || 8:
          seg(0, 3);
        case 10:
          seg(0, 3);
          seg(2, 1);
      }
    }
  }
  return Float32List.fromList(out);
}

/// Bauhaus tiles: a grid of quarter circles, half discs, bars and triangles.
void _bauhaus(_K k) {
  final r = k.r, s = k.s;
  final set = [k.bg, ...k.cols, k.ink]..removeAt(1 + r.i(3)); // four colours
  k.fill(set[0]);
  final n = r.pick([2, 3, 3, 4, 4, 5]);
  final cell = s / n;
  Color other(Color not) {
    Color c;
    do {
      c = set[r.i(set.length)];
    } while (c == not);
    return c;
  }

  void tile(double x, double y, double w, int motif) {
    final cb = set[r.i(set.length)];
    final cm = other(cb);
    final p = Paint()..color = cm;
    k.c
      ..save()
      ..clipRect(Rect.fromLTWH(x, y, w, w))
      ..drawRect(Rect.fromLTWH(x, y, w, w), Paint()..color = cb);
    final corner = r.i(4), cx = x + (corner & 1) * w, cy = y + (corner >> 1) * w;
    switch (motif) {
      case 0: // quarter circle from a corner
        k.c.drawCircle(Offset(cx, cy), w, p);
      case 1: // half disc on an edge
        final e = r.i(4);
        k.c.drawCircle(
          Offset(x + w * [.5, 1, .5, 0][e], y + w * [0, .5, 1, .5][e]),
          w / 2,
          p,
        );
      case 2: // disc, sometimes with a ring
        k.c.drawCircle(Offset(x + w / 2, y + w / 2), w * .36, p);
        if (r.p(.5)) {
          k.c.drawCircle(Offset(x + w / 2, y + w / 2), w * .16, Paint()..color = other(cm));
        }
      case 3: // triangle
        final path = Path()
          ..moveTo(cx, cy)
          ..lineTo(x + w - (cx - x), cy)
          ..lineTo(cx, y + w - (cy - y))
          ..close();
        k.c.drawPath(path, p);
      case 4: // bars
        final vert = r.p(.5);
        for (var b = 0; b < 3; b++) {
          final o = w * (.12 + b * .3);
          k.c.drawRect(
            vert ? Rect.fromLTWH(x + o, y, w * .16, w) : Rect.fromLTWH(x, y + o, w, w * .16),
            p,
          );
        }
      case 5: // two quarter circles, opposite corners
        k.c
          ..drawCircle(Offset(cx, cy), w / 2, p)
          ..drawCircle(Offset(x + w - (cx - x), y + w - (cy - y)), w / 2, p);
      case 6: // leaf: two quarter circles intersecting
        k.c
          ..save()
          ..clipPath(Path()..addOval(Rect.fromCircle(center: Offset(cx, cy), radius: w)))
          ..drawCircle(Offset(x + w - (cx - x), y + w - (cy - y)), w, p)
          ..restore();
    }
    k.c.restore();
  }

  for (var j = 0; j < n; j++) {
    for (var i = 0; i < n; i++) {
      tile(i * cell, j * cell, cell, r.i(8));
    }
  }
  if (n >= 3 && r.p(.5)) {
    final hi = r.i(n - 1), hj = r.i(n - 1);
    tile(hi * cell, hj * cell, cell * 2, r.pick([0, 1, 2, 6]));
  }
  k.grain(.3);
}

/// Risograph: two inks overprinted (multiply on paper, screen on dark), a
/// little out of register, with a speckled ink texture.
void _riso(_K k) {
  final r = k.r, s = k.s;
  k.fill(k.bg);
  final inks = k.dark ? (r.p(.5) ? [k.cols[2], k.ink] : [k.ink, k.cols[2]]) : [k.cols[r.i(3)], k.cols[2], k.cols[1]];
  final inkA = inks[0], inkB = inks[1] == inks[0] ? k.cols[0] : inks[1];
  final mode = k.dark ? BlendMode.screen : BlendMode.multiply;
  final comp = r.pick([0, 1, 2, 3, 4, 6, 7, 0, 1, 2, 3, 4, 6, 7, 5]);
  // Shared composition numbers, so both inks line up.
  final a = r.r(.35, .65), b = r.r(.35, .6), c = r.r(0, 1), n = 3 + r.i(4), rot = r.r(-.6, .6), f = r.r(5, 10);
  final mis = Offset(r.r(-.007, .007) * s, r.r(-.007, .007) * s);
  void layer(Color ink, bool first) {
    k.c.saveLayer(k.all, Paint()..blendMode = mode);
    if (!first) k.c.translate(mis.dx, mis.dy);
    final p = Paint()..color = ink;
    switch (comp) {
      case 0: // sun behind stripes
        if (first) {
          k.c.drawCircle(k.o(a, b), s * .3, p);
        } else {
          for (var i = 0; i < n + 2; i++) {
            k.c.drawRect(Rect.fromLTWH(0, (b - .1 + i * .09) * s, s, .045 * s), p);
          }
        }
      case 1: // venn
        k.c.drawCircle(k.o(first ? .36 : .64, b), s * .26, p);
        if (!first) k.c.drawCircle(k.o(.2 + .6 * c, .14), s * .05, p);
      case 2: // rainbow arches, then a sun and ground
        if (first) {
          for (var i = 0; i < n; i++) {
            k.c.drawArc(
              Rect.fromCircle(center: k.o(a, .82), radius: (.44 - i * (.36 / n)) * s),
              math.pi,
              math.pi,
              false,
              Paint()
                ..color = ink
                ..style = PaintingStyle.stroke
                ..strokeWidth = s * .36 / n * .55,
            );
          }
        } else {
          k.c
            ..drawCircle(k.o(.2 + .6 * c, .24), s * .1, p)
            ..drawRect(Rect.fromLTWH(0, .82 * s, s, .18 * s), p);
        }
      case 3: // rotated slabs over a disc
        if (first) {
          k.c
            ..save()
            ..translate(s / 2, s / 2)
            ..rotate(rot);
          for (var i = 0; i < 3; i++) {
            k.c.drawRect(Rect.fromLTWH(-.7 * s, (i * .28 - .42) * s, 1.4 * s, .14 * s), p);
          }
          k.c.restore();
        } else {
          k.c.drawCircle(k.o(a, b), s * .28, p);
        }
      case 4: // a halftone sphere and a solid band
        if (first) {
          const sp = 1 / 30;
          for (var y = b - .34; y < b + .34; y += sp) {
            for (var x = a - .34; x < a + .34; x += sp) {
              final d = math.sqrt((x - a) * (x - a) + (y - b) * (y - b));
              if (d > .32) continue;
              final t = 1 - ((x - a + .2) * (x - a + .2) + (y - b + .2) * (y - b + .2)) / .4;
              k.c.drawCircle(k.o(x, y), sp * .62 * t.clamp(.15, 1.0) * s, p);
            }
          }
        } else {
          k.c.drawRect(Rect.fromLTWH(0, (b + .12) * s, s, .2 * s), p);
        }
      case 5: // polka grids, the second shifted half a cell
        final g = n + 1, cell = 1 / g;
        for (var j = 0; j <= g; j++) {
          for (var i = 0; i <= g; i++) {
            final o = first ? cell / 2 : 0.0;
            k.c.drawCircle(k.o(o + i * cell, o + j * cell), s * cell * .32, p);
          }
        }
      case 6: // two crossing wave bands
        double yAt(double t) => (first ? b : 1 - b) + .1 * math.sin(t * f + c * 6 + (first ? 0 : 2));
        final path = Path()..moveTo(-.05 * s, (yAt(0) - .1) * s);
        for (var j = 0; j <= 60; j++) {
          final t = j / 60;
          path.lineTo((t * 1.1 - .05) * s, (yAt(t) - .1) * s);
        }
        for (var j = 60; j >= 0; j--) {
          final t = j / 60;
          path.lineTo((t * 1.1 - .05) * s, (yAt(t) + .1) * s);
        }
        k.c.drawPath(path..close(), p);
      default: // a spiral of turned square outlines around a disc
        k.c
          ..save()
          ..translate(a * s, b * s);
        if (first) {
          for (var i = 0; i < n + 1; i++) {
            final w = (.7 - i * (.5 / (n + 1))) * s;
            k.c
              ..rotate(rot / 2)
              ..drawRect(
                Rect.fromCenter(center: Offset.zero, width: w, height: w),
                Paint()
                  ..color = ink
                  ..style = PaintingStyle.stroke
                  ..strokeWidth = s * .022,
              );
          }
        } else {
          k.c.drawCircle(Offset.zero, s * .14, p);
        }
        k.c.restore();
    }
    // Speckle: punch the ink with the grain tile, like riso drum texture.
    k.c.drawRect(
      k.all,
      Paint()
        ..shader = ImageShader(_grainTile(), TileMode.repeated, TileMode.repeated, Float64List.fromList(_identity))
        ..blendMode = BlendMode.dstOut
        ..color = const Color(0x66000000),
    );
    k.c.restore();
  }

  layer(inkA, true);
  layer(inkB, false);
  k.grain(.35);
}

/// Bokeh and light leaks: discs of out-of-focus light on a dark ground.
void _bokeh(_K k) {
  final r = k.r, s = k.s;
  k.vgradient(Color.lerp(k.bg, k.cols[0], .3)!, k.bg);
  // A light leak glowing in from one edge, sometimes with a soft streak.
  final warm = k.cols[1 + r.i(2)];
  final e = r.i(4), t = r.r(.1, .9);
  final at = [k.o(t, -.15), k.o(1.15, t), k.o(t, 1.15), k.o(-.15, t)][e];
  k.c.drawCircle(at, s * r.r(.45, .7), _blur(warm.withValues(alpha: r.r(.35, .6)), s * .2)..blendMode = BlendMode.plus);
  if (r.p(.6)) {
    k.c
      ..save()
      ..translate(r.r(.2, .8) * s, r.r(.2, .8) * s)
      ..rotate(r.r(0, math.pi))
      ..drawOval(
        Rect.fromCenter(center: Offset.zero, width: 1.6 * s, height: r.r(.05, .12) * s),
        _blur(Color.lerp(warm, k.ink, .5)!.withValues(alpha: .3), s * .05)..blendMode = BlendMode.plus,
      )
      ..restore();
  }
  // Discs along a band: small ones crisp and bright, big ones soft and dim.
  final n = 18 + r.i(30), a0 = r.r(0, math.pi);
  final bx = r.r(.3, .7), by = r.r(.3, .7), spread = r.r(.1, .3);
  for (var i = 0; i < n; i++) {
    final t = r.r(-.8, .8), off = (r.d() + r.d() - 1) * spread;
    final x = bx + t * math.cos(a0) - off * math.sin(a0), y = by + t * math.sin(a0) + off * math.cos(a0);
    final rad = .014 + math.pow(r.d(), 1.8) * .1;
    final col = r.p(.2) ? k.ink : k.cols[1 + r.i(2)];
    final soft = rad > .06 || r.p(.3);
    final alpha = (.62 - rad * 3) * r.r(.7, 1);
    final c = k.o(x, y);
    k.c.drawCircle(c, rad * s, _blur(col.withValues(alpha: alpha), s * rad * (soft ? .35 : .04))..blendMode = BlendMode.plus);
    if (!soft) {
      k.c.drawCircle(
        c,
        rad * s * .96,
        Paint()
          ..color = col.withValues(alpha: alpha * .6)
          ..style = PaintingStyle.stroke
          ..strokeWidth = k.px(.0025)
          ..blendMode = BlendMode.plus,
      );
    }
  }
  k.vignette(.55);
  k.grain(.3);
}

/// Flow field: thin lines that follow a noise field.
void _flow(_K k) {
  final r = k.r, s = k.s;
  k.fill(k.bg);
  final fs = r.r(1.2, 3), curl = r.r(1, 2.4), rot = r.r(0, math.pi * 2), quant = r.p(.2);
  final count = 260 + r.i(400), steps = 30 + r.i(60);
  final step = r.r(.003, .006);
  final paths = [for (var i = 0; i < 4; i++) Path()];
  for (var i = 0; i < count; i++) {
    var x = r.r(-.1, 1.1), y = r.r(-.1, 1.1);
    final p = paths[r.p(.06) ? 3 : r.i(3)]..moveTo(x * s, y * s);
    for (var j = 0; j < steps; j++) {
      var a = k.n.fbm(x * fs, y * fs, 2) * math.pi * curl + rot;
      if (quant) a = (a / (math.pi / 4)).roundToDouble() * math.pi / 4;
      x += math.cos(a) * step;
      y += math.sin(a) * step;
      p.lineTo(x * s, y * s);
    }
  }
  final w = k.px(r.r(.0016, .0035));
  for (var i = 0; i < 4; i++) {
    k.c.drawPath(
      paths[i],
      Paint()
        ..color = (i == 3 ? k.ink : k.cols[i]).withValues(alpha: .75)
        ..style = PaintingStyle.stroke
        ..strokeWidth = w
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }
  k.grain(.3);
}

/// Concentric rings, some broken into arcs, like a record or a radial chart.
void _rings(_K k) {
  final r = k.r, s = k.s;
  k.fill(k.bg);
  final where = r.i(10);
  final c = where < 5
      ? k.o(.5, .5)
      : where < 8
      ? k.o(r.pick([0.0, 1.0]), r.pick([0.0, 1.0]))
      : k.o(r.r(-.3, 1.3), r.pick([-0.25, 1.25]));
  final maxR = s * 1.6;
  var rad = where < 5 && r.p(.5) ? s * r.r(.04, .12) : 0.0;
  final unit = r.r(.01, .03);
  final palette = [...k.cols, k.ink];
  var ci = r.i(4);
  if (rad > 0) k.c.drawCircle(c, rad, Paint()..color = k.cols[2]);
  while (rad < maxR) {
    final w = s * unit * r.pick([1.0, 1.0, 2.0, 3.0, .4]);
    final col = palette[ci = (ci + 1 + r.i(2)) % 4];
    final p = Paint()
      ..color = col.withValues(alpha: r.r(.7, 1))
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * r.r(.4, .9);
    final rect = Rect.fromCircle(center: c, radius: rad + w / 2);
    if (r.p(.35)) {
      final segs = 1 + r.i(5), rot = r.r(0, math.pi * 2);
      for (var i = 0; i < segs; i++) {
        final a = rot + i * math.pi * 2 / segs;
        k.c.drawArc(rect, a, math.pi * 2 / segs * r.r(.3, .85), false, p);
      }
    } else if (r.p(.85)) {
      k.c.drawCircle(c, rad + w / 2, p);
    }
    rad += w;
  }
  k.grain(.3);
}

/// Stripes pushed around by a displacement warp.
void _stripes(_K k) {
  final r = k.r, s = k.s;
  k.fill(k.bg);
  final ang = r.pick([0.0, 0, 90, 45, -30, 15]) * math.pi / 180;
  final e1 = Offset(math.cos(ang), math.sin(ang)), e2 = Offset(-math.sin(ang), math.cos(ang));
  final n = 8 + r.i(20), w = 1.5 / n;
  final mode = r.i(3), amp = r.r(.04, .14), f = r.r(4, 12), ph = r.r(0, 6), fs = r.r(1, 2.5);
  final bx = r.r(-.3, .3), by = r.r(-.3, .3);
  final two = r.p(.5);
  double warp(double u, double v) => switch (mode) {
    0 => amp * math.sin(v * f + ph + u * 2),
    1 => amp * 1.6 * k.n.fbm(u * fs + 3, v * fs),
    _ => amp * 2.5 * math.exp(-((u - bx) * (u - bx) + (v - by) * (v - by)) * 8),
  };
  const m = 70;
  Offset pt(double u, double v) {
    final uu = u + warp(u, v);
    return Offset(.5 + uu * e1.dx + v * e2.dx, .5 + uu * e1.dy + v * e2.dy) * s;
  }

  for (var i = 0; i < n; i++) {
    final u0 = -.75 + i * w, u1 = u0 + w;
    final col = two ? (i.isEven ? k.cols[2] : k.bg) : k.ramp((i % 6) / 5, toInk: true);
    if (col == k.bg) continue;
    final path = Path()..moveTo(pt(u0, -.75).dx, pt(u0, -.75).dy);
    for (var j = 1; j <= m; j++) {
      final p = pt(u0, -.75 + 1.5 * j / m);
      path.lineTo(p.dx, p.dy);
    }
    for (var j = m; j >= 0; j--) {
      final p = pt(u1, -.75 + 1.5 * j / m);
      path.lineTo(p.dx, p.dy);
    }
    k.c.drawPath(path..close(), Paint()..color = col);
  }
  k.grain(.3);
}

/// Cut paper: layered hills or nested blobs, each casting a soft shadow.
void _paper(_K k) {
  final r = k.r, s = k.s;
  final shadow = _blur(const Color(0x73000000), s * .012);
  final rev = r.p(.5);
  Color layerCol(double t) => k.ramp(rev ? 1 - t : t, toInk: !k.dark && r.p(.2));
  if (r.p(.6)) {
    // Hills.
    k.vgradient(k.bg, Color.lerp(k.bg, k.cols[0], .5)!);
    if (r.p(.6)) k.c.drawCircle(k.o(r.r(.2, .8), r.r(.15, .35)), s * r.r(.08, .15), Paint()..color = k.ink.withValues(alpha: .9));
    final n = 4 + r.i(4), f = r.r(1.5, 4), amp = r.r(.05, .14);
    for (var i = 0; i < n; i++) {
      final base = .3 + i * (.62 / n);
      final path = Path()..moveTo(0, s);
      for (var j = 0; j <= 60; j++) {
        final x = j / 60;
        path.lineTo(x * s, (base + amp * k.n.fbm(x * f, i * 3.7, 2)) * s);
      }
      path
        ..lineTo(s, s)
        ..close();
      k.c.drawPath(path.shift(Offset(0, -s * .006)), shadow);
      k.c.drawPath(path, Paint()..color = layerCol(i / (n - 1)));
    }
  } else {
    // Nested blobs.
    k.fill(k.bg);
    final n = 5 + r.i(4), cx = r.r(.35, .65), cy = r.r(.35, .65), wob = r.r(.04, .1);
    final k1 = 2 + r.i(2), k2 = 3 + r.i(3), p1 = r.r(0, 6), p2 = r.r(0, 6), drift = r.r(.1, .5);
    for (var i = 0; i < n; i++) {
      final rad = .75 * (1 - i / n);
      final path = Path();
      for (var j = 0; j <= 120; j++) {
        final a = j / 120 * math.pi * 2;
        final rr = rad * (1 + wob * (.6 * math.sin(a * k1 + p1 + i * drift) + .4 * math.sin(a * k2 + p2 - i * drift)));
        final p = k.o(cx + math.cos(a) * rr, cy + math.sin(a) * rr);
        j == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
      }
      path.close();
      k.c.drawPath(path.shift(Offset(s * .006, s * .01)), shadow);
      k.c.drawPath(path, Paint()..color = layerCol(i / (n - 1)));
    }
  }
  k.grain(.4);
}

/// Pixel sort: a sun over a gradient, melting into sorted colour streaks, with
/// a few slices knocked out of line.
void _glitch(_K k) {
  final r = k.r, s = k.s;
  final stops = [k.bg, k.cols[0], k.cols[1], k.cols[2], k.ink]..length = 3 + r.i(3);
  final pos = [for (var i = 0; i < stops.length; i++) i / (stops.length - 1)];
  final sunX = r.r(.3, .7), sunY = r.r(.25, .5), sunR = r.r(.14, .26);
  final sunCol = k.cols[1 + r.i(2)], sunEnd = Color.lerp(sunCol, k.ink, .6)!;
  Color bgAt(double y) {
    final t = y.clamp(0.0, 1.0) * (stops.length - 1);
    final i = t.floor().clamp(0, stops.length - 2);
    return Color.lerp(stops[i], stops[i + 1], t - i)!;
  }

  Color at(double x, double y) {
    final dx = x - sunX, dy = y - sunY;
    if (dx * dx + dy * dy < sunR * sunR) return Color.lerp(sunCol, sunEnd, (y - sunY + sunR) / (2 * sunR))!;
    return bgAt(y);
  }

  // The whole scene turned a quarter (or half) turn sometimes: sideways or rising melts.
  final turn = r.pick([0, 0, 0, 1, 2, 3]);
  k.c
    ..save()
    ..translate(s / 2, s / 2)
    ..rotate(turn * math.pi / 2)
    ..translate(-s / 2, -s / 2);
  // Kept as rects and paints, so a knocked-out slice redraws only what it
  // crosses (replaying the whole scene per slice was slow on Impeller).
  final bgPaint = Paint()..shader = ui.Gradient.linear(Offset.zero, Offset(0, s), stops, pos);
  final sunRect = Rect.fromCircle(center: k.o(sunX, sunY), radius: sunR * s);
  final sunPaint = Paint()..shader = ui.Gradient.linear(k.o(0, sunY - sunR), k.o(0, sunY + sunR), [sunCol, sunEnd]);
  final cuts = <(Rect, Paint)>[];
  if (r.p(.4)) {
    // Synthwave cuts through the lower half of the sun.
    for (var i = 0; i < 5; i++) {
      final y = sunY + sunR * (.1 + i * .19);
      cuts.add((Rect.fromLTWH((sunX - sunR) * s, y * s, sunR * 2 * s, sunR * .035 * (i + 1) * s), Paint()..color = bgAt(y)));
    }
  }
  // The melt: each column of the sun, sorted by brightness, dragged down.
  final streaks = <(Rect, List<Color>)>[];
  final cw = 1 / r.r(70, 150), melt = r.r(.2, .55), fs = r.r(3, 9);
  for (var x = sunX - sunR; x < sunX + sunR; x += cw) {
    final dx = x + cw / 2 - sunX;
    if (dx.abs() >= sunR) continue;
    final half = math.sqrt(sunR * sunR - dx * dx);
    final len = melt * (.25 + .75 * (.5 + .5 * k.n.at(x * fs, 3.3))) * (r.p(.12) ? 1.7 : 1);
    final y0 = sunY + half * r.r(-.6, .3), y1 = sunY + half + len;
    final cs = [for (var i = 0; i < 8; i++) at(x + cw / 2, y0 + (y1 - y0) * i / 7)]
      ..sort((a, b) => b.computeLuminance().compareTo(a.computeLuminance()));
    streaks.add((Rect.fromLTRB(x * s, y0 * s, (x + cw) * s + .5, y1 * s), cs));
  }
  void scene(Rect band) {
    k.c.drawRect(k.all.intersect(band), bgPaint);
    if (sunRect.overlaps(band)) k.c.drawOval(sunRect, sunPaint);
    for (final (rect, paint) in cuts) {
      if (rect.overlaps(band)) k.c.drawRect(rect, paint);
    }
    // Streaks as one mesh with vertex colours: a gradient shader per streak
    // cost ~1 ms each on Impeller.
    final pos = <double>[], col = <int>[];
    for (final (rect, cs) in streaks) {
      if (!rect.overlaps(band)) continue;
      for (var i = 0; i < 7; i++) {
        final ya = rect.top + rect.height * i / 7, yb = rect.top + rect.height * (i + 1) / 7;
        final a = cs[i].toARGB32(), b = cs[i + 1].toARGB32();
        pos.addAll([rect.left, ya, rect.right, ya, rect.right, yb, rect.left, ya, rect.right, yb, rect.left, yb]);
        col.addAll([a, a, b, a, b, b]);
      }
    }
    if (pos.isNotEmpty) {
      k.c.drawVertices(
        ui.Vertices.raw(ui.VertexMode.triangles, Float32List.fromList(pos), colors: Int32List.fromList(col)),
        BlendMode.dst,
        Paint(),
      );
    }
  }

  scene(k.all);
  // Slices knocked sideways.
  for (var i = 0, n = 2 + r.i(4); i < n; i++) {
    final y = r.r(.05, .9), h = r.r(.008, .05), dx = r.r(-.07, .07) * s;
    final band = Rect.fromLTWH(-dx, y * s, s, h * s);
    k.c
      ..save()
      ..clipRect(band.shift(Offset(dx, 0)))
      ..translate(dx, 0);
    scene(band);
    k.c.restore();
  }
  if (r.p(.4)) {
    final lines = Path();
    for (var y = 0.0; y < 1; y += 3 / math.max(s, 96)) {
      lines.addRect(Rect.fromLTWH(0, y * s, s, math.max(1, s / 512)));
    }
    k.c.drawPath(lines, Paint()..color = const Color(0x14000000));
  }
  k.c.restore();
  k.grain(.3);
}

/// Aurora: soft curtains of light over a night sky.
void _aurora(_K k) {
  final r = k.r, s = k.s;
  k.vgradient(k.bg, Color.lerp(k.bg, k.cols[0], .7)!);
  // Stars.
  final stars = <double>[];
  for (var i = 0, n = 40 + r.i(100); i < n; i++) {
    stars
      ..add(r.d() * s)
      ..add(r.d() * r.d() * s);
  }
  k.c.drawRawPoints(
    ui.PointMode.points,
    Float32List.fromList(stars),
    Paint()
      ..color = k.ink.withValues(alpha: .6)
      ..strokeWidth = k.px(.0025, .8)
      ..strokeCap = StrokeCap.round,
  );
  for (var b = 0, n = 2 + r.i(3); b < n; b++) {
    final col = k.cols[1 + r.i(2)];
    final y0 = r.r(.35, .75), amp = r.r(.08, .2), f = r.r(.8, 2), h = r.r(.18, .42), o = r.r(0, 40);
    const m = 60;
    double yAt(double x) => y0 + amp * k.n.fbm(x * f + o, b * 2.1, 2);
    for (var l = 0; l < 6; l++) {
      final hl = h * (1 - l / 6);
      final path = Path()..moveTo(-.05 * s, yAt(-.05) * s);
      for (var j = 0; j <= m; j++) {
        final x = -.05 + 1.1 * j / m;
        path.lineTo(x * s, yAt(x) * s);
      }
      for (var j = m; j >= 0; j--) {
        final x = -.05 + 1.1 * j / m;
        final ray = .5 + .5 * k.n.at(x * 24 + o, l * 1.3);
        path.lineTo(x * s, (yAt(x) - hl * ray) * s);
      }
      k.c.drawPath(path..close(), _blur(col.withValues(alpha: .12), s * .012)..blendMode = BlendMode.plus);
    }
    final edge = Path()..moveTo(-.05 * s, yAt(-.05) * s);
    for (var j = 0; j <= m; j++) {
      final x = -.05 + 1.1 * j / m;
      edge.lineTo(x * s, yAt(x) * s);
    }
    k.c.drawPath(
      edge,
      _blur(Color.lerp(col, k.ink, .4)!.withValues(alpha: .5), s * .006)
        ..style = PaintingStyle.stroke
        ..strokeWidth = k.px(.006)
        ..blendMode = BlendMode.plus,
    );
  }
  if (r.p(.5)) {
    // A dark horizon.
    final path = Path()..moveTo(0, s);
    final hy = r.r(.82, .9), f = r.r(2, 5);
    for (var j = 0; j <= 40; j++) {
      final x = j / 40;
      path.lineTo(x * s, (hy + .04 * k.n.fbm(x * f, 9.1, 2)) * s);
    }
    k.c.drawPath(
      path
        ..lineTo(s, s)
        ..close(),
      Paint()..color = Color.lerp(k.bg, const Color(0xFF000000), .5)!,
    );
  }
  k.grain(.35);
}

// ---------------------------------------------------------------- text

void _initials(_K k, String text) {
  final s = k.s;
  final tp = TextPainter(
    text: TextSpan(
      text: text.toUpperCase(),
      style: TextStyle(
        fontFamily: 'Inter',
        fontWeight: FontWeight.w600,
        fontSize: s * .085,
        letterSpacing: s * .004,
        color: (k.dark ? const Color(0xFFFFFFFF) : const Color(0xFF111111)).withValues(alpha: .88),
        shadows: [Shadow(color: const Color(0x55000000), blurRadius: s * .02)],
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  tp.paint(k.c, Offset(s * .07, s * .93 - tp.height));
  tp.dispose();
}

/// The Lumen "L with two sound bars", small, bottom right.
void _mark(_K k) {
  final s = k.s, m = s * .075, x = s * .93 - m, y = s * .93 - m, u = m / 296;
  final p = Paint()..color = (k.dark ? const Color(0xFFFFFFFF) : const Color(0xFF111111)).withValues(alpha: .85);
  RRect bar(double bx, double by, double w, double h) =>
      RRect.fromRectAndRadius(Rect.fromLTWH(x + (bx - 108) * u, y + (by - 108) * u, w * u, h * u), Radius.circular(math.min(w, h) * u / 2));
  k.c
    ..drawRRect(bar(140, 108, 64, 296), p)
    ..drawRRect(bar(140, 340, 236, 64), p)
    ..drawRRect(bar(240, 212, 48, 100), p)
    ..drawRRect(bar(316, 158, 48, 154), p);
}

