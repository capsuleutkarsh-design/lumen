// UI fixes of the 0.2.0 round: one small check per review finding (IDs from
// lumen_work/review/ui.md). Runs headless with a scratch library and an engine
// that never opens libmpv.
import 'dart:io';
import 'dart:math';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:music_player/audio/engine.dart';
import 'package:music_player/library/library.dart';
import 'package:music_player/library/models.dart';
import 'package:music_player/ui/app.dart';
import 'package:music_player/ui/lyrics_view.dart';
import 'package:music_player/ui/pages/albums.dart';
import 'package:music_player/ui/pages/artists.dart';
import 'package:music_player/ui/pages/settings.dart';
import 'package:music_player/ui/pages/songs.dart';
import 'package:music_player/ui/player_bar.dart';
import 'package:music_player/ui/search.dart';
import 'package:music_player/ui/theme.dart';
import 'package:music_player/ui/tracks.dart';
import 'package:music_player/ui/widgets.dart';

/// Plays nothing: transport changes only flip fields.
class FakeEngine extends Engine {
  FakeEngine(super.lib);
  @override
  Future<void> togglePlay() async {
    playing = !playing;
    notifyListeners();
  }

  @override
  Future<void> setVolume(double v) async {
    volume = v.clamp(0, 100);
    notifyListeners();
  }

  @override
  Future<void> toggleMute() async {
    muted = !muted;
    notifyListeners();
  }
}

late Directory tmp;
const long = 'Symphony No. 9 in D minor, Op. 125 "Choral": IV. Presto – Allegro assai – Andante maestoso – Allegro energico';
const longArtist = 'Berliner Philharmoniker, Herbert von Karajan, Gundula Janowitz, Hilde Rössel-Majdan, Waldemar Kmentt';

/// [albums] albums of [per] songs each, no files, no cover art.
void addTracks({int albums = 3, int per = 5, String? lyrics, String? title}) {
  final db = lib.db;
  final ins = db.prepare(
    '''INSERT INTO tracks(id,path,root,folder,mtime,size,title,artist,album_artist_tag,compilation,album,album_artist,album_key,
      track_no,disc_no,year,genre,duration_ms,codec,sample_rate,bit_depth,channels,bitrate,cover,lyrics,added_at) VALUES(?,?,?,?,?,?,?,?,?,0,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)''',
  );
  var id = (db.select('SELECT max(id) m FROM tracks').first['m'] as int? ?? 0) + 1;
  for (var a = 0; a < albums; a++) {
    final album = 'Album ${String.fromCharCode(65 + a)}', artist = 'Artist $a';
    for (var i = 0; i < per; i++) {
      ins.execute([
        id,
        '${tmp.path}\\$album\\$i.flac',
        tmp.path,
        '${tmp.path}\\$album',
        0,
        0,
        title ?? 'Song $i of $album',
        artist,
        artist,
        album,
        artist,
        '${artist.toLowerCase()}\u0000${album.toLowerCase()}',
        i + 1,
        1,
        2000 + a,
        'Rock',
        200000,
        'FLAC',
        96000,
        24,
        2,
        0,
        null,
        lyrics,
        id,
      ]);
      id++;
    }
  }
  ins.close();
  lib.load();
}

Future<void> pumpApp(WidgetTester tester, {Size size = const Size(1440, 900)}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(const App());
  await tester.pump();
}

Future<void> pumpOne(WidgetTester tester, Widget w, {Size size = const Size(1200, 800), double text = 1}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: buildTheme(),
      scaffoldMessengerKey: messengerKey,
      home: Builder(
        builder: (c) => MediaQuery(
          data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(text)),
          child: Scaffold(body: w),
        ),
      ),
    ),
  );
  await tester.pump();
}

double contrast(Color a, Color b) {
  double l(Color c) => c.computeLuminance();
  final (x, y) = (l(a), l(b));
  return (max(x, y) + 0.05) / (min(x, y) + 0.05);
}

/// A widget test with a fresh engine made inside the test's fake-async zone
/// (its internal futures must belong to that zone to complete).
void uiTest(String name, Future<void> Function(WidgetTester) body) => testWidgets(name, (tester) async {
  engine = FakeEngine(lib);
  await body(tester);
});

void main() {
  setUp(() {
    tmp = Directory.systemTemp.createTempSync('lumen_ui');
    lib = Library(tmp.path)..load();
    selection.clear();
    nav.go('home');
    nav.setSearch(false);
    nav.memo.clear();
    if (nav.queue) nav.toggleQueue();
    final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    m.setMockMethodCallHandler(const MethodChannel('window_manager'), (_) async => false);
    m.setMockMethodCallHandler(const MethodChannel('desktop_drop'), (_) async => null);
  });
  tearDown(() {
    lib.db.close();
    tmp.deleteSync(recursive: true);
  });

  uiTest('B1 + U3: the player bar fits the smallest window and 130 % text', (tester) async {
    addTracks(title: long);
    engine.queue.playNow([lib.tracks.first.id]);
    await pumpOne(
      tester,
      const Align(alignment: Alignment.bottomCenter, child: PlayerBar()),
      size: const Size(780, 200),
    );
    expect(tester.takeException(), isNull);
    await pumpOne(
      tester,
      const Align(alignment: Alignment.bottomCenter, child: PlayerBar()),
      size: const Size(780, 300),
      text: 1.3,
    );
    expect(tester.takeException(), isNull);
  });

  uiTest('B2: album and playlist headers wrap instead of overflowing when narrow', (tester) async {
    addTracks(title: long);
    final a = lib.albums.first;
    for (final w in [440.0, 560.0, 720.0]) {
      await pumpOne(
        tester,
        SingleChildScrollView(
          child: SizedBox(
            width: w,
            child: PageHero(
              cover: CoverArt.album(a),
              glow: (null, 'x'),
              title: long,
              meta: [longArtist, '2017', '8 songs'],
              badge: a.badge,
              tracks: a.tracks,
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull, reason: 'width $w');
    }
  });

  uiTest('B3: the Songs table drops columns instead of collapsing', (tester) async {
    addTracks();
    await pumpOne(tester, const SongsPage(), size: const Size(480, 700));
    expect(tester.takeException(), isNull);
    expect(find.text('Year'), findsNothing);
    expect(find.text('Format'), findsNothing);
    await pumpOne(tester, const SongsPage(), size: const Size(1200, 700));
    expect(find.text('Year'), findsOneWidget);
  });

  uiTest('B4: Space on a focused button presses it and does not also toggle play', (tester) async {
    addTracks();
    nav.push('album', lib.albums.first.key);
    await pumpApp(tester);
    await tester.pumpAndSettle();
    Focus.of(tester.element(find.text('Shuffle'))).requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(engine.playing, isFalse, reason: 'Space went to the button only');
    expect(engine.queue.shuffle, isTrue, reason: 'the button was pressed');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    expect(engine.playing, isTrue, reason: 'with nothing focused Space is play/pause');
  });

  uiTest('B5 + keyboard: Enter plays the focused song; ↓ moves focus and selection', (tester) async {
    addTracks();
    nav.go('songs');
    await pumpApp(tester);
    await tester.pumpAndSettle();
    final rows = find.byType(TrackRow);
    await tester.tap(rows.at(1));
    await tester.pump();
    expect(selection.length, 1);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    final second = tester.widget<TrackRow>(rows.at(2)).track;
    expect(selection.has(second.id), isTrue, reason: 'selection follows the focus');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(engine.current?.id, second.id);
  });

  uiTest('B6: search takes the focus after a Tab and Esc closes it from anywhere', (tester) async {
    addTracks();
    await pumpApp(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    nav.setSearch(true);
    await tester.pumpAndSettle();
    expect(typing, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab); // to the close button
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(nav.search, isFalse);
  });

  uiTest('B7: plain lyrics are drawn at full strength, not as disabled buttons', (tester) async {
    addTracks(albums: 1, per: 1, lyrics: 'First plain line\nSecond plain line');
    engine.queue.playNow([lib.tracks.first.id]);
    await pumpOne(tester, const LyricsView());
    final line = find.text('First plain line');
    expect(line, findsOneWidget);
    expect(find.ancestor(of: line, matching: find.byType(Clickable)), findsNothing);
    expect(find.ancestor(of: line, matching: find.byType(Opacity)), findsNothing);
  });

  uiTest('B8: synced lyrics follow a far seek', (tester) async {
    final lrc = [for (var i = 0; i < 200; i++) '[${(i ~/ 60).toString().padLeft(2, '0')}:${(i % 60).toString().padLeft(2, '0')}.00]Line $i']
        .join('\n');
    addTracks(albums: 1, per: 1, lyrics: lrc);
    engine.queue.playNow([lib.tracks.first.id]);
    await pumpOne(tester, const LyricsView());
    engine.position.value = const Duration(seconds: 180, milliseconds: 500);
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    final line = find.text('Line 180');
    expect(line, findsOneWidget);
    final y = tester.getCenter(line).dy;
    expect(y, inInclusiveRange(0, 800), reason: 'the current line is on screen');
  });

  uiTest('C1 + C2: the empty Home picks a folder in place and shows scan progress', (tester) async {
    await pumpOne(tester, const NoMusic());
    expect(tester.widget<PillButton>(find.widgetWithText(PillButton, 'Choose folder')).onTap, addMusicFolder);
    lib.scan.value = (1200, 20000);
    await tester.pump();
    expect(find.text('Reading your music…'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    lib.scan.value = null;
  });

  uiTest('C4: a song from search plays its album from that song', (tester) async {
    addTracks();
    await pumpApp(tester);
    nav.setSearch(true);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Song 3 of Album B');
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(engine.current?.title, 'Song 3 of Album B');
    expect(engine.queue.items.length, 5, reason: 'the whole album is queued');
  });

  uiTest('C5: right-click on an album card offers Play next and Add to queue', (tester) async {
    addTracks();
    nav.go('albums');
    await pumpApp(tester);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Album A'), buttons: kSecondaryButton);
    await tester.pumpAndSettle();
    expect(find.text('Play next'), findsOneWidget);
    expect(find.text('Add to queue'), findsOneWidget);
    await tester.tap(find.text('Add to queue'));
    await tester.pumpAndSettle();
    expect(engine.queue.items.length, 5);
    expect(find.text('Undo'), findsOneWidget, reason: 'the toast can undo it');
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(engine.queue.items.length, 1, reason: 'only the song that started playing stays');
  });

  uiTest('C6: the sort order survives navigation', (tester) async {
    addTracks();
    nav.go('albums');
    await pumpApp(tester);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sort: Title'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Year'));
    await tester.pumpAndSettle();
    nav.go('home');
    await tester.pumpAndSettle();
    nav.go('albums');
    await tester.pumpAndSettle();
    expect(find.text('Sort: Year'), findsOneWidget);
  });

  test('C7: click, Ctrl+click and Shift+click select like Explorer', () {
    final list = [for (var i = 0; i < 10; i++) Track(id: i, title: '$i')];
    final s = Selection()..click(list, 2);
    s.click(list, 5, toggle: true);
    expect(s.ids, {2, 5});
    s.click(list, 8, range: true);
    expect(s.ids, {5, 6, 7, 8});
    s.click(list, 2, toggle: true);
    expect(s.tracks.map((t) => t.id), [2, 5, 6, 7, 8]);
    s.selectAll();
    expect(s.length, 10);
  });

  uiTest('C8: a toast sits above the player bar, never over it', (tester) async {
    await pumpOne(tester, const SizedBox());
    toast(null, 'Hello', actions: [('Show queue', () {})]);
    await tester.pumpAndSettle();
    final bar = tester.widget<SnackBar>(find.byType(SnackBar));
    expect((bar.margin as EdgeInsets).bottom, greaterThanOrEqualTo(128));
    expect(find.text('Show queue'), findsOneWidget);
  });

  uiTest('C9: rail, page, queue and player bar are separate focus regions', (tester) async {
    await pumpApp(tester);
    for (final t in [Rail, PlayerBar]) {
      expect(find.ancestor(of: find.byType(t), matching: find.byType(FocusTraversalGroup)), findsWidgets);
    }
  });

  test('C10: an artist with no album of their own is "2 songs", not "0 albums · 2 songs"', () {
    final a = Artist('Guest')..appearsOn.addAll([Track(id: 1, title: 'a'), Track(id: 2, title: 'b')]);
    expect(artistMeta(a), '2 songs');
  });

  uiTest('U1 + U5: badges are neutral and every text colour is readable', (tester) async {
    await pumpOne(tester, const FormatBadge('FLAC 24/96'));
    expect(tester.widget<Text>(find.text('FLAC 24/96')).style!.color, isNot(C.accent));
    for (final bg in [C.bg, C.raised1, C.raised2, C.raised3]) {
      for (final fg in [C.text, C.dim, C.faint]) {
        expect(contrast(fg, bg), greaterThanOrEqualTo(4.5), reason: '$fg on $bg');
      }
    }
  });

  uiTest('U2: the focus ring does not move the content', (tester) async {
    const key = Key('inner');
    await pumpOne(
      tester,
      Center(
        child: Clickable(
          onTap: () {},
          child: const SizedBox(key: key, width: 40, height: 40),
        ),
      ),
    );
    expect(tester.getTopLeft(find.byKey(key)), tester.getTopLeft(find.byType(AnimatedContainer)));
  });

  uiTest('U3: album cards fit 130 % and 150 % text', (tester) async {
    addTracks(title: long);
    for (final t in [1.3, 1.5]) {
      await pumpOne(tester, const AlbumsPage(), text: t);
      expect(tester.takeException(), isNull, reason: 'text $t');
    }
  });

  test('U4: five type sizes', () {
    final sizes = {
      for (final s in [T.display, T.title, T.heading, T.body, T.label, T.small, T.caption, T.lyric]) s.fontSize,
    };
    expect(sizes, {44.0, 28.0, 18.0, 14.0, 12.0});
  });

  uiTest('U6: carousel arrows only when there is more to scroll', (tester) async {
    addTracks(albums: 12);
    await pumpOne(tester, AlbumShelf(lib.albums.take(2).toList()));
    await tester.pumpAndSettle();
    expect(find.byTooltip('More'), findsNothing);
    await pumpOne(tester, AlbumShelf(lib.albums));
    await tester.pumpAndSettle();
    expect(find.byTooltip('More'), findsOneWidget);
    expect(find.byTooltip('Back'), findsNothing, reason: 'nothing to the left yet');
  });

  test('U7: the output format reads like a person wrote it', () {
    expect(friendlyFormat('s32 96000 Hz'), '32-bit · 96 kHz');
    expect(friendlyFormat('float 44100 Hz'), '32-bit float · 44.1 kHz');
  });

  uiTest('P1: the maximise button turns into restore', (tester) async {
    await pumpApp(tester);
    expect(find.byIcon(LucideIcons.square), findsOneWidget);
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.handlePlatformMessage(
      'window_manager',
      const StandardMethodCodec().encodeMethodCall(const MethodCall('onEvent', {'eventName': 'maximize'})),
      (_) {},
    );
    await tester.pump();
    expect(find.byIcon(LucideIcons.copy), findsOneWidget);
  });

  uiTest('P5: search leaves the title bar usable', (tester) async {
    await pumpApp(tester);
    nav.setSearch(true);
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.byType(FocusScope).last).dy, greaterThanOrEqualTo(TitleBar.height));
    expect(find.byType(SearchConsole), findsOneWidget);
  });

  uiTest('P7 + P9 + P10: playlist icon, full title tooltip in the bar, quiet disabled buttons', (tester) async {
    await pumpApp(tester);
    expect(find.byIcon(LucideIcons.listVideo), findsNothing);
    expect(find.byIcon(LucideIcons.listMusic), findsWidgets);
    addTracks(albums: 1, per: 1, title: long);
    engine.queue.playNow([lib.tracks.first.id]);
    engine.notifyListeners();
    await tester.pump();
    expect(find.byWidgetPredicate((w) => w is Tooltip && (w.message ?? '').startsWith(long)), findsOneWidget);
    await pumpOne(tester, const PillButton('Play'));
    expect(tester.widget<Opacity>(find.ancestor(of: find.text('Play'), matching: find.byType(Opacity)).first).opacity, lessThan(1));
  });

  uiTest('P8: a long reason fits on an album card', (tester) async {
    // Measure with the real font, not the test font.
    await (FontLoader('Inter')..addFont(rootBundle.load('assets/fonts/Inter-Regular.ttf'))).load();
    addTracks(albums: 1);
    await pumpOne(tester, AlbumShelf(lib.albums, whys: const ['You played this 35 days ago']));
    final p = tester.renderObject<RenderParagraph>(find.text('You played this 35 days ago'));
    expect(p.didExceedMaxLines, isFalse);
  });

  uiTest('P11: no art = a gradient with the album initials, the same every time', (tester) async {
    expect(initialsOf('Velvet Static'), 'VS');
    expect(initialsOf('The Dark Side of the Moon'), 'DS');
    expect(initialsOf('1989'), '19');
    expect(noCoverColors('a\u0000b'), noCoverColors('a\u0000b'));
    expect(noCoverColors('a\u0000b'), isNot(noCoverColors('c\u0000d')));
    await pumpOne(
      tester,
      const SizedBox(
        width: 200,
        child: CoverArt(null, seed: 'Velvet Static\u0000X', label: 'Velvet Static'),
      ),
    );
    expect(find.text('VS'), findsOneWidget);
  });

  uiTest('Multi-select bar, Ctrl+A and Esc', (tester) async {
    addTracks();
    nav.go('songs');
    await pumpApp(tester);
    await tester.pumpAndSettle();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(selection.length, 15);
    expect(find.text('15 selected'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(selection.length, 0);
    // Ctrl+click adds to the selection.
    final rows = find.byType(TrackRow);
    await tester.tap(rows.at(0));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.tap(rows.at(2));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(selection.length, 2);
    // Right-click on a selected row keeps the selection; the menu acts on both.
    await tester.tap(rows.at(2), buttons: kSecondaryButton);
    await tester.pumpAndSettle();
    expect(selection.length, 2);
    expect(find.text('Play 2 songs'), findsOneWidget);
  });

  uiTest('Menu key opens the right-click menu of the focused song', (tester) async {
    addTracks();
    nav.go('songs');
    await pumpApp(tester);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(TrackRow).first);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.contextMenu);
    await tester.pumpAndSettle();
    expect(find.text('Go to album'), findsOneWidget);
  });

  uiTest('Now Playing opens from the bar cover; Esc closes it', (tester) async {
    addTracks();
    engine.queue.playNow([lib.tracks.first.id]);
    await pumpApp(tester);
    await tester.tap(find.byTooltip('Now Playing'));
    await tester.pumpAndSettle();
    expect(nav.nowPlaying, isTrue);
    expect(tester.takeException(), isNull);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(nav.nowPlaying, isFalse);
  });

  uiTest('Mouse back / forward buttons, and the wheel on the volume', (tester) async {
    addTracks();
    nav.go('albums');
    nav.push('album', lib.albums.first.key);
    await pumpApp(tester);
    await tester.pumpAndSettle();
    final g = await tester.createGesture(kind: PointerDeviceKind.mouse, buttons: kBackMouseButton);
    await g.down(const Offset(700, 400));
    await g.up();
    await tester.pumpAndSettle();
    expect(nav.top.page, 'albums');
    final f = await tester.createGesture(kind: PointerDeviceKind.mouse, buttons: kForwardMouseButton);
    await f.down(const Offset(700, 400));
    await f.up();
    await tester.pumpAndSettle();
    expect(nav.top.page, 'album');
    engine.volume = 50;
    final at = tester.getCenter(find.byType(Slider).last);
    await tester.sendEventToBinding(PointerScrollEvent(position: at, scrollDelta: const Offset(0, -100)));
    await tester.pump();
    expect(engine.volume, 55);
  });

  uiTest('C6: scroll position survives navigation', (tester) async {
    addTracks(albums: 20);
    nav.go('songs');
    await pumpApp(tester);
    await tester.pumpAndSettle();
    final pos = tester.state<ScrollableState>(find.byType(Scrollable).at(1)).position;
    pos.jumpTo(600);
    await tester.pump();
    nav.go('albums');
    await tester.pumpAndSettle();
    nav.go('songs');
    await tester.pumpAndSettle();
    expect(tester.state<ScrollableState>(find.byType(Scrollable).at(1)).position.pixels, 600);
  });

  uiTest('Hovering the seek bar shows the time there', (tester) async {
    addTracks(albums: 1, per: 1);
    engine.queue.playNow([lib.tracks.first.id]);
    engine.duration = const Duration(minutes: 4);
    await pumpOne(tester, const Center(child: SizedBox(width: 420, child: SeekBar())));
    final slider = tester.getRect(find.byType(Slider));
    final g = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await g.addPointer(location: Offset(slider.center.dx, slider.center.dy));
    await g.moveTo(Offset(slider.center.dx, slider.center.dy));
    await tester.pump();
    expect(find.text('2:00'), findsOneWidget);
    await g.removePointer();
  });

  uiTest('Dropping songs from the library offers play / queue', (tester) async {
    addTracks();
    await pumpApp(tester);
    final ctx = tester.element(find.byType(Shell));
    onDrop(ctx, [lib.tracks.first.path], const Offset(400, 300));
    await tester.pumpAndSettle();
    expect(find.text('Play next'), findsOneWidget);
  });
}
