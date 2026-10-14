// Painterly cover styles: brush strokes (starry, garden) and flat picture-book scenes (storybook).
// Part of generative_cover.dart so they share its seeded random, noise and grain.
part of 'generative_cover.dart';

// ---------------------------------------------------------------- brush strokes

/// Thousands of brush strokes collected into one vertex mesh (Impeller draws one mesh fast).
/// Each stroke is a ribbon: lit edge to shaded edge across its width (a rounded, impasto look),
/// a dry, slightly transparent tail, and ~1 device px soft fringes, because vertices get no
/// anti-aliasing. Points are in unit coordinates (0..1).
class _Brush {
  _Brush(this.s) : f = 1.0 / s;
  final double s, f;
  var _p = Float32List(1 << 18);
  var _c = Int32List(1 << 17);
  var _n = 0;
  final _x = Float64List(64), _y = Float64List(64);
  var _m = 0;

  // Light from the top left.
  static const _lx = -.55, _ly = -.83;

  void _v(double x, double y, int c) {
    _p[2 * _n] = x * s;
    _p[2 * _n + 1] = y * s;
    _c[_n++] = c;
  }

  void _quad(double ax, double ay, int ac, double bx, double by, int bc, double cx, double cy, int cc, double dx, double dy, int dc) {
    _v(ax, ay, ac);
    _v(bx, by, bc);
    _v(cx, cy, cc);
    _v(ax, ay, ac);
    _v(cx, cy, cc);
    _v(dx, dy, dc);
  }

  /// Starts a stroke at (x, y); add points with [to], then [end] it.
  void start(double x, double y) {
    _m = 0;
    to(x, y);
  }

  void to(double x, double y) {
    if (_m == _x.length) return;
    _x[_m] = x;
    _y[_m++] = y;
  }

  /// Draws the stroke [w] wide (unit), from the [lit] edge to the [shade] edge.
  void end(double w, Color lit, Color shade, {double tail = .55}) {
    final m = _m;
    if (m < 2) return;
    if (_n + m * 18 > _c.length) {
      _c = Int32List(_c.length * 2)..setAll(0, _c);
      _p = Float32List(_p.length * 2)..setAll(0, _p);
    }
    // Which side faces the light (once per stroke, so it never flips midway).
    var nx = -(_y[m - 1] - _y[0]), ny = _x[m - 1] - _x[0];
    var a = lit.toARGB32(), b = shade.toARGB32();
    if (nx * _lx + ny * _ly < 0) {
      final t = a;
      a = b;
      b = t;
    }
    final a0 = a & 0xFFFFFF, b0 = b & 0xFFFFFF;
    final fw = math.max(f, w * .12);
    double pl = 0, pr = 0, plf = 0, prf = 0, ql = 0, qr = 0, qlf = 0, qrf = 0; // previous edge points
    int pa = 0, pb = 0;
    for (var i = 0; i < m; i++) {
      final i0 = i == 0 ? 0 : i - 1, i1 = i == m - 1 ? m - 1 : i + 1;
      var tx = _x[i1] - _x[i0], ty = _y[i1] - _y[i0];
      final len = math.sqrt(tx * tx + ty * ty);
      if (len > 0) {
        tx /= len;
        ty /= len;
      }
      nx = -ty;
      ny = tx;
      final t = i / (m - 1);
      final hw = w * .5 * (.4 + .6 * math.sin(math.pi * (.1 + .8 * t)));
      final alpha = (255 * (1 - (1 - tail) * t * t * t)).round() << 24;
      final ca = a0 | alpha, cb = b0 | alpha;
      final x = _x[i], y = _y[i];
      final lx = x + nx * hw, ly = y + ny * hw, rx = x - nx * hw, ry = y - ny * hw;
      final lfx = lx + nx * fw, lfy = ly + ny * fw, rfx = rx - nx * fw, rfy = ry - ny * fw;
      if (i > 0) {
        _quad(plf, qlf, a0, pl, ql, pa, lx, ly, ca, lfx, lfy, a0);
        _quad(pl, ql, pa, pr, qr, pb, rx, ry, cb, lx, ly, ca);
        _quad(pr, qr, pb, prf, qrf, b0, rfx, rfy, b0, rx, ry, cb);
      }
      pl = lx;
      ql = ly;
      pr = rx;
      qr = ry;
      plf = lfx;
      qlf = lfy;
      prf = rfx;
      qrf = rfy;
      pa = ca;
      pb = cb;
    }
  }

  /// A short straight dab of paint.
  void dab(double x, double y, double angle, double len, double w, Color lit, Color shade) {
    final dx = math.cos(angle) * len / 2, dy = math.sin(angle) * len / 2;
    start(x - dx, y - dy);
    to(x, y);
    to(x + dx, y + dy);
    end(w, lit, shade, tail: .8);
  }

  /// Paints everything so far (in order) and starts an empty layer.
  void flush(Canvas c) {
    if (_n == 0) return;
    c.drawVertices(
      ui.Vertices.raw(ui.VertexMode.triangles, Float32List.sublistView(_p, 0, _n * 2), colors: Int32List.sublistView(_c, 0, _n)),
      BlendMode.dst,
      Paint(),
    );
    _n = 0;
  }
}

/// [c] a little lighter (t > 0) or darker (t < 0).
Color _tone(Color c, double t) => t >= 0 ? Color.lerp(c, const Color(0xFFFFFFFF), t)! : Color.lerp(c, const Color(0xFF000000), -t)!;

Color _lerp(Color a, Color b, double t) => Color.lerp(a, b, t.clamp(0.0, 1.0))!;

/// A colour along a list of stops (t 0..1).
Color _ramp(List<Color> l, double t) {
  t = t.clamp(0.0, 1.0) * (l.length - 1);
  final i = t.floor().clamp(0, l.length - 2);
  return Color.lerp(l[i], l[i + 1], t - i)!;
}

// ---------------------------------------------------------------- starry swirl

/// One mood of the starry style.
class _Sky {
  const _Sky(this.sky, this.swirl, this.orb, this.halo, this.ground, this.tree, this.lights, {this.day = false});
  final List<Color> sky; // top .. horizon
  final Color swirl; // the light bands in the swirls (clouds by day)
  final Color orb, halo; // moon or sun: core and halo
  final List<Color> ground; // dark .. light
  final List<Color> tree; // the cypress, dark .. light
  final Color lights; // windows and reflections
  final bool day;
}

const _night = [
  _Sky(
    [Color(0xFF0B1E5B), Color(0xFF1A3F95), Color(0xFF3567B5), Color(0xFF7FA6D6)],
    Color(0xFFCADDEB),
    Color(0xFFF7E9A6),
    Color(0xFFE9B53A),
    [Color(0xFF0D1C30), Color(0xFF1C3A5A), Color(0xFF2F5F78), Color(0xFF4E8070)],
    [Color(0xFF0A1712), Color(0xFF1B3426), Color(0xFF365A3C)],
    Color(0xFFF5CF4A),
  ),
  _Sky(
    [Color(0xFF08203A), Color(0xFF134C6A), Color(0xFF2A7A8C), Color(0xFF9CC8C0)],
    Color(0xFFD7E9DC),
    Color(0xFFF9EDB4),
    Color(0xFFE4C04E),
    [Color(0xFF0B1A24), Color(0xFF16384A), Color(0xFF295C66), Color(0xFF5E8A6A)],
    [Color(0xFF07140F), Color(0xFF173024), Color(0xFF2F5238)],
    Color(0xFFF2C94C),
  ),
  _Sky(
    [Color(0xFF120F45), Color(0xFF283C9A), Color(0xFF4B6FC4), Color(0xFFA4B9E0)],
    Color(0xFFE6E2F0),
    Color(0xFFFFF0B8),
    Color(0xFFF0A93A),
    [Color(0xFF100F2A), Color(0xFF232E5C), Color(0xFF3B4F86), Color(0xFF61709A)],
    [Color(0xFF0B0E1C), Color(0xFF1C2638), Color(0xFF34484E)],
    Color(0xFFFFD25A),
  ),
];
const _dusk = [
  _Sky(
    [Color(0xFF2A2266), Color(0xFF5B3F8F), Color(0xFFC0679A), Color(0xFFF2A766)],
    Color(0xFFF7CDA0),
    Color(0xFFFFE9A8),
    Color(0xFFF2963F),
    [Color(0xFF1B1434), Color(0xFF382656), Color(0xFF5C3E6C), Color(0xFF85587A)],
    [Color(0xFF110C1E), Color(0xFF281F3E), Color(0xFF43355E)],
    Color(0xFFFFC85A),
  ),
  _Sky(
    [Color(0xFF16254F), Color(0xFF3D4A8E), Color(0xFFD27D6F), Color(0xFFF6C27A)],
    Color(0xFFFAD9A8),
    Color(0xFFFFF1C0),
    Color(0xFFF07F3C),
    [Color(0xFF14182C), Color(0xFF2B2F50), Color(0xFF524868), Color(0xFF8A6070)],
    [Color(0xFF0C0F1A), Color(0xFF1E2434), Color(0xFF3A3E52)],
    Color(0xFFFFCF66),
  ),
];
const _wheat = [
  _Sky(
    [Color(0xFF2C6CB0), Color(0xFF4C93CD), Color(0xFF86BFDF), Color(0xFFD5E8E6)],
    Color(0xFFF5F2E6),
    Color(0xFFFFF6C4),
    Color(0xFFF3D04C),
    [Color(0xFF8E5F1C), Color(0xFFCB9028), Color(0xFFE6BC45), Color(0xFFF4DC7C)],
    [Color(0xFF10251A), Color(0xFF24442C), Color(0xFF4C6B34)],
    Color(0xFFFFFFFF),
    day: true,
  ),
  _Sky(
    [Color(0xFF3B78A8), Color(0xFF63A1C4), Color(0xFFA8D0D8), Color(0xFFEDE7CF)],
    Color(0xFFFFFBEF),
    Color(0xFFFFF2B0),
    Color(0xFFF0B83C),
    [Color(0xFF7C5A1E), Color(0xFFB8862C), Color(0xFFDDB04A), Color(0xFFF1D888)],
    [Color(0xFF15281C), Color(0xFF2B4A2E), Color(0xFF5A7438)],
    Color(0xFFFFFFFF),
    day: true,
  ),
];

/// Van Gogh-like night (or dusk, or a golden wheat field): thick curved strokes following a
/// swirling flow field, a moon or sun with ringed halo, rolling hills, sometimes a cypress
/// flame, a village with lit windows or a river with reflections.
void _starry(_K k) {
  final r = k.r, n = k.n;
  final mode = r.pick(const [0, 0, 0, 1, 1, 2, 2, 3, 3]); // night hills, night river, dusk, wheat field
  final pal = r.pick(switch (mode) { 2 => _dusk, 3 => _wheat, _ => _night });
  final b = _Brush(k.s);
  final hor = mode == 1 ? r.r(.5, .62) : r.r(.58, .72); // the horizon
  final treeSide = r.p(.5) ? -1.0 : 1.0;
  final hasTree = mode != 1 && r.p(.6);
  final treeX = .5 + treeSide * r.r(.24, .36);

  // Underpainting so no gap between strokes shows canvas.
  k.c.drawRect(k.all, Paint()..shader = ui.Gradient.linear(Offset.zero, Offset(0, k.s * hor), [_tone(pal.sky[0], -.35), _tone(pal.sky[2], -.3)]));
  k.c.drawRect(Rect.fromLTRB(0, k.s * (hor - .02), k.s, k.s), Paint()..color = _tone(pal.ground[mode == 1 ? 0 : 1], -.3));

  // The moon or sun, opposite the tree.
  final orbR = mode == 3 || mode == 2 ? r.r(.055, .075) : r.r(.04, .06);
  final orbX = .5 - treeSide * r.r(.12, .3), orbY = mode == 2 ? r.r(hor - .3, hor - .14) : r.r(.12, hor * .45);
  final crescent = !pal.day && mode != 2 && r.p(.6);

  // Swirls: one big one and a few small, plus a wavy band of wind across the sky.
  final vort = <List<double>>[];
  for (var i = 0, nv = 1 + r.i(3); i < nv; i++) {
    final big = i == 0;
    vort.add([r.r(.15, .85), r.r(.12, hor - .15), big ? r.r(.13, .2) : r.r(.06, .11), r.p(.5) ? 1 : -1]);
  }
  final windY = r.r(.25, hor - .12), windA = r.r(.02, .06), windF = r.r(4, 9), windP = r.r(0, 6), windOn = r.p(.75);
  final wobble = r.r(.5, .9), turn = r.r(-.25, .25);

  // Direction of the sky's flow at (x, y).
  (double, double) skyFlow(double x, double y) {
    final a0 = turn + wobble * n.fbm(x * 2.3 + 11, y * 2.3, 2);
    var dx = math.cos(a0), dy = math.sin(a0);
    if (windOn) {
      final cy = windY + windA * math.sin(x * windF + windP), slope = windA * windF * math.cos(x * windF + windP);
      final w = 2.2 * math.exp(-math.pow((y - cy) / .06, 2));
      final l = math.sqrt(1 + slope * slope);
      dx += w / l;
      dy += w * slope / l;
    }
    for (final v in vort) {
      final ox = x - v[0], oy = y - v[1], d = math.sqrt(ox * ox + oy * oy) + 1e-6;
      final w = 3 * math.exp(-math.pow(d / v[2], 2));
      dx += w * (-oy / d * v[3] - ox / d * .3);
      dy += w * (ox / d * v[3] - oy / d * .3);
    }
    final l = math.sqrt(dx * dx + dy * dy) + 1e-9;
    return (dx / l, dy / l);
  }

  // Sky colour at (x, y): a gradient, lighter in swirl bands and along the wind.
  Color skyCol(double x, double y) {
    var c = _ramp(pal.sky, y / hor + .12 * n.at(x * 3 + 5, y * 3));
    var light = 0.0;
    for (final v in vort) {
      final ox = x - v[0], oy = y - v[1], d = math.sqrt(ox * ox + oy * oy);
      if (d > v[2] * 1.6) continue;
      final band = math.sin(d / v[2] * math.pi * 3.2 + math.atan2(oy, ox) * v[3] * .5);
      light = math.max(light, (band * .5 + .25) * (1 - d / (v[2] * 1.6)) * 1.6);
    }
    if (windOn) {
      final cy = windY + windA * math.sin(x * windF + windP);
      light = math.max(light, .75 * math.exp(-math.pow((y - cy) / .035, 2)) * (.6 + .4 * n.at(x * 9, 3.3)));
    }
    // Glow around the orb.
    final od = math.sqrt(math.pow(x - orbX, 2) + math.pow(y - orbY, 2));
    c = _lerp(c, pal.halo, .55 * math.exp(-math.pow((od - orbR) / (orbR * 2.5), 2)) * (pal.day ? .6 : 1));
    return _lerp(c, pal.swirl, light.clamp(0.0, .85));
  }

  void flowStroke(double x, double y, double len, double w, Color col, (double, double) Function(double, double) flow, [int steps = 5]) {
    final st = len / steps;
    // Centre the stroke on (x, y): walk back half, then forward.
    for (var i = 0; i < steps ~/ 2; i++) {
      final (dx, dy) = flow(x, y);
      x -= dx * st;
      y -= dy * st;
    }
    b.start(x, y);
    for (var i = 0; i < steps; i++) {
      final (dx, dy) = flow(x, y);
      x += dx * st;
      y += dy * st;
      b.to(x, y);
    }
    b.end(w, _tone(col, .2), _tone(col, -.24));
  }

  // 1. The sky, two layers of strokes.
  for (var pass = 0; pass < 2; pass++) {
    final sp = pass == 0 ? .03 : .021;
    for (var gy = -.01; gy < hor + .02; gy += sp) {
      for (var gx = -.01; gx < 1.02; gx += sp) {
        final x = gx + r.r(-.5, .5) * sp, y = gy + r.r(-.5, .5) * sp;
        var c = _tone(skyCol(x + r.r(-.03, .03), y + r.r(-.03, .03)), r.r(-.1, .1));
        if (r.p(.07)) c = _lerp(c, r.p(.5) ? pal.swirl : pal.sky[0], .45);
        flowStroke(x, y, r.r(.04, .07), r.r(.013, .019) * (pass == 0 ? 1.3 : 1), c, skyFlow);
      }
    }
  }

  // 2. Haloes: rings of short tangential strokes, alternately lighter, fading into the sky.
  void halo(double cx, double cy, double inner, double outer, Color core, double w) {
    var ring = 0;
    for (var rad = inner; rad < outer; rad += w * .9, ring++) {
      final t = (rad - inner) / (outer - inner);
      final cnt = math.max(6, (2 * math.pi * rad / (w * 2.4)).round());
      final off = r.d() * math.pi * 2;
      for (var j = 0; j < cnt; j++) {
        if (r.d() < t * .55) continue;
        final a0 = off + j / cnt * math.pi * 2 + r.r(-.1, .1), a1 = a0 + (w * 3) / rad;
        final x = cx + math.cos(a0) * rad, y = cy + math.sin(a0) * rad;
        var c = _lerp(core, skyCol(x, y), math.pow(t, 1.2).toDouble());
        if (ring.isOdd) c = _lerp(c, pal.day ? pal.swirl : const Color(0xFFFFF8D8), .3 * (1 - t));
        b.start(x, y);
        for (var q = 1; q <= 3; q++) {
          final a = a0 + (a1 - a0) * q / 3;
          b.to(cx + math.cos(a) * rad, cy + math.sin(a) * rad);
        }
        c = _tone(c, r.r(-.06, .06));
        b.end(w, _tone(c, .2), _tone(c, -.15));
      }
    }
  }

  halo(orbX, orbY, orbR * 1.05, orbR * (pal.day ? 2.2 : 2.6), pal.halo, .014);
  b.flush(k.c);
  k.c.drawCircle(k.o(orbX, orbY), orbR * 1.08 * k.s, Paint()..color = crescent ? pal.halo : _lerp(pal.halo, pal.orb, .6));
  // The orb itself: rings of strokes inward (a crescent moon: a bright sliver on an amber disc).
  for (var rad = orbR; rad > .004; rad -= .011) {
    final cnt = math.max(4, (2 * math.pi * rad / .022).round());
    for (var j = 0; j < cnt; j++) {
      final a = j / cnt * math.pi * 2 + r.d();
      final x = orbX + math.cos(a) * rad, y = orbY + math.sin(a) * rad;
      var c = _lerp(pal.halo, pal.orb, .55 + .45 * (1 - rad / orbR));
      if (crescent) {
        final ox = x - (orbX + orbR * .38), oy = y - (orbY - orbR * .2);
        c = ox * ox + oy * oy < orbR * orbR * .8 ? _tone(pal.halo, -.06) : pal.orb;
      }
      b.dab(x, y, a + math.pi / 2, .028, .015, _tone(c, .18), _tone(c, -.1));
    }
  }
  if (!pal.day) {
    // Stars.
    final ns = mode == 2 ? 2 + r.i(4) : 5 + r.i(8);
    for (var i = 0; i < ns; i++) {
      final x = r.r(.05, .95), y = r.r(.04, hor - .1);
      if ((x - orbX).abs() < orbR * 3 && (y - orbY).abs() < orbR * 3) continue;
      if (hasTree && (x - treeX).abs() < .1) continue;
      final sr = r.r(.008, .02);
      halo(x, y, sr, sr * r.r(2.2, 3), _lerp(pal.orb, pal.halo, .3), .011);
      for (var j = 0; j < 5; j++) {
        final a = r.d() * math.pi * 2;
        b.dab(x + math.cos(a) * sr * .4, y + math.sin(a) * sr * .4, a, sr * 1.2, .011, const Color(0xFFFFFCE8), pal.orb);
      }
    }
  }
  b.flush(k.c);

  // 3. The ground.
  if (mode == 1) {
    _river(k, b, pal, hor);
  } else {
    final layers = 2 + r.i(2);
    for (var l = 0; l < layers; l++) {
      final base = hor + l * (.12 + r.r(0, .05)), amp = r.r(.025, .07), f = r.r(1.5, 3.5), o = r.r(0, 50);
      double top(double x) => base + amp * n.fbm(x * f + o, l * 3.1, 2) - (l == 0 ? .02 : 0);
      final far = 1 - l / layers; // 1 = farthest
      // Each hill its own colour: alternately lighter and darker, the far ones hazier.
      var tl = (mode == 3 ? .35 : .2) + .5 * (1 - far) + (l.isOdd ? .12 : -.05) + r.r(-.08, .08);
      if (pal.day && l == 0) tl = -1; // distant blue hills
      Color groundAt(double x, double y) {
        final depth = y - top(x);
        if (tl < 0) return _lerp(pal.sky[1], pal.ground[0], .25 + .2 * n.at(x * 8, y * 8));
        var t = tl + .28 * n.fbm(x * 5 + l * 7, y * 5, 2);
        if (mode == 3) t += .12 * math.sin((x * 1.5 + y * 7) * math.pi) + .3 * ((y - hor) / (1 - hor) - .3);
        var c = _ramp(pal.ground, t);
        if (depth < .035) c = _lerp(_tone(c, .15), pal.sky[2], mode == 3 ? 0 : .22); // lit ridge
        return c;
      }

      final path = Path()..moveTo(0, k.s);
      for (var j = 0; j <= 40; j++) {
        path.lineTo(j / 40 * k.s, top(j / 40) * k.s);
      }
      k.c.drawPath(
        path
          ..lineTo(k.s, k.s)
          ..close(),
        Paint()..color = _tone(groundAt(.5, base + .1), -.3),
      );
      (double, double) flow(double x, double y) {
        final slope = (top(x + .01) - top(x - .01)) / .02 * math.exp(-(y - top(x)) * 5);
        final a = math.atan(slope) + (mode == 3 ? 1.1 : .55) * n.fbm(x * 4 + l, y * 4 + 7, 2) + (mode == 3 ? -.6 : 0);
        return (math.cos(a), math.sin(a));
      }

      const sp = .02;
      for (var gy = base - amp - .02; gy < 1.02; gy += sp) {
        for (var gx = -.01; gx < 1.02; gx += sp) {
          final x = gx + r.r(-.5, .5) * sp, y = gy + r.r(-.5, .5) * sp;
          if (y < top(x) + .006) continue;
          var c = groundAt(x, y);
          if (mode == 3 && r.p(.1)) c = r.pick(const [Color(0xFF6F8A3A), Color(0xFFE07B28), Color(0xFF5E8FA8)]); // green, orange, blue among the wheat
          if (mode != 3 && r.p(.06)) c = _lerp(c, pal.sky[2], .4);
          flowStroke(x, y, r.r(.035, .06), r.r(.012, .018), _tone(c, r.r(-.1, .1)), flow, 4);
        }
      }
      if (l == 0 && mode != 3 && r.p(.65)) _village(k, b, pal, top, treeX, hasTree);
      b.flush(k.c);
    }
  }

  // 4. The cypress: a dark flame.
  if (hasTree) {
    final topY = r.r(.06, .28), mw = r.r(.06, .1), ph = r.r(0, 6), ph2 = r.r(0, 6);
    double cxAt(double y) => treeX + .02 * math.sin(y * 9 + ph2) * (1 - y);
    double wAt(double y) {
      final t = ((1.02 - y) / (1.02 - topY)).clamp(0.0, 1.0); // 0 bottom, 1 tip
      return mw * math.pow(1 - t, .75) * (.8 + .2 * math.sin(t * 14 + ph));
    }

    final path = Path()..moveTo((cxAt(1.05) - wAt(1.05)) * k.s, 1.05 * k.s);
    for (var y = 1.05; y > topY; y -= .01) {
      path.lineTo((cxAt(y) - wAt(y)) * k.s, y * k.s);
    }
    path.lineTo(cxAt(topY) * k.s, topY * k.s);
    for (var y = topY; y < 1.05; y += .01) {
      path.lineTo((cxAt(y) + wAt(y)) * k.s, y * k.s);
    }
    k.c.drawPath(path..close(), Paint()..color = pal.tree[0]);
    (double, double) flame(double x, double y) {
      final a = -math.pi / 2 + .7 * math.sin(y * 28 + (x - treeX) * 50 + ph) + (x - cxAt(y)) * 6;
      return (math.cos(a), math.sin(a));
    }

    for (var y = topY; y < 1.04; y += .012) {
      final w = wAt(y);
      for (var x = cxAt(y) - w; x < cxAt(y) + w; x += .014) {
        final px = x + r.r(-.004, .004), py = y + r.r(-.004, .004);
        final edge = ((px - cxAt(py)).abs() / (w + 1e-6)).clamp(0.0, 1.0);
        var c = _ramp(pal.tree, .2 + .7 * r.d() * (1 - edge * .5));
        if (r.p(.06)) c = _lerp(c, pal.sky[2], .5);
        flowStroke(px, py, r.r(.03, .05), r.r(.008, .012), c, flame, 4);
      }
    }
    b.flush(k.c);
  }
  k.grain(.35);
  k.vignette(.3);
}

/// Far shore with lights, and dark water with long wavering reflections.
void _river(_K k, _Brush b, _Sky pal, double hor) {
  final r = k.r, n = k.n, s = k.s;
  final shore = hor + .02;
  // Water.
  for (var gy = shore; gy < 1.02; gy += .013) {
    for (var gx = -.02; gx < 1.02; gx += .022) {
      final x = gx + r.r(-.01, .01), y = gy + r.r(-.004, .004);
      final c = _tone(_ramp(pal.sky, .35 + .55 * ((y - shore) / (1 - shore)) + .3 * n.at(x * 5, y * 12)), r.r(-.12, .06));
      b.start(x - .02, y + r.r(-.003, .003));
      b.to(x, y);
      b.to(x + .022, y + r.r(-.003, .003));
      b.end(r.r(.008, .012), _tone(c, .1), _tone(c, -.15));
    }
  }
  // The far shore: a dark strip with roofs.
  final path = Path()..moveTo(0, (shore + .015) * s);
  for (var x = 0.0; x <= 1.0001; x += .025) {
    final h = .01 + .025 * (.5 + .5 * n.at(x * 14, 2.2)).clamp(0.0, 1.0);
    path
      ..lineTo(x * s, (shore - h) * s)
      ..lineTo((x + .025) * s, (shore - h) * s);
  }
  path
    ..lineTo(s, (shore + .015) * s)
    ..close();
  k.c.drawPath(path, Paint()..color = pal.ground[0]);
  b.flush(k.c);
  // Lights and their reflections.
  for (var i = 0, nl = 6 + r.i(8); i < nl; i++) {
    final x = r.r(.04, .96);
    final col = _lerp(pal.lights, const Color(0xFFF08A2A), r.d() * .5);
    b.dab(x, shore - .01, 0, .012, .012, _tone(col, .3), col);
    final len = r.r(.12, .32);
    for (var y = shore + .012; y < shore + len; y += .016) {
      final t = (y - shore) / len;
      final wdt = r.r(.015, .035) * (1 - t * .5);
      final c = _lerp(col, pal.sky[1], t * .7);
      b.start(x - wdt / 2 + r.r(-.006, .006), y);
      b.to(x + wdt / 2 + r.r(-.006, .006), y + r.r(-.002, .002));
      b.end(.008 * (1 - t * .4), _tone(c, .15), c, tail: .5);
    }
  }
  b.flush(k.c);
}

/// A small village on the first hill: houses, a church spire, lit windows.
void _village(_K k, _Brush b, _Sky pal, double Function(double) top, double treeX, bool hasTree) {
  final r = k.r, s = k.s;
  var x = r.r(.08, .55);
  final end = x + r.r(.25, .4);
  final wall = _lerp(pal.ground[1], pal.sky[1], .25), roof = _lerp(pal.ground[0], pal.ground[2], .3);
  var spire = r.p(.6);
  while (x < end) {
    final w = r.r(.025, .045), h = r.r(.02, .035);
    if (hasTree && (x - treeX).abs() < .08) {
      x += w * 1.2;
      continue;
    }
    final base = top(x + w / 2) + .025;
    final house = Path()
      ..moveTo(x * s, base * s)
      ..lineTo(x * s, (base - h) * s)
      ..lineTo((x + w / 2) * s, (base - h - w * .45) * s)
      ..lineTo((x + w) * s, (base - h) * s)
      ..lineTo((x + w) * s, base * s)
      ..close();
    k.c.drawPath(house, Paint()..color = _tone(wall, r.r(-.1, .1)));
    k.c.drawPath(
      Path()
        ..moveTo((x - w * .08) * s, (base - h + .002) * s)
        ..lineTo((x + w / 2) * s, (base - h - w * .45) * s)
        ..lineTo((x + w * 1.08) * s, (base - h + .002) * s),
      Paint()
        ..color = roof
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1, .006 * s),
    );
    if (spire) {
      spire = false;
      final sx = x + w / 2;
      k.c.drawPath(
        Path()
          ..moveTo((sx - .008) * s, (base - h) * s)
          ..lineTo(sx * s, (base - h - .09) * s)
          ..lineTo((sx + .008) * s, (base - h) * s)
          ..close(),
        Paint()..color = roof,
      );
    }
    for (var i = 0, nw = 1 + r.i(2); i < nw; i++) {
      if (r.p(.3)) continue;
      final wx = x + w * (.25 + .5 * r.d()), wy = base - h * r.r(.3, .6);
      b.dab(wx, wy, 0, .007, .008, const Color(0xFFFFF0A0), pal.lights);
    }
    x += w * r.r(1.05, 1.5);
  }
}

// ---------------------------------------------------------------- storybook

class _Book {
  const _Book(this.sky, this.glow, this.layers, this.light, this.ink, this.cloud, {this.night = true});
  final List<Color> sky; // top, bottom
  final Color glow; // moon or sun
  final List<Color> layers; // far .. near
  final Color light; // windows, lamp
  final Color ink; // details: trunks, birds, outlines
  final Color cloud;
  final bool night;
}

const _books = [
  // lavender dusk
  _Book([Color(0xFF3E3170), Color(0xFFB59BCB)], Color(0xFFFBE9C8),
      [Color(0xFF9A88C2), Color(0xFF7B69AE), Color(0xFF5C4B93), Color(0xFF3F3272), Color(0xFF2A2152)], Color(0xFFFFC86B), Color(0xFF1F173B), Color(0xFFD6C4E6)),
  // starry navy
  _Book([Color(0xFF0E1838), Color(0xFF2C4576)], Color(0xFFF6ECCB),
      [Color(0xFF3F5E8E), Color(0xFF2F4B78), Color(0xFF213A62), Color(0xFF162B4C), Color(0xFF0D1D36)], Color(0xFFFFD27A), Color(0xFF080F24), Color(0xFF51698F)),
  // teal night
  _Book([Color(0xFF0C2733), Color(0xFF2C6A70)], Color(0xFFF4E8C6),
      [Color(0xFF468F83), Color(0xFF337468), Color(0xFF235A54), Color(0xFF16413F), Color(0xFF0D2C2C)], Color(0xFFFFC870), Color(0xFF071C20), Color(0xFF5C978E)),
  // violet night with pink horizon
  _Book([Color(0xFF231A4A), Color(0xFFD08BA8)], Color(0xFFFFF0D6),
      [Color(0xFFA17BB0), Color(0xFF7E5C9E), Color(0xFF5E4386), Color(0xFF412F68), Color(0xFF2A1F4A)], Color(0xFFFFD27E), Color(0xFF180F30), Color(0xFFE8B8C8)),
  // peach sunset
  _Book([Color(0xFFEF9C86), Color(0xFFFBDDB4)], Color(0xFFFFF5DA),
      [Color(0xFFDA9A92), Color(0xFFBE7887), Color(0xFF955A78), Color(0xFF6C4067), Color(0xFF452A4E)], Color(0xFFFFE6A0), Color(0xFF341C3A), Color(0xFFFDE8D6), night: false),
  // mint morning
  _Book([Color(0xFFB5DED3), Color(0xFFF5EED6)], Color(0xFFFFF3C4),
      [Color(0xFF9CCDB8), Color(0xFF72B39C), Color(0xFF4F9480), Color(0xFF357266), Color(0xFF22504A)], Color(0xFFF6AE62), Color(0xFF1A3634), Color(0xFFFFFFFF), night: false),
  // golden hour
  _Book([Color(0xFFF2B266), Color(0xFFFCE5B5)], Color(0xFFFFF8E2),
      [Color(0xFFE2AE6C), Color(0xFFC88A4C), Color(0xFFA0663A), Color(0xFF744630), Color(0xFF4A2D22)], Color(0xFFFFF0B0), Color(0xFF32201A), Color(0xFFFFF1D8), night: false),
  // rose dawn
  _Book([Color(0xFFE9AFC0), Color(0xFFFCE6D4)], Color(0xFFFFF6E8),
      [Color(0xFFE0A4B6), Color(0xFFC287A6), Color(0xFF996B98), Color(0xFF6E4F80), Color(0xFF47355C)], Color(0xFFFFD98A), Color(0xFF2E2140), Color(0xFFFFF2EA), night: false),
];

/// Flat picture-book scenes: layered hills or mountains or sea, a big moon or sun, stars,
/// clouds, simple trees, birds, a lighthouse or a little house with a lit window, on paper.
void _storybook(_K k) {
  final r = k.r, s = k.s, c = k.c;
  final pal = _books[r.i(_books.length)];
  final scene = r.i(4); // hills and house, sea and lighthouse, mountains and lake, big sun meadow
  Paint fill(Color col) => Paint()..color = col;

  // Sky.
  c.drawRect(k.all, Paint()..shader = ui.Gradient.linear(Offset.zero, Offset(0, s * .75), pal.sky));
  // Moon or sun with soft rings of glow.
  final big = scene == 3;
  final gx = r.r(.22, .78), gy = big ? r.r(.36, .5) : r.r(.16, .32), gr = big ? r.r(.16, .22) : r.r(.07, .12);
  for (var i = 4; i >= 1; i--) {
    c.drawCircle(k.o(gx, gy), s * gr * (1 + i * .28), fill(pal.glow.withValues(alpha: .07 + (pal.night ? .03 : .05))));
  }
  c.drawCircle(k.o(gx, gy), s * gr, fill(pal.glow));
  if (pal.night && !big) {
    // Craters, faint.
    for (var i = 0; i < 4; i++) {
      final a = r.d() * math.pi * 2, d = r.r(0, .6) * gr;
      c.drawCircle(k.o(gx + math.cos(a) * d, gy + math.sin(a) * d), s * gr * r.r(.1, .22), fill(_tone(pal.glow, -.07).withValues(alpha: .6)));
    }
  }
  // Stars: dots and four-point sparkles.
  if (pal.night) {
    for (var i = 0, ns = 30 + r.i(50); i < ns; i++) {
      final x = r.d(), y = r.d() * .6;
      if (math.pow(x - gx, 2) + math.pow(y - gy, 2) < math.pow(gr * 1.8, 2)) continue;
      final sz = r.p(.12) ? r.r(.012, .022) : r.r(.002, .005);
      if (sz > .01) {
        _sparkle(c, k.o(x, y), sz * s, pal.glow);
      } else {
        c.drawCircle(k.o(x, y), math.max(.6, sz * s), fill(pal.glow.withValues(alpha: r.r(.5, .95))));
      }
    }
  }
  // Clouds: flat lumpy bands.
  for (var i = 0, nc = r.i(4); i < nc; i++) {
    _cloud(c, s, r.r(-.1, .9), r.r(.1, .5), r.r(.18, .34), pal.cloud.withValues(alpha: pal.night ? .55 : .9), r);
  }
  // Birds.
  if (r.p(.6)) {
    final bx = r.r(.15, .7), by = r.r(.12, .35);
    for (var i = 0, nb = 2 + r.i(5); i < nb; i++) {
      _bird(c, k.o(bx + r.r(0, .25), by + r.r(-.06, .08)), s * r.r(.012, .024), pal.ink.withValues(alpha: .85));
    }
  }

  final L = pal.layers;
  // A hill line: gentle sum of sines.
  double Function(double) hill(double base, double amp, double f) {
    final p1 = r.r(0, 6), p2 = r.r(0, 6), f2 = f * r.r(1.7, 2.6);
    return (x) => base + amp * (.65 * math.sin(x * f + p1) + .35 * math.sin(x * f2 + p2));
  }

  Path under(double Function(double) top, [double x0 = -.02, double x1 = 1.02]) {
    final p = Path()..moveTo(x0 * s, s * 1.02);
    for (var j = 0; j <= 48; j++) {
      final x = x0 + (x1 - x0) * j / 48;
      p.lineTo(x * s, top(x) * s);
    }
    return p
      ..lineTo(x1 * s, s * 1.02)
      ..close();
  }

  // Ridge highlight: a lighter line along the top of a layer.
  void rim(double Function(double) top, Color col) {
    final p = Path()..moveTo(-.02 * s, top(-.02) * s);
    for (var j = 1; j <= 48; j++) {
      final x = -.02 + 1.04 * j / 48;
      p.lineTo(x * s, top(x) * s);
    }
    c.drawPath(
      p,
      Paint()
        ..color = _tone(col, .18).withValues(alpha: .7)
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(.8, s * .004),
    );
  }

  void layer(double Function(double) top, Color col) {
    c.drawPath(under(top), fill(col));
    rim(top, col);
  }

  switch (scene) {
    case 1: // Sea and lighthouse.
      final hor = r.r(.58, .68);
      // A far island.
      if (r.p(.6)) layer(hill(hor - .02, .03, r.r(6, 12)), L[0]);
      // The sea: rows of scalloped waves, darker towards us.
      c.drawRect(Rect.fromLTRB(0, hor * s, s, s), fill(L[1]));
      // The orb's path on the water.
      c.drawRect(Rect.fromLTRB((gx - gr * .5) * s, hor * s, (gx + gr * .5) * s, s), fill(pal.glow.withValues(alpha: .18)));
      for (var row = 0; hor + row * .045 < 1.03; row++) {
        final y = hor + .02 + row * .045, w = .05 + row * .012, col = _tone(_lerp(L[1], L[4], row / 9), row.isEven ? .06 : -.04);
        final p = Path()..moveTo(-.05 * s, s * 1.02);
        for (var x = -.05 - (row.isOdd ? w / 2 : 0); x < 1.05; x += w) {
          p
            ..lineTo(x * s, y * s)
            ..arcToPoint(Offset((x + w) * s, y * s), radius: Radius.circular(w * s * .55), clockwise: true);
        }
        p
          ..lineTo(1.05 * s, s * 1.02)
          ..close();
        c.drawPath(p, fill(col));
        c.drawPath(p, Paint()
          ..color = _tone(col, .22).withValues(alpha: .8)
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(.8, s * .004));
        if (row < 4) {
          for (var x = r.r(0, .2); x < 1; x += r.r(.15, .35)) {
            c.drawLine(k.o(x, y + .012), k.o(x + .03, y + .012), Paint()
              ..color = _tone(col, .25).withValues(alpha: .6)
              ..strokeWidth = math.max(.7, s * .003)
              ..strokeCap = StrokeCap.round);
          }
        }
      }
      // A cliff with the lighthouse.
      final left = r.p(.5), cx0 = left ? -.05 : .55, cx1 = left ? .45 : 1.05;
      final cliffTop = r.r(.52, .6);
      final cliff = Path()..moveTo(cx0 * s, s * 1.02);
      cliff.lineTo(cx0 * s, cliffTop * s);
      for (var j = 0; j <= 10; j++) {
        final x = cx0 + (cx1 - cx0) * j / 10;
        final edge = left ? j / 10 : 1 - j / 10; // 0 at the open sea side
        cliff.lineTo(x * s, (cliffTop + .015 * math.sin(j * 1.7) + (edge > .7 ? (edge - .7) * .9 : 0)) * s);
      }
      cliff
        ..lineTo(cx1 * s, s * 1.02)
        ..close();
      c.drawPath(cliff, fill(L[3]));
      final lx = left ? r.r(.12, .22) : r.r(.78, .88);
      _lighthouse(c, s, lx, cliffTop + .01, r.r(.17, .23), pal, left);
      if (r.p(.5)) _house(c, s, lx + (left ? .09 : -.13), cliffTop + .015, .07, pal, r);
    case 2: // Mountains and a lake.
      final lake = r.r(.62, .72);
      final peaks = <Path>[];
      for (var l = 0; l < 2; l++) {
        final base = lake + .005;
        final p = Path()..moveTo(-.05 * s, base * s);
        var x = -.05;
        while (x < 1.05) {
          final w = l == 0 ? r.r(.28, .5) : r.r(.3, .55), h = l == 0 ? r.r(.2, .42) : r.r(.08, .18);
          p
            ..lineTo((x + w * r.r(.4, .6)) * s, (base - h) * s)
            ..lineTo((x + w) * s, base * s);
          // Snow cap.
          if (l == 0 && r.p(.7)) {
            final px = x + w * .5, py = base - h;
            final cap = Path()
              ..moveTo((px - w * .12) * s, (py + h * .22) * s)
              ..lineTo(px * s, py * s)
              ..lineTo((px + w * .12) * s, (py + h * .22) * s)
              ..lineTo((px + w * .04) * s, (py + h * .17) * s)
              ..lineTo((px - w * .03) * s, (py + h * .24) * s)
              ..close();
            peaks.add(cap);
          }
          x += w * r.r(.45, .8);
        }
        p
          ..lineTo(1.05 * s, base * s)
          ..close();
        c.drawPath(p, fill(L[l]));
        if (l == 0) {
          for (final cap in peaks) {
            c.drawPath(cap, fill(_lerp(L[0], const Color(0xFFFFFFFF), .6)));
          }
        }
      }
      // Lake with a soft mirror of the sky and the orb.
      c.drawRect(Rect.fromLTRB(0, lake * s, s, s), Paint()..shader = ui.Gradient.linear(Offset(0, lake * s), Offset(0, s), [_lerp(pal.sky[1], L[1], .3), _lerp(pal.sky[0], L[3], .5)]));
      c.drawOval(Rect.fromCenter(center: k.o(gx, lake + (lake - gy) * .35), width: gr * 1.6 * s, height: gr * .5 * s), fill(pal.glow.withValues(alpha: .35)));
      for (var i = 0; i < 9; i++) {
        final y = lake + .02 + i * .03, x = r.r(.05, .8);
        c.drawLine(k.o(x, y), k.o(x + r.r(.06, .18), y), Paint()
          ..color = _tone(L[1], .3).withValues(alpha: .5)
          ..strokeWidth = math.max(.7, s * .003)
          ..strokeCap = StrokeCap.round);
      }
      // Forested shores: rows of little pines.
      final shore = hill(r.r(.8, .86), .03, r.r(3, 6));
      layer(shore, L[3]);
      for (var x = r.r(-.02, .02); x < 1.02; x += r.r(.025, .045)) {
        final h = r.r(.05, .1);
        _pine(c, s, x, shore(x) + .01, h, _tone(L[4], r.r(-.1, .05)));
      }
      final near = hill(r.r(.92, .97), .02, r.r(2, 4));
      layer(near, L[4]);
    default: // Hills (with a house) or the big-sun meadow.
      final nl = 4 + r.i(2);
      double Function(double)? houseHill;
      for (var l = 0; l < nl; l++) {
        final base = (scene == 3 ? .55 : .5) + l * (.42 / nl), top = hill(base, r.r(.025, .06), r.r(2.5, 6));
        layer(top, L[math.min(l, L.length - 1)]);
        if (l == nl - 2) houseHill = top;
        // Trees along this hill.
        if (l > 0 && r.p(.75)) {
          final round = r.p(.5), cnt = 1 + r.i(5);
          final tx0 = r.r(0, .8);
          for (var t = 0; t < cnt; t++) {
            final x = tx0 + t * r.r(.035, .07);
            final h = r.r(.06, .11) * (.6 + l / nl);
            final col = _tone(L[math.min(l + 1, L.length - 1)], r.r(-.06, .02));
            round ? _roundTree(c, s, x, top(x) + .008, h, col, pal.ink) : _pine(c, s, x, top(x) + .008, h, col);
          }
        }
      }
      if (scene == 0 && houseHill != null) {
        final hx = r.r(.2, .72);
        _house(c, s, hx, houseHill(hx + .04) + .008, r.r(.09, .13), pal, r);
      } else if (scene == 3) {
        // One big tree on the nearest hill and some flowers.
        final tx = r.r(.15, .85);
        _roundTree(c, s, tx, .93, r.r(.22, .3), _tone(L[4], .05), pal.ink);
        for (var i = 0; i < 40; i++) {
          c.drawCircle(k.o(r.d(), r.r(.9, 1)), s * r.r(.003, .007), fill(_lerp(pal.light, pal.glow, r.d()).withValues(alpha: .9)));
        }
      }
  }

  // Paper: soft mottling, a few fibres, grain and a light vignette.
  for (var i = 0; i < 6; i++) {
    c.drawCircle(k.o(r.d(), r.d()), s * r.r(.2, .4), _blur((r.p(.5) ? const Color(0xFFFFFFFF) : const Color(0xFF000000)).withValues(alpha: .035), s * .1));
  }
  final fibre = Paint()
    ..color = const Color(0x14FFFFFF)
    ..style = PaintingStyle.stroke
    ..strokeWidth = math.max(.5, s * .0012);
  for (var i = 0; i < 40; i++) {
    final x = r.d(), y = r.d(), a = r.d() * math.pi, l = r.r(.01, .03);
    c.drawLine(k.o(x, y), k.o(x + math.cos(a) * l, y + math.sin(a) * l), fibre);
  }
  k.grain(.28);
  k.vignette(.22);
}

void _sparkle(Canvas c, Offset o, double r, Color col) {
  final p = Path()
    ..moveTo(o.dx, o.dy - r)
    ..quadraticBezierTo(o.dx, o.dy, o.dx + r, o.dy)
    ..quadraticBezierTo(o.dx, o.dy, o.dx, o.dy + r)
    ..quadraticBezierTo(o.dx, o.dy, o.dx - r, o.dy)
    ..quadraticBezierTo(o.dx, o.dy, o.dx, o.dy - r)
    ..close();
  c.drawCircle(o, r * .7, Paint()..color = col.withValues(alpha: .18));
  c.drawPath(p, Paint()..color = col);
}

void _cloud(Canvas c, double s, double x, double y, double w, Color col, _Rng r) {
  final p = Path()..moveTo(x * s, y * s);
  var cx = x;
  final h = w * .22;
  while (cx < x + w) {
    final bw = r.r(.25, .4) * w;
    p.arcToPoint(Offset((cx + bw) * s, y * s), radius: Radius.circular(bw * .55 * s));
    cx += bw;
  }
  p
    ..lineTo(cx * s, (y + h * .35) * s)
    ..lineTo(x * s, (y + h * .35) * s)
    ..close();
  c.drawPath(p, Paint()..color = col);
}

void _bird(Canvas c, Offset o, double w, Color col) {
  final p = Path()
    ..moveTo(o.dx - w, o.dy - w * .25)
    ..quadraticBezierTo(o.dx - w * .45, o.dy - w * .55, o.dx, o.dy)
    ..quadraticBezierTo(o.dx + w * .45, o.dy - w * .55, o.dx + w, o.dy - w * .25);
  c.drawPath(
    p,
    Paint()
      ..color = col
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(.8, w * .22)
      ..strokeCap = StrokeCap.round,
  );
}

void _pine(Canvas c, double s, double x, double base, double h, Color col) {
  final w = h * .42;
  final p = Path()..moveTo(x * s, (base - h) * s);
  for (var i = 1; i <= 3; i++) {
    final y = base - h + h * i / 3 * .9, ww = w * (.45 + .55 * i / 3) / 2;
    p
      ..lineTo((x + ww) * s, y * s)
      ..lineTo((x + ww * .45) * s, (y - h * .06) * s);
  }
  for (var i = 3; i >= 1; i--) {
    final y = base - h + h * i / 3 * .9, ww = w * (.45 + .55 * i / 3) / 2;
    p
      ..lineTo((x - ww * .45) * s, (y - h * .06) * s)
      ..lineTo((x - ww) * s, y * s);
  }
  c.drawPath(p..close(), Paint()..color = col);
  c.drawRect(Rect.fromLTRB((x - h * .03) * s, (base - h * .12) * s, (x + h * .03) * s, base * s), Paint()..color = col);
}

void _roundTree(Canvas c, double s, double x, double base, double h, Color col, Color ink) {
  final rr = h * .32;
  c.drawRect(Rect.fromLTRB((x - h * .035) * s, (base - h * .5) * s, (x + h * .035) * s, base * s), Paint()..color = _lerp(col, ink, .5));
  final cy = base - h + rr;
  c.drawCircle(Offset(x * s, cy * s), rr * s, Paint()..color = col);
  c.drawCircle(Offset((x - rr * .6) * s, (cy + rr * .35) * s), rr * .7 * s, Paint()..color = col);
  c.drawCircle(Offset((x + rr * .6) * s, (cy + rr * .35) * s), rr * .7 * s, Paint()..color = col);
  // A lit edge.
  c.drawArc(Rect.fromCircle(center: Offset(x * s, cy * s), radius: rr * .82 * s), -2.6, 1.3, false, Paint()
    ..color = _tone(col, .2).withValues(alpha: .7)
    ..style = PaintingStyle.stroke
    ..strokeWidth = math.max(.7, rr * s * .1)
    ..strokeCap = StrokeCap.round);
}

/// A little house with a pitched roof, a chimney and a lit window.
void _house(Canvas c, double s, double x, double base, double w, _Book pal, _Rng r) {
  final h = w * .7, roofH = w * .45;
  final wall = _lerp(pal.layers[2], pal.glow, .25), roof = _lerp(pal.layers[4], pal.ink, .3);
  c.drawRect(Rect.fromLTRB(x * s, (base - h) * s, (x + w) * s, base * s), Paint()..color = wall);
  c.drawRect(Rect.fromLTRB((x + w * .72) * s, (base - h - roofH * .9) * s, (x + w * .84) * s, (base - h) * s), Paint()..color = roof);
  c.drawPath(
    Path()
      ..moveTo((x - w * .1) * s, (base - h) * s)
      ..lineTo((x + w / 2) * s, (base - h - roofH) * s)
      ..lineTo((x + w * 1.1) * s, (base - h) * s)
      ..close(),
    Paint()..color = roof,
  );
  // Window glow, then the window.
  final win = Rect.fromLTWH((x + w * .18) * s, (base - h * .7) * s, w * .26 * s, w * .26 * s);
  c.drawCircle(win.center, win.width * 1.6, _blur(pal.light.withValues(alpha: pal.night ? .45 : .25), win.width * .8));
  c.drawRect(win, Paint()..color = pal.light);
  c.drawLine(Offset(win.center.dx, win.top), Offset(win.center.dx, win.bottom), Paint()
    ..color = wall
    ..strokeWidth = math.max(.6, win.width * .1));
  // Door.
  c.drawRect(Rect.fromLTWH((x + w * .6) * s, (base - h * .55) * s, w * .2 * s, h * .55 * s), Paint()..color = roof);
  if (r.p(.5)) {
    // Smoke.
    final p = Path()..moveTo((x + w * .78) * s, (base - h - roofH * .95) * s);
    for (var i = 1; i <= 6; i++) {
      p.lineTo((x + w * .78 + math.sin(i * 1.3) * w * .08 + i * w * .03) * s, (base - h - roofH - i * w * .14) * s);
    }
    c.drawPath(p, Paint()
      ..color = pal.cloud.withValues(alpha: .5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(.8, w * s * .05)
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round);
  }
}

void _lighthouse(Canvas c, double s, double x, double base, double h, _Book pal, bool beamRight) {
  final wb = h * .2, wt = h * .13, top = base - h;
  final white = _lerp(pal.glow, const Color(0xFFFFFFFF), .4), red = _lerp(const Color(0xFFC8493E), pal.layers[3], .25);
  // Beam.
  final lampY = top - h * .1;
  final dir = beamRight ? 1 : -1;
  c.drawPath(
    Path()
      ..moveTo(x * s, lampY * s)
      ..lineTo((x + dir * .7) * s, (lampY - .09) * s)
      ..lineTo((x + dir * .7) * s, (lampY + .07) * s)
      ..close(),
    Paint()
      ..shader = ui.Gradient.linear(Offset(x * s, lampY * s), Offset((x + dir * .7) * s, lampY * s), [
        pal.light.withValues(alpha: pal.night ? .45 : .25),
        pal.light.withValues(alpha: 0),
      ]),
  );
  // Tower with stripes.
  final tower = Path()
    ..moveTo((x - wb / 2) * s, base * s)
    ..lineTo((x - wt / 2) * s, top * s)
    ..lineTo((x + wt / 2) * s, top * s)
    ..lineTo((x + wb / 2) * s, base * s)
    ..close();
  c.drawPath(tower, Paint()..color = white);
  c.save();
  c.clipPath(tower);
  for (var i = 0; i < 4; i++) {
    final y0 = top + h * (.1 + i * .25);
    c.drawRect(Rect.fromLTRB((x - wb) * s, y0 * s, (x + wb) * s, (y0 + h * .11) * s), Paint()..color = red);
  }
  c.restore();
  // Lamp room and cap.
  c.drawRect(Rect.fromLTRB((x - wt * .45) * s, (lampY - h * .02) * s, (x + wt * .45) * s, top * s), Paint()..color = pal.light);
  c.drawCircle(Offset(x * s, lampY * s), wt * 1.2 * s, _blur(pal.light.withValues(alpha: .6), wt * s * .8));
  c.drawPath(
    Path()
      ..moveTo((x - wt * .7) * s, (lampY - h * .02) * s)
      ..lineTo(x * s, (lampY - h * .12) * s)
      ..lineTo((x + wt * .7) * s, (lampY - h * .02) * s)
      ..close(),
    Paint()..color = red,
  );
}

// ---------------------------------------------------------------- brush garden

/// Loose painterly flowers: irises against a warm wall, a poppy meadow, or a lily pond.
void _garden(_K k) {
  final r = k.r, n = k.n, s = k.s;
  final b = _Brush(s);
  final mode = r.i(3);
  // Fills a region with slightly bent strokes; [col] and [angle] give each stroke's colour and direction.
  void field(double x0, double y0, double x1, double y1, double sp, double len, double w, Color Function(double x, double y) col,
      double Function(double x, double y) angle, [bool Function(double x, double y)? keep]) {
    for (var gy = y0; gy < y1; gy += sp) {
      for (var gx = x0; gx < x1; gx += sp) {
        final x = gx + r.r(-.5, .5) * sp, y = gy + r.r(-.5, .5) * sp;
        if (keep != null && !keep(x, y)) continue;
        final a = angle(x, y), dx = math.cos(a) * len / 2, dy = math.sin(a) * len / 2;
        final bend = r.r(-.3, .3);
        b.start(x - dx, y - dy);
        b.to(x - dy * bend, y + dx * bend);
        b.to(x + dx, y + dy);
        final c = _tone(col(x, y), r.r(-.1, .1));
        b.end(w * r.r(.8, 1.2), _tone(c, .2), _tone(c, -.22));
      }
    }
  }

  // A petal: a short curved stroke from (x, y) out at angle [a], curling by [curl].
  void petal(double x, double y, double a, double len, double w, double curl, Color c) {
    b.start(x, y);
    for (var i = 1; i <= 4; i++) {
      final aa = a + curl * i / 4;
      x += math.cos(aa) * len / 4;
      y += math.sin(aa) * len / 4;
      b.to(x, y);
    }
    c = _tone(c, r.r(-.08, .08));
    b.end(w, _tone(c, .22), _tone(c, -.2), tail: .8);
  }

  switch (mode) {
    case 0: // Irises.
      final warm = r.p(.55);
      final wall = warm
          ? const [Color(0xFFC9973A), Color(0xFFD9B04A), Color(0xFFE8C766)]
          : const [Color(0xFF6E9C92), Color(0xFF8FB8A8), Color(0xFFB4CFB8)];
      k.fill(_tone(wall[0], -.3));
      field(-.02, -.02, 1.02, .8, .024, .05, .018, (x, y) => _ramp(wall, .5 + .5 * n.fbm(x * 4, y * 4, 2)), (x, y) => .4 * n.at(x * 3, y * 3));
      field(-.02, .78, 1.02, 1.03, .02, .045, .016,
          (x, y) => _ramp(const [Color(0xFF7A3E22), Color(0xFFA8572E), Color(0xFFC77B45)], .5 + .6 * n.at(x * 6, y * 6)),
          (x, y) => .3 * n.at(x * 5, y * 5 + 3));
      b.flush(k.c);
      const leaves = [Color(0xFF2C5A48), Color(0xFF3E7A5A), Color(0xFF5E9A6A), Color(0xFF4F8F86), Color(0xFF8DB48A)];
      const blooms = [Color(0xFF26246E), Color(0xFF3D3A9E), Color(0xFF5B4FC4), Color(0xFF7E6BD6)];
      final tops = <(double, double)>[];
      for (var i = 0, nl = 45 + r.i(30); i < nl; i++) {
        var x = r.r(-.05, 1.05), y = r.r(.85, 1.08);
        final h = r.r(.25, .6), lean = r.r(-.35, .35), bend = r.r(-.8, .8);
        b.start(x, y);
        for (var j = 1; j <= 8; j++) {
          final t = j / 8, a = -math.pi / 2 + lean + bend * t * t;
          x += math.cos(a) * h / 8;
          y += math.sin(a) * h / 8;
          b.to(x, y);
        }
        final c = _tone(leaves[r.i(leaves.length)], r.r(-.1, .08));
        b.end(r.r(.018, .03), _tone(c, .22), _tone(c, -.25), tail: .9);
        if (r.p(.45)) tops.add((x, y));
      }
      b.flush(k.c);
      final white = r.i(tops.length + 1); // often one white iris among the blue
      for (var i = 0; i < tops.length; i++) {
        final (x, y) = tops[i];
        final sz = r.r(.035, .055);
        final base = i == white ? const Color(0xFFEDEBE0) : blooms[r.i(blooms.length)];
        for (var q = -1; q <= 1; q++) {
          petal(x, y, math.pi / 2 + q * 1.1 + r.r(-.2, .2), sz * 1.1, sz * .55, q * .9, _tone(base, -.05)); // falls
          petal(x, y - sz * .2, -math.pi / 2 + q * .5, sz * .9, sz * .45, q * .5, _tone(base, .1)); // standards
        }
        b.dab(x, y + sz * .15, 0, sz * .3, sz * .25, const Color(0xFFF6D34A), const Color(0xFFE0A030));
      }
      b.flush(k.c);
    case 1: // A poppy meadow.
      final sky = r.r(.18, .32);
      const skies = [Color(0xFF9CC3DA), Color(0xFFCFE0E4), Color(0xFFF2E6C8)];
      k.fill(_tone(skies[0], -.3));
      field(-.02, -.02, 1.02, sky + .02, .024, .05, .017, (x, y) => _ramp(skies, y / sky * .7 + .4 * n.at(x * 4, y * 4)),
          (x, y) => .25 * n.at(x * 3, y * 3));
      // A far tree line.
      double bush(double x) => .015 + .06 * (.5 + .5 * n.fbm(x * 7, 1.7, 2)).clamp(0.0, 1.0);
      field(-.02, sky - .08, 1.02, sky + .05, .016, .03, .016,
          (x, y) => _ramp(const [Color(0xFF2E4A36), Color(0xFF4A6B44), Color(0xFF6E8A58)], .5 + .6 * n.at(x * 9, y * 9)),
          (x, y) => n.at(x * 20, y * 20) * 3, (x, y) => y > sky + .03 - bush(x));
      const grass = [Color(0xFF4E6E2E), Color(0xFF6E8E3A), Color(0xFF9AAE4E), Color(0xFFC9C46A)];
      field(-.02, sky + .04, 1.02, 1.03, .02, .05, .016,
          (x, y) => _ramp(grass, .3 + .5 * n.fbm(x * 4, y * 4, 2) + .3 * (1 - (y - sky) / (1 - sky))),
          (x, y) => -math.pi / 2 + .5 * n.at(x * 4 + 9, y * 4) + .3);
      b.flush(k.c);
      const reds = [Color(0xFFD0261E), Color(0xFFE5482A), Color(0xFFF06A2E), Color(0xFFB81E28)];
      for (var i = 0, np = 70 + r.i(70); i < np; i++) {
        final y = sky + .05 + (1 - sky) * math.pow(r.d(), .7).toDouble(), x = r.r(-.02, 1.02);
        final d = ((y - sky) / (1 - sky)).clamp(0.0, 1.0), sz = .008 + .045 * math.pow(d, 1.6);
        final col = r.p(.1) ? (r.p(.5) ? const Color(0xFFEDEDE4) : const Color(0xFF4A62C8)) : reds[r.i(reds.length)];
        for (var q = 0, pn = 4 + r.i(2); q < pn; q++) {
          final a = q / pn * math.pi * 2 + r.d();
          b.dab(x + math.cos(a) * sz * .45, y + math.sin(a) * sz * .3, a + math.pi / 2, sz * 1.1, sz * .8, _tone(col, .2), _tone(col, -.2));
        }
        b.dab(x, y, 0, sz * .35, sz * .35, const Color(0xFF2A1A18), const Color(0xFF140C0C));
      }
      b.flush(k.c);
    default: // A lily pond.
      const water = [Color(0xFF1E2E5A), Color(0xFF2F4E7E), Color(0xFF4F7A96), Color(0xFF8AAEB8), Color(0xFFB8A4C8)];
      k.fill(_tone(water[1], -.35));
      field(-.02, -.02, 1.02, 1.03, .02, .055, .016, (x, y) => _ramp(water, .45 + .55 * n.fbm(x * 3, y * 5, 2)), (x, y) => .12 * n.at(x * 4, y * 4));
      // Reflections of willows: vertical green streaks.
      for (var i = 0, nr = 2 + r.i(3); i < nr; i++) {
        final cx = r.d(), wdt = r.r(.06, .14), len = r.r(.35, .75);
        field(cx - wdt, -.02, cx + wdt, len + .1, .018, .06, .014,
            (x, y) => _ramp(const [Color(0xFF2E5A4A), Color(0xFF4E7E5E), Color(0xFF7FA07A)], .5 + .5 * n.at(x * 8, y * 3)),
            (x, y) => math.pi / 2 + .15 * n.at(x * 30, y * 30),
            (x, y) => r.d() > math.pow((x - cx).abs() / wdt, 2) && y < len * (.75 + .35 * n.at(x * 25, 4)) && r.d() > y / len * .6);
      }
      b.flush(k.c);
      const pads = [Color(0xFF3E6E3A), Color(0xFF5E8E44), Color(0xFF8AAE5A), Color(0xFFA8C878), Color(0xFF2E5034)];
      const blooms = [Color(0xFFF2B8C8), Color(0xFFE8889E), Color(0xFFFFF4EC), Color(0xFFF7D9E2)];
      for (var i = 0, np = 12 + r.i(10); i < np; i++) {
        final cy = r.r(.08, 1), cx = r.r(-.05, 1.05), rx = .04 + .09 * cy * r.r(.7, 1.2), ry = rx * r.r(.35, .5);
        for (var j = 0, nd = (rx * 320).round(); j < nd; j++) {
          final a = r.d() * math.pi * 2, rr = math.sqrt(r.d());
          if ((a - 5.9).abs() < .25) continue; // the notch
          final c = pads[r.i(pads.length)];
          b.dab(cx + math.cos(a) * rr * rx * .85, cy + math.sin(a) * rr * ry * .85, a + math.pi / 2 + r.r(-.3, .3), rx * .45, ry * .45,
              _tone(c, .2), _tone(c, -.2));
        }
        if (r.p(.5)) {
          final col = blooms[r.i(blooms.length)], sz = rx * .55;
          for (var q = 0; q < 7; q++) {
            petal(cx, cy - ry * .2, -math.pi / 2 + (q - 3) * .45, sz, sz * .55, 0, col);
          }
          b.dab(cx, cy - ry * .3, 0, sz * .35, sz * .3, const Color(0xFFF6D34A), const Color(0xFFE0A030));
        }
      }
      b.flush(k.c);
  }
  k.grain(.3);
  k.vignette(.25);
}
