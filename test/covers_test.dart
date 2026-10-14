// Generated covers in the app: when they are used, Change cover, the 0.2.0 database
// upgrade, and the disc's ticker stopping on pause.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_player/art/art_cache.dart';
import 'package:music_player/art/art_sources.dart';
import 'package:music_player/art/generative_cover.dart';
import 'package:music_player/library/db.dart';
import 'package:music_player/library/library.dart';
import 'package:music_player/library/scanner.dart';
import 'package:music_player/ui/disc.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

import 'scanner_test.dart' show jpeg, writeFlac;

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('mp_covers'));
  tearDown(() => tmp.deleteSync(recursive: true));

  Library scanned() {
    final music = p.join(tmp.path, 'music');
    // A: a 100 px folder cover (too small). B: a clean 600 px one. C: none.
    for (final a in ['A', 'B', 'C']) {
      writeFlac(p.join(music, a, '01.flac'), {'TITLE': 'Song $a', 'ARTIST': 'Ana', 'ALBUM': 'Album $a'});
    }
    File(p.join(music, 'A', 'cover.jpg')).writeAsBytesSync(jpeg(90, size: 100));
    File(p.join(music, 'B', 'cover.jpg')).writeAsBytesSync(jpeg(90, size: 600));
    final covers = p.join(tmp.path, 'covers');
    scan(p.join(tmp.path, 'library.db'), covers, [music]);
    return Library(tmp.path)..load();
  }

  test('a missing or low-quality cover gets generated art; a good one is kept', () {
    final lib = scanned();
    Art art(String album) {
      final a = lib.albums.firstWhere((x) => x.title == album);
      return lib.artFor(a.key, a.cover);
    }

    final a = lib.albums.firstWhere((x) => x.title == 'Album A');
    expect(a.cover, isNotNull, reason: 'the small cover is still found');
    expect(lib.db.select('SELECT problem FROM cover_quality WHERE cover = ?', [a.cover]).single['problem'], 'small');
    expect(art('Album A'), autoArt(a.key, lib.artSourcesOn));
    expect(art('Album B').file, isNotNull);
    expect(art('Album C').generated, isTrue);
    lib.db.close();
  });

  test('Change cover is stored per album, survives a restart, and resets to automatic', () {
    var lib = scanned();
    final a = lib.albums.firstWhere((x) => x.title == 'Album A');
    final b = lib.albums.firstWhere((x) => x.title == 'Album B');
    lib.setCoverChoice(a.key, 'original'); // keep the small original
    lib.setCoverChoice(b.key, 'riso@4d2'); // a generated one instead of a good cover
    lib.db.close();

    lib = Library(tmp.path)..load();
    expect(lib.artFor(a.key, a.cover), Art.file(a.cover!));
    expect(lib.artFor(b.key, b.cover), const Art.drawn('riso@4d2'));
    lib.setCoverChoice(b.key, null);
    expect(lib.artFor(b.key, b.cover), Art.file(b.cover!));
    lib.db.close();
    expect(File(p.join(tmp.path, 'music', 'B', 'cover.jpg')).lengthSync(), jpeg(90, size: 600).length, reason: 'files untouched');
  });

  test('a database from the 0.2.0 betas (version 2) upgrades: cover tables, embedded covers read again once', () {
    final path = p.join(tmp.path, 'library.db');
    final old = sqlite3.open(path);
    old.execute(migrations[0]);
    old.execute(migrations[1]);
    old.execute('PRAGMA user_version = 2');
    for (final (id, embedded) in [(1, 1), (2, 0)]) {
      old.execute(
        'INSERT INTO tracks(id, path, root, folder, mtime, size, title, album, duration_ms, codec, sample_rate, bit_depth, channels, bitrate, added_at, embedded_cover) '
        "VALUES(?, ?, 'r', 'f', 777, 1, 't', 'a', 1, 'FLAC', 44100, 16, 2, 0, 0, ?)",
        [id, 'p$id', embedded],
      );
    }
    old.close();
    final db = openDb(path);
    expect(db.select('PRAGMA user_version').single.values.first, migrations.length);
    expect([for (final r in db.select('SELECT mtime FROM tracks ORDER BY id')) r['mtime']], [0, 777]);
    db.execute("INSERT INTO album_covers VALUES('k', 'original')");
    db.execute("INSERT INTO cover_quality VALUES('c', 'blurry')");
    db.close();
  });

  testWidgets('the disc turns while playing and its ticker stops on pause', (tester) async {
    if (windowsAnimationsOff) return markTestSkipped('Windows animations are off on this PC');
    Widget disc(bool playing, {bool still = false}) => MediaQuery(
      data: MediaQueryData(disableAnimations: still),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: DiscView(art: const Art.drawn('mesh@1'), playing: playing, size: 200, style: DiscStyle.vinyl),
        ),
      ),
    );
    await tester.pumpWidget(disc(true));
    final state = tester.state<DiscViewState>(find.byType(DiscView));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(state.spinning, isTrue);
    expect(state.turns.value, greaterThan(0));

    await tester.pumpWidget(disc(false));
    await tester.pump(const Duration(milliseconds: 300));
    expect(state.spinning, isTrue, reason: 'still slowing down');
    await tester.pump(const Duration(milliseconds: 700)); // the 0.6 s slow-down is over
    expect(state.spinning, isFalse);
    expect(tester.binding.transientCallbackCount, 0, reason: 'nothing ticks while paused');
    final stopped = state.turns.value;
    await tester.pump(const Duration(seconds: 2));
    expect(state.turns.value, stopped);

    // With animations turned off, it never turns.
    await tester.pumpWidget(disc(true, still: true));
    await tester.pump(const Duration(seconds: 1));
    expect(state.spinning, isFalse);
  });

  test('art sources: painterly packs by default, else the abstract styles the owner approved', () {
    for (final s in artSources.where((s) => s.pack)) {
      s.images = [];
    }
    expect(sourcesOn(null), {'masterpieces', 'painted', 'illustrated'});
    // The painted styles need no pack, so painterly art is there even with no pack installed.
    final painted = autoArt('ana|album a|x', sourcesOn(null)).key!.split('@').first;
    expect(GenerativeCover.painted.map((s) => s.name), contains(painted));
    // Nothing painterly in use (no pack installed, Painted off): the abstract styles, with each album's own approved style.
    final art = autoArt('ana|album a|x', {'masterpieces'});
    final seed = GenerativeCover.seedFor('ana|album a|x');
    expect(art, Art.drawn('${GenerativeCover.styleOf(seed).name}@${seed.toRadixString(16)}'));
  });

  test('the packs: found in the assets, credited, and the three painterly sources picked equally often', () async {
    await loadArtPacks();
    ArtSource src(String id) => artSources.firstWhere((s) => s.id == id);
    expect(src('masterpieces').images, hasLength(100));
    expect(src('illustrated').images, hasLength(100));
    expect(artSources.map((s) => s.id), isNot(contains('sample')), reason: 'the sample pack is not shipped');
    expect(creditFor(const Art.drawn('pack:masterpieces/vangogh_starry_night.jpg')), 'The Starry Night — Vincent van Gogh, 1889');
    expect(creditFor(const Art.drawn('pack:illustrated/illus_001.jpg')), 'Lavender Bison — Made with Magnific AI for Lumen');
    expect(knownArt('pack:illustrated/illus_100.jpg'), isTrue);
    expect(knownArt('pack:gone/x.jpg'), isFalse);
    // A big library with the defaults: about a third each, abstract (off) never, and every pack image used.
    final count = <String, int>{}, used = <String>{};
    for (var i = 0; i < 3000; i++) {
      final key = autoArt('artist $i\u0000album $i\u0000d:/music/$i', sourcesOn(null)).key!;
      if (key.startsWith('pack:')) used.add(key);
      final id = key.startsWith('pack:')
          ? key.substring(5, key.indexOf('/'))
          : GenerativeCover.painted.any((s) => key.startsWith('${s.name}@'))
          ? 'painted'
          : 'abstract';
      count[id] = (count[id] ?? 0) + 1;
    }
    expect(count.keys.toSet(), {'masterpieces', 'illustrated', 'painted'});
    for (final n in count.values) {
      expect(n, inInclusiveRange(900, 1100), reason: '$count');
    }
    expect(used, hasLength(200));
  });

  test('a pack image is drawn square into the cache (a wide one is cropped), from a tiny test-only pack', () async {
    final wide = img.Image(width: 90, height: 60);
    for (final px in wide) {
      px.setRgb(px.x * 2, px.y * 3, 120);
    }
    final pack = _Bundle({
      'assets/covers/illustrated/wide.jpg': img.encodeJpg(wide),
      'assets/covers/illustrated/credits.json': utf8.encode('{"wide.jpg": {"title": "Wide", "credit": "Test fixture"}}'),
    });
    await loadArtPacks(pack);
    expect(artSources.firstWhere((s) => s.id == 'illustrated').images, ['wide.jpg']);
    expect(creditFor(const Art.drawn('pack:illustrated/wide.jpg')), 'Wide — Test fixture');
    ArtCache.assets = pack;
    ArtCache.init(p.join(tmp.path, 'art'));
    final file = await ArtCache.ensure(const Art.drawn('pack:illustrated/wide.jpg'), 128);
    final im = img.decodeJpg(File(file!).readAsBytesSync())!;
    expect((im.width, im.height), (128, 128));
    ArtCache.dir = null;
    ArtCache.assets = rootBundle;
    await loadArtPacks();
  });

  test('the art cache is capped: old versions, then the least recently used files go first', () async {
    final dir = Directory(p.join(tmp.path, 'art'))..createSync();
    File f(String name) => File(p.join(dir.path, name));
    final v = 'v${ArtCache.version}_';
    f('v1_old_128.jpg').writeAsBytesSync(List.filled(10, 0));
    final names = [for (final n in ['a', 'b', 'c', 'd']) '$v${n}_128.jpg'];
    for (final n in names) {
      f(n).writeAsBytesSync(List.filled(100, 0));
    }
    for (final (i, n) in names.indexed) {
      f(n).setLastAccessedSync(DateTime(2026, 1, 1 + i));
    }
    f(names[1]).setLastAccessedSync(DateTime(2026, 2, 1)); // b was used last
    await ArtCache.trim(dir.path, 250);
    expect(dir.listSync().map((e) => p.basename(e.path)).toSet(), {'${v}b_128.jpg', '${v}d_128.jpg'});
  });

  test("a moved music folder keeps its albums' automatic art and Change cover choice", () {
    var lib = scanned();
    album(Library l, String title) => l.albums.firstWhere((x) => x.title == title);
    final c = album(lib, 'Album C');
    final autoC = lib.artFor(c.key, c.cover);
    lib.setCoverChoice(album(lib, 'Album A').key, 'riso@4d2');
    lib.db.close();
    Directory(p.join(tmp.path, 'music')).renameSync(p.join(tmp.path, 'moved'));
    scan(p.join(tmp.path, 'library.db'), p.join(tmp.path, 'covers'), [p.join(tmp.path, 'moved')]);
    lib = Library(tmp.path)..load();
    final c2 = album(lib, 'Album C'), a2 = album(lib, 'Album A');
    expect(c2.key, isNot(c.key), reason: 'the album key has the folder in it');
    expect(lib.artFor(c2.key, c2.cover), autoC);
    expect(lib.artFor(a2.key, a2.cover), const Art.drawn('riso@4d2'));
    lib.db.close();
  });
}

/// A tiny asset bundle for tests: the given files plus their AssetManifest.
class _Bundle extends CachingAssetBundle {
  _Bundle(this.files);
  final Map<String, List<int>> files;
  @override
  Future<ByteData> load(String key) async {
    if (key == 'AssetManifest.bin') {
      return const StandardMessageCodec().encodeMessage({
        for (final f in files.keys) f: [{'asset': f}],
      })!;
    }
    final bytes = files[key];
    if (bytes == null) throw FlutterError('no asset $key');
    return ByteData.sublistView(Uint8List.fromList(bytes));
  }
}
