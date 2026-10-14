import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:music_player/art/generative_cover.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('masterpieces pack: every image credited, public domain, under 10 MB', () {
    final dir = Directory('assets/covers/masterpieces');
    final jpgs = dir.listSync().whereType<File>().where((f) => f.path.endsWith('.jpg')).map((f) => f.uri.pathSegments.last).toSet();
    final credits = (jsonDecode(File('${dir.path}/credits.json').readAsStringSync()) as Map).cast<String, Map>();
    expect(jpgs, isNotEmpty);
    expect(credits.keys.toSet(), jpgs, reason: 'one entry per image, no extras');
    for (final MapEntry(:key, :value) in credits.entries) {
      for (final field in ['title', 'artist', 'year', 'source', 'licence']) {
        expect('${value[field] ?? ''}'.trim(), isNotEmpty, reason: '$key: $field');
      }
      expect(value['source'], startsWith('https://commons.wikimedia.org/wiki/File:'), reason: key);
      expect(value['licence'], startsWith('Public domain'), reason: key);
      expect(value['artistDied'] as int, lessThan(1926), reason: '$key: public domain everywhere (life + 100)');
    }
    final bytes = dir.listSync().whereType<File>().fold<int>(0, (n, f) => n + f.lengthSync());
    expect(bytes, lessThanOrEqualTo(10 * 1000 * 1000));
  });

  test('painted styles are deterministic and never picked as abstract art', () async {
    for (final style in GenerativeCover.painted) {
      for (final px in [64, 512]) {
        final seed = GenerativeCover.seedFor('painted/${style.name}/$px');
        expect(await GenerativeCover(seed, style: style).toPng(px), await GenerativeCover(seed, style: style).toPng(px), reason: '${style.name} $px');
      }
    }
    for (var i = 0; i < 2000; i++) {
      expect(GenerativeCover.painted, isNot(contains(GenerativeCover.styleOf(GenerativeCover.seedFor('album/$i')))));
    }
  });
}
