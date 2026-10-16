// Is an embedded or folder cover good enough to show, or should Gleo draw a
// generative one instead? Pure Dart (package:image), so it can run in an
// isolate at scan time.
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Why a cover is low quality ('unreadable', 'small', 'blocky', 'blurry'),
/// or null when it is fine.
String? coverProblem(Uint8List bytes) {
  final im = img.decodeImage(bytes);
  return im == null ? 'unreadable' : imageProblem(im);
}

bool isLowQualityCover(Uint8List bytes) => coverProblem(bytes) != null;

String? imageProblem(img.Image im) {
  if (math.min(im.width, im.height) < 300) return 'small';
  if (blockiness(im) > 1.8) return 'blocky';
  if (sharpness(im) < .9) return 'blurry';
  return null;
}

Float64List _luma(img.Image im) {
  final l = Float64List(im.width * im.height);
  var i = 0;
  for (final p in im) {
    l[i++] = .299 * p.r + .587 * p.g + .114 * p.b;
  }
  return l;
}

/// JPEG 8x8 block edges: the mean step across block borders over the mean
/// step inside blocks, on the top-left 512 px (where the grid is aligned).
/// About 1 for clean images; heavy compression pushes it well above 2.
double blockiness(img.Image im) {
  final w = math.min(im.width, 512), h = math.min(im.height, 512);
  final l = _luma(img.copyCrop(im.convert(numChannels: 3), x: 0, y: 0, width: w, height: h));
  var edge = 0.0, inner = 0.0, ne = 0, ni = 0;
  for (var y = 1; y < h; y++) {
    for (var x = 1; x < w; x++) {
      final v = l[y * w + x];
      final dx = (v - l[y * w + x - 1]).abs(), dy = (v - l[(y - 1) * w + x]).abs();
      if (x % 8 == 0) {
        edge += dx;
        ne++;
      } else {
        inner += dx;
        ni++;
      }
      if (y % 8 == 0) {
        edge += dy;
        ne++;
      } else {
        inner += dy;
        ni++;
      }
    }
  }
  edge /= ne;
  inner /= ni;
  if (edge < 1) return 1; // flat image: nothing to judge
  return (edge + .5) / (inner + .5);
}

/// Edge crispness on a 256 px copy: mean |Laplacian| over mean gradient, on
/// the pixels that sit on an edge. Scales like 1 / blur width, ignores flat
/// areas, so a clean minimal cover is not called blurry.
double sharpness(img.Image im) {
  final small = img.copyResize(im, width: im.width >= im.height ? 256 : null, height: im.height > im.width ? 256 : null, interpolation: img.Interpolation.average);
  final w = small.width, h = small.height, l = _luma(small);
  var lap = 0.0, grad = 0.0, n = 0;
  for (var y = 1; y < h - 1; y++) {
    for (var x = 1; x < w - 1; x++) {
      final i = y * w + x;
      final gx = (l[i + 1] - l[i - 1]) / 2, gy = (l[i + w] - l[i - w]) / 2;
      final g = math.sqrt(gx * gx + gy * gy);
      if (g < 8) continue;
      lap += (l[i + 1] + l[i - 1] + l[i + w] + l[i - w] - 4 * l[i]).abs();
      grad += g;
      n++;
    }
  }
  if (n < w * h * .003) return double.infinity; // almost no edges: nothing to judge
  return lap / grad;
}
