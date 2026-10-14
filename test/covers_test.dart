// Generated covers in the app: when they are used, Change cover, the 0.2.0 database
// upgrade, and the disc's ticker stopping on pause.
import 'dart:io';

import 'package:flutter/material.dart';
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
    // Nothing painterly installed yet: the abstract styles, with each album's own approved style.
    final art = autoArt('ana|album a|x', sourcesOn(null));
    final seed = GenerativeCover.seedFor('ana|album a|x');
    expect(art, Art.drawn('${GenerativeCover.styleOf(seed).name}@${seed.toRadixString(16)}'));
  });

  test('an image pack: found in the assets, picked by hash, drawn square into the cache, credited', () async {
    await loadArtPacks();
    final sample = artSources.firstWhere((s) => s.id == 'sample');
    expect(sample.images, ['dunes.jpg', 'lanterns.jpg', 'tide.jpg']);
    final picks = {
      for (var i = 0; i < 30; i++) autoArt('album $i', {'sample'}),
    };
    expect(picks, {for (final f in sample.images) Art.drawn('pack:sample/$f')}, reason: 'every image gets used');
    expect(creditFor(const Art.drawn('pack:sample/dunes.jpg')), 'Dunes (sample) — Drawn by Lumen, 2026');
    expect(knownArt('pack:sample/dunes.jpg'), isTrue);
    expect(knownArt('pack:gone/x.jpg'), isFalse);

    ArtCache.init(p.join(tmp.path, 'art'));
    final file = await ArtCache.ensure(const Art.drawn('pack:sample/dunes.jpg'), 128); // a 900 x 600 image
    final im = img.decodeJpg(File(file!).readAsBytesSync())!;
    expect((im.width, im.height), (128, 128));
    ArtCache.dir = null;
  });
}
