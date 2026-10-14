import 'package:flutter_test/flutter_test.dart';
import 'package:music_player/art/cover_quality.dart';
import 'package:music_player/art/generative_cover.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('seeds are stable and every style renders the same twice', () async {
    expect(GenerativeCover.seedFor('a'), 0xE40C292C); // FNV-1a
    for (final style in CoverStyle.values) {
      final seed = GenerativeCover.seedFor('album/${style.name}');
      final a = await GenerativeCover(seed, style: style).toPng(96);
      final b = await GenerativeCover(seed, style: style).toPng(96);
      expect(a, b, reason: style.name);
      final big = await GenerativeCover(seed, style: style).toPng(512);
      expect(coverProblem(big), isNull, reason: 'our own art passes the quality check');
    }
  });
}
