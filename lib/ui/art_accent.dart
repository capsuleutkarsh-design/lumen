import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../library/models.dart';
import 'app.dart';
import 'theme.dart';
import 'widgets.dart';

/// The colour taken from the playing song's cover, or null for coral. Only Now
/// Playing's glow and the active seek bar use it; everything else stays coral.
final artAccent = ValueNotifier<Color?>(null);

/// Settings → Theme: on by default.
bool get accentFromArt => lib.setting('artAccent') != '0';

/// The colour a cover should lend the UI, from its RGBA pixels: the most
/// colourful hue family (not a muddy average). Null (coral) when the cover is
/// grey, too dark or too light, or would show less than 3:1 against [bg].
Color? pickAccent(List<int> rgba, Color bg) {
  const n = 12; // 30° hue families
  final w = List.filled(n, 0.0), r = List.filled(n, 0.0), g = List.filled(n, 0.0), b = List.filled(n, 0.0);
  var pixels = 0;
  for (var i = 0; i + 3 < rgba.length; i += 4) {
    if (rgba[i + 3] < 128) continue;
    pixels++;
    final c = HSLColor.fromColor(Color.fromARGB(255, rgba[i], rgba[i + 1], rgba[i + 2]));
    final chroma = c.saturation * (1 - (2 * c.lightness - 1).abs());
    if (chroma < 0.1) continue;
    final k = (c.hue / 360 * n).floor() % n;
    w[k] += chroma;
    r[k] += rgba[i] * chroma;
    g[k] += rgba[i + 1] * chroma;
    b[k] += rgba[i + 2] * chroma;
  }
  if (pixels == 0) return null;
  var best = 0;
  for (var k = 1; k < n; k++) {
    if (w[k] > w[best]) best = k;
  }
  if (w[best] / pixels < 0.05) return null; // almost no colour: grey
  final c = Color.fromARGB(255, (r[best] / w[best]).round(), (g[best] / w[best]).round(), (b[best] / w[best]).round());
  final hsl = HSLColor.fromColor(c);
  if (hsl.saturation < 0.25 || hsl.lightness < 0.2 || hsl.lightness > 0.85) return null;
  final (x, y) = (c.computeLuminance(), bg.computeLuminance());
  return (max(x, y) + 0.05) / (min(x, y) + 0.05) < 3 ? null : c;
}

/// RGBA of [image] (already small: the 64 px thumbnail), or null if it can't be read.
Future<List<int>?> _pixels(ImageProvider image) {
  final done = Completer<List<int>?>();
  final stream = image.resolve(ImageConfiguration.empty);
  late final ImageStreamListener l;
  l = ImageStreamListener(
    (info, _) async {
      stream.removeListener(l);
      final data = await info.image.toByteData(format: ui.ImageByteFormat.rawRgba);
      info.dispose();
      if (!done.isCompleted) done.complete(data?.buffer.asUint8List());
    },
    onError: (_, _) {
      stream.removeListener(l);
      if (!done.isCompleted) done.complete(null);
    },
  );
  stream.addListener(l);
  return done.future;
}

/// The accent for [t], read through the cover widget's own source ([CoverArt.source]),
/// so covers drawn by Lumen give their colour the same way as files.
Future<Color?> coverAccent(Track t) async {
  final (image, fallback) = CoverArt.source(t, 64);
  final px = image == null ? null : await _pixels(image);
  return pickAccent(px ?? [(fallback.r * 255).round(), (fallback.g * 255).round(), (fallback.b * 255).round(), 255], C.bg);
}

/// Re-checks the accent now (after the setting or the theme changed).
void Function() refreshArtAccent = () {};

Object? _watching;

/// Keeps [artAccent] in step with the playing song, the setting and the theme.
void watchArtAccent() {
  if (identical(_watching, engine)) return; // the App is built again (tests), same engine
  _watching = engine;
  Object? key;
  Future<void> update() async {
    final t = engine.current;
    final k = (t?.id, t?.cover, accentFromArt, C.palette);
    if (k == key) return;
    key = k;
    final c = t == null || !accentFromArt ? null : await coverAccent(t);
    if (key == k) artAccent.value = c; // a newer song may have started meanwhile
  }

  engine.addListener(update);
  lib.addListener(update);
  refreshArtAccent = update;
  update();
}

/// Builds with the art accent (coral when there is none), blending changes over 300 ms.
class ArtAccentBuilder extends StatelessWidget {
  const ArtAccentBuilder({super.key, required this.builder});
  final Widget Function(BuildContext context, Color accent) builder;
  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: artAccent,
    builder: (context, c, _) => TweenAnimationBuilder<Color?>(
      tween: ColorTween(end: c ?? C.accent),
      duration: Motion.colour,
      curve: Motion.curve,
      builder: (context, v, _) => builder(context, v ?? C.accent),
    ),
  );
}
