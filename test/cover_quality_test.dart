import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:gleo/art/cover_quality.dart';

/// A crisp 600 px "cover": a gradient, shapes, thin lines and text.
img.Image clean() {
  final im = img.Image(width: 600, height: 600);
  for (var y = 0; y < 600; y++) {
    for (var x = 0; x < 600; x++) {
      im.setPixelRgb(x, y, 40 + x ~/ 5, 30 + y ~/ 6, 90);
    }
  }
  img.fillCircle(im, x: 220, y: 240, radius: 130, color: img.ColorRgb8(255, 107, 74));
  img.fillRect(im, x1: 330, y1: 80, x2: 540, y2: 300, color: img.ColorRgb8(240, 230, 200));
  for (var i = 0; i < 12; i++) {
    img.drawLine(im, x1: 40, y1: 400 + i * 14, x2: 560, y2: 380 + i * 16, color: img.ColorRgb8(20, 20, 30), thickness: 2);
  }
  img.drawString(im, 'GLEO', font: img.arial48, x: 320, y: 500, color: img.ColorRgb8(255, 255, 255));
  return im;
}

String? check(img.Image im, {bool jpeg = false, int quality = 90}) =>
    coverProblem(jpeg ? img.encodeJpg(im, quality: quality) : img.encodePng(im));

void main() {
  test('cover quality', () {
    final c = clean();
    final blurry = img.gaussianBlur(clean(), radius: 6);

    expect(check(c), isNull);
    expect(check(c, jpeg: true), isNull, reason: 'a normal JPEG is fine');
    expect(check(img.Image(width: 600, height: 600)), isNull, reason: 'a flat cover is not blurry');
    expect(check(img.copyResize(c, width: 200)), 'small');
    expect(check(c, jpeg: true, quality: 3), 'blocky');
    expect(check(blurry), 'blurry');
    expect(check(img.copyResize(img.copyResize(c, width: 80), width: 600, interpolation: img.Interpolation.linear)), 'blurry',
        reason: 'a small cover blown up');
    expect(coverProblem(Uint8List.fromList([1, 2, 3])), 'unreadable');
  });
}
