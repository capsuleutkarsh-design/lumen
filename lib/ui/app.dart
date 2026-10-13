import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:path/path.dart' as p;

import '../audio/engine.dart';
import '../library/library.dart';
import '../platform/window.dart';
import 'lyrics_view.dart';
import 'pages/albums.dart';
import 'pages/artists.dart';
import 'pages/favourites.dart';
import 'pages/folders.dart';
import 'pages/home.dart';
import 'pages/playlists.dart';
import 'pages/settings.dart';
import 'pages/songs.dart';
import 'player_bar.dart';
import 'queue_panel.dart';
import 'search.dart';
import 'theme.dart';
import 'widgets.dart';

// The app's two long-lived objects, set up in main().
late Library lib;
late Engine engine;
final nav = Nav();

class Place {
  const Place(this.page, [this.arg]);
  final String page;
  final Object? arg;
}

class Nav extends ChangeNotifier {
  final List<Place> _stack = [const Place('home')];
  Place get top => _stack.last;
  bool get canBack => _stack.length > 1;
  bool lyrics = false, queue = false, search = false;

  /// Rail pages reset the stack; detail pages push onto it.
  void go(String page) {
    _stack
      ..clear()
      ..add(Place(page));
    lyrics = false;
    notifyListeners();
  }

  void push(String page, Object arg) {
    _stack.add(Place(page, arg));
    lyrics = false;
    notifyListeners();
  }

  void back() {
    if (lyrics) {
      lyrics = false;
    } else if (canBack) {
      _stack.removeLast();
    }
    notifyListeners();
  }

  void toggleLyrics() {
    lyrics = !lyrics;
    notifyListeners();
  }

  void toggleQueue() {
    queue = !queue;
    notifyListeners();
  }

  void setSearch(bool v) {
    search = v;
    notifyListeners();
  }
}

final shotKey = GlobalKey();

/// Saves the whole window as a PNG (debug screenshot hotkey F12, and tests).
Future<String> captureShot(String name, [String? dir]) async {
  final boundary = shotKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
  final image = await boundary.toImage(pixelRatio: 1);
  final png = await image.toByteData(format: ui.ImageByteFormat.png);
  dir ??= p.join(Directory.current.path, '_scratch', 'shots');
  Directory(dir).createSync(recursive: true);
  final file = p.join(dir, '$name.png');
  File(file).writeAsBytesSync(png!.buffer.asUint8List());
  return file;
}

class App extends StatefulWidget {
  const App({super.key});
  @override
  State<App> createState() => _AppState();
}

class _AppState extends State<App> {
  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_key);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_key);
    super.dispose();
  }

  /// Global keys. Text fields keep their own keys.
  bool _key(KeyEvent e) {
    if (e is KeyUpEvent) return false;
    final k = e.logicalKey;
    if (ctrl && k == LogicalKeyboardKey.keyK) {
      nav.setSearch(!nav.search);
      return true;
    }
    if (nav.search || typing) return false;
    if (e is KeyRepeatEvent && k != LogicalKeyboardKey.arrowLeft && k != LogicalKeyboardKey.arrowRight) return false;
    if (k == LogicalKeyboardKey.space) {
      engine.togglePlay();
    } else if (ctrl && k == LogicalKeyboardKey.arrowLeft) {
      engine.previous();
    } else if (ctrl && k == LogicalKeyboardKey.arrowRight) {
      engine.next();
    } else if (k == LogicalKeyboardKey.arrowLeft) {
      engine.seekBy(const Duration(seconds: -5));
    } else if (k == LogicalKeyboardKey.arrowRight) {
      engine.seekBy(const Duration(seconds: 5));
    } else if (ctrl && k == LogicalKeyboardKey.keyL) {
      nav.toggleLyrics();
    } else if (k == LogicalKeyboardKey.escape && (nav.lyrics || nav.canBack)) {
      nav.back();
    } else if (kDebugMode && k == LogicalKeyboardKey.f12) {
      captureShot('shot_${DateTime.now().millisecondsSinceEpoch}').then((f) => debugPrint('saved $f'));
    } else {
      return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Lumen',
    debugShowCheckedModeBanner: false,
    theme: buildTheme(),
    home: RepaintBoundary(key: shotKey, child: const Shell()),
  );
}

class Shell extends StatelessWidget {
  const Shell({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: C.bg,
    body: ListenableBuilder(
      listenable: nav,
      builder: (context, _) => Stack(
        children: [
          Column(
            children: [
              const TitleBar(),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(S.x4, 0, S.x4, S.x4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Rail(),
                      const SizedBox(width: S.x4),
                      Expanded(
                        child: Column(
                          children: [
                            Expanded(
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Expanded(
                                    child: AnimatedSwitcher(
                                      duration: Motion.normal,
                                      switchInCurve: Motion.curve,
                                      child: KeyedSubtree(
                                        key: ValueKey(nav.lyrics ? 'lyrics' : '${nav.top.page}/${nav.top.arg}'),
                                        child: nav.lyrics ? const LyricsView() : _page(nav.top),
                                      ),
                                    ),
                                  ),
                                  if (nav.queue) ...[const SizedBox(width: S.x4), const SizedBox(width: 340, child: QueuePanel())],
                                ],
                              ),
                            ),
                            const SizedBox(height: S.x4),
                            const PlayerBar(),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          if (nav.search) const SearchConsole(),
        ],
      ),
    ),
  );

  Widget _page(Place p) => switch (p.page) {
    'albums' => const AlbumsPage(),
    'album' => AlbumPage(p.arg as String),
    'artists' => const ArtistsPage(),
    'artist' => ArtistPage(p.arg as String),
    'songs' => const SongsPage(),
    'folders' => const FoldersPage(),
    'playlists' => const PlaylistsPage(),
    'playlist' => PlaylistPage(p.arg as int),
    'favourites' => const FavouritesPage(),
    'settings' => const SettingsPage(),
    _ => const HomePage(),
  };
}

class TitleBar extends StatelessWidget {
  const TitleBar({super.key});
  @override
  Widget build(BuildContext context) => SizedBox(
    height: 40,
    child: Row(
      children: [
        Expanded(
          child: dragArea(
            Container(
              color: Colors.transparent,
              padding: const EdgeInsets.only(left: S.x5),
              child: Row(
                children: [
                  const AppMark(size: 18),
                  const SizedBox(width: S.x2),
                  Text(
                    'Lumen',
                    style: T.caption.copyWith(color: C.dim, fontWeight: FontWeight.w500),
                  ),
                  const Spacer(),
                  const ScanPill(),
                  const SizedBox(width: S.x3),
                ],
              ),
            ),
          ),
        ),
        if (isDesktop) ...[
          _WinButton(LucideIcons.minus, 'Minimize', minimizeWindow),
          _WinButton(LucideIcons.square, 'Maximize', toggleMaximize, iconSize: 12),
          _WinButton(LucideIcons.x, 'Close', closeWindow, danger: true),
        ],
      ],
    ),
  );
}

class _WinButton extends StatefulWidget {
  const _WinButton(this.icon, this.tooltip, this.onTap, {this.danger = false, this.iconSize = 15});
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool danger;
  final double iconSize;
  @override
  State<_WinButton> createState() => _WinButtonState();
}

class _WinButtonState extends State<_WinButton> {
  bool _hover = false;
  @override
  Widget build(BuildContext context) => MouseRegion(
    onEnter: (_) => setState(() => _hover = true),
    onExit: (_) => setState(() => _hover = false),
    child: GestureDetector(
      onTap: widget.onTap,
      child: AnimatedContainer(
        duration: Motion.fast,
        width: 46,
        height: 40,
        color: _hover ? (widget.danger ? const Color(0xFFC42B1C) : C.raised2) : Colors.transparent,
        child: Icon(widget.icon, size: widget.iconSize, color: _hover ? C.text : C.dim),
      ),
    ),
  );
}

/// The Lumen logo (assets/brand/lumen.svg, rendered by tool/brand/build_brand.py).
class AppMark extends StatelessWidget {
  const AppMark({super.key, this.size = 32});
  final double size;
  @override
  Widget build(BuildContext context) =>
      Image.asset('assets/brand/lumen_256.png', width: size, height: size, filterQuality: FilterQuality.medium);
}

/// "Scanning 12 / 30" while the library scan runs.
class ScanPill extends StatelessWidget {
  const ScanPill({super.key});
  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: lib.scan,
    builder: (_, s, _) => AnimatedSwitcher(
      duration: Motion.normal,
      child: s == null
          ? const SizedBox.shrink()
          : Row(
              key: const ValueKey('scan'),
              children: [
                SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.5,
                    color: C.accent,
                    backgroundColor: C.raised3,
                    value: s.$2 == 0 ? null : s.$1 / s.$2,
                  ),
                ),
                const SizedBox(width: S.x2),
                Text(s.$2 == 0 ? 'Checking library…' : 'Scanning ${s.$1} / ${s.$2}', style: T.caption),
              ],
            ),
    ),
  );
}

class Rail extends StatelessWidget {
  const Rail({super.key});
  static const items = [
    ('home', LucideIcons.house, 'Home'),
    ('albums', LucideIcons.disc3, 'Albums'),
    ('artists', LucideIcons.micVocal, 'Artists'),
    ('songs', LucideIcons.listMusic, 'Songs'),
    ('folders', LucideIcons.folder, 'Folders'),
    ('playlists', LucideIcons.listVideo, 'Playlists'),
    ('favourites', LucideIcons.heart, 'Favourites'),
  ];

  static String _section(String page) => switch (page) {
    'album' => 'albums',
    'artist' => 'artists',
    'playlist' => 'playlists',
    _ => page,
  };

  @override
  Widget build(BuildContext context) => ListenableBuilder(listenable: nav, builder: (context, _) => _build());

  Widget _build() {
    final current = _section(nav.top.page);
    Widget item(String page, IconData icon, String label, VoidCallback onTap, {bool active = false}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Clickable(
        onTap: onTap,
        tooltip: label,
        radius: R.card - S.x1,
        selected: active,
        hover: C.raised2,
        child: SizedBox(width: 44, height: 44, child: Icon(icon, size: 20, color: active ? C.text : C.faint)),
      ),
    );
    return Panel(
      padding: const EdgeInsets.symmetric(horizontal: S.x2 + 2, vertical: S.x4),
      child: Column(
        children: [
          const AppMark(size: 36),
          const SizedBox(height: S.x6),
          for (final (page, icon, label) in items) item(page, icon, label, () => nav.go(page), active: !nav.lyrics && current == page),
          const Spacer(),
          item('search', LucideIcons.search, 'Search  (Ctrl+K)', () => nav.setSearch(true)),
          item('settings', LucideIcons.settings, 'Settings', () => nav.go('settings'), active: !nav.lyrics && current == 'settings'),
        ],
      ),
    );
  }
}
