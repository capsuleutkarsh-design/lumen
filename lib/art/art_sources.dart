// Where Lumen's cover art comes from: styles drawn by code (lib/art/) or bundled image
// packs (assets/covers/<pack>/*.jpg + credits.json). The automatic art of an album is
// picked by a hash of its key over the items of the sources that are on.
//
// Adding a pack: put the images in assets/covers/<pack>/, list the folder in pubspec.yaml
// (assets:), and add `ArtSource.pack('<pack>', 'Name')` below. credits.json is optional:
//   {"starry-night.jpg": {"title": "The Starry Night", "artist": "Vincent van Gogh", "year": 1889}}
// Adding a code style: add it to CoverStyle and to a source's style list below.
import 'dart:convert';

import 'package:flutter/services.dart';

import 'art_cache.dart';
import 'generative_cover.dart';

class ArtSource {
  ArtSource.styles(this.id, this.name, this.styles, {this.painterly = false}) : pack = false;
  ArtSource.pack(this.id, this.name, {this.painterly = false}) : styles = const [], pack = true;

  final String id, name;

  /// Painterly sources are on by default; the others can be turned on in Settings.
  final bool painterly;
  final bool pack;
  final List<CoverStyle> styles;

  /// A pack's image file names (filled by [loadArtPacks]) and their credits.
  List<String> images = [];
  Map<String, Map<String, Object?>> credits = {};

  /// Its share of the automatic choice: each image counts once, each code style 8 times.
  int get weight => pack ? images.length : styles.length * 8;

  /// The [n]th artwork of this source for an album; n = 0 is the album's automatic one.
  /// Packs list every image in order for n >= 1.
  Art item(String albumKey, int n) {
    final seed = GenerativeCover.seedFor(n == 0 ? albumKey : '$albumKey#$n');
    if (pack) return Art.drawn('pack:$id/${images[(n == 0 ? GenerativeCover.seedFor('$albumKey/image') : n - 1) % images.length]}');
    // The abstract styles keep the art the owner approved: the seed's own style when it is in this source.
    final own = GenerativeCover.styleOf(seed);
    final style = styles.contains(own) ? own : styles[(seed >>> 8) % styles.length];
    return Art.drawn('${style.name}@${seed.toRadixString(16)}');
  }
}

/// Every source, in the order the Change cover picker shows them.
final artSources = [
  ArtSource.pack('masterpieces', 'Masterpieces', painterly: true),
  ArtSource.styles('painted', 'Painted', GenerativeCover.painted, painterly: true),
  ArtSource.pack('illustrated', 'Illustrated', painterly: true),
  ArtSource.styles('abstract', 'Abstract', const [
    CoverStyle.mesh,
    CoverStyle.halftone,
    CoverStyle.contours,
    CoverStyle.bauhaus,
    CoverStyle.riso,
    CoverStyle.bokeh,
    CoverStyle.flow,
    CoverStyle.stripes,
    CoverStyle.paper,
    CoverStyle.glitch,
    CoverStyle.aurora,
  ]),
  ArtSource.pack('sample', 'Sample pack'), // a small test pack, proves the image-pack path
];

ArtSource get _abstract => artSources.firstWhere((s) => s.id == 'abstract');

/// The sources that are on: the saved list, or every painterly one.
Set<String> sourcesOn(String? saved) {
  try {
    if (saved != null) return {...(jsonDecode(saved) as List).cast<String>()};
  } catch (_) {}
  return {for (final s in artSources.where((s) => s.painterly)) s.id};
}

/// The sources Lumen picks from: those that are on and have something in them; with none
/// (e.g. no painterly pack installed yet), the abstract styles.
List<ArtSource> sourcesInUse(Set<String> on) {
  final pool = [
    for (final s in artSources)
      if (on.contains(s.id) && s.weight > 0) s,
  ];
  return pool.isEmpty ? [_abstract] : pool;
}

/// The art Lumen picks for an album: a hash of its key over the items of [sourcesInUse].
Art autoArt(String albumKey, Set<String> on) {
  final pool = sourcesInUse(on);
  var r = GenerativeCover.seedFor('$albumKey/source') % pool.fold(0, (n, s) => n + s.weight);
  for (final s in pool) {
    if (r < s.weight) return s.item(albumKey, 0);
    r -= s.weight;
  }
  return pool.last.item(albumKey, 0);
}

/// Whether [key] still names something Lumen can draw (a pack may have been removed).
bool knownArt(String key) {
  if (key.startsWith('pack:')) {
    final slash = key.indexOf('/');
    return slash > 5 && artSources.any((s) => s.pack && s.id == key.substring(5, slash) && s.images.contains(key.substring(slash + 1)));
  }
  return CoverStyle.values.asNameMap().containsKey(key.split('@').first);
}

/// "The Starry Night — Vincent van Gogh, 1889" for a pack image with credits.
String? creditFor(Art art) {
  final key = art.key;
  if (key == null || !key.startsWith('pack:')) return null;
  final slash = key.indexOf('/');
  final pack = artSources.where((s) => s.pack && s.id == key.substring(5, slash)).firstOrNull;
  final c = pack?.credits[key.substring(slash + 1)];
  if (c == null) return null;
  final by = [c['artist'], c['year']].whereType<Object>().join(', ');
  return [c['title'], if (by.isNotEmpty) by].whereType<Object>().join(' — ');
}

/// Finds the bundled packs' images and credits (once, at start).
Future<void> loadArtPacks([AssetBundle? bundle]) async {
  bundle ??= rootBundle;
  final assets = (await AssetManifest.loadFromAssetBundle(bundle)).listAssets();
  for (final s in artSources.where((s) => s.pack)) {
    final dir = 'assets/covers/${s.id}/';
    s.images = [
      for (final a in assets)
        if (a.startsWith(dir) && RegExp(r'\.(jpe?g|png|webp)$', caseSensitive: false).hasMatch(a)) a.substring(dir.length),
    ]..sort();
    if (assets.contains('${dir}credits.json')) {
      try {
        s.credits = (jsonDecode(await bundle.loadString('${dir}credits.json')) as Map).map(
          (k, v) => MapEntry('$k', (v as Map).cast<String, Object?>()),
        );
      } catch (_) {} // bad credits: the images still work
    }
  }
}
