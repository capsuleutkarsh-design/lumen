import 'dart:io';
import 'dart:ui' as ui;

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:path/path.dart' as p;
import 'package:window_manager/window_manager.dart';

import '../audio/engine.dart';
import '../audio/sound_control.dart';
import '../library/library.dart';
import '../library/models.dart';
import '../library/tags.dart' show audioExtensions;
import '../platform/android.dart' show lockView, musicAccess, photosStep;
import '../platform/window.dart';
import 'art_accent.dart';
import 'lock_view.dart';
import 'lyrics_view.dart';
import 'mini_player.dart';
import 'now_playing.dart';
import 'phone.dart';
import 'pages/albums.dart';
import 'pages/artists.dart';
import 'pages/browse.dart';
import 'pages/favourites.dart';
import 'pages/folders.dart';
import 'pages/home.dart';
import 'pages/playlists.dart';
import 'pages/settings.dart';
import 'pages/smart_playlists.dart';
import 'pages/songs.dart';
import 'pages/sound.dart';
import 'pages/stats_page.dart';
import 'player_bar.dart';
import 'queue_panel.dart';
import 'search.dart';
import 'theme.dart';
import 'tracks.dart';
import 'widgets.dart';

// The app's two long-lived objects, set up in main().
late Library lib;
late Engine engine;

/// The Sound page's settings, applied to [engine] (boot() calls init). Follows [engine]
/// when a test swaps it; a fresh one has the default settings.
Sound get sound => _sound != null && identical(_sound!.engine, engine) ? _sound! : _sound = Sound(lib, engine);
Sound? _sound;
final nav = Nav();

class Place {
  const Place(this.page, [this.arg]);
  final String page;
  final Object? arg;
  String get id => '$page/$arg';
}

class Nav extends ChangeNotifier {
  final List<Place> _stack = [const Place('home')];
  final List<Place> _forward = [];
  Place get top => _stack.last;
  bool get canBack => _stack.length > 1;
  bool lyrics = false, queue = false, search = false, nowPlaying = false;

  /// Disc mode (only the cover and the spinning disc), and the mini player.
  bool disc = false, mini = false, miniExpanded = false;

  /// Per-page choices that survive navigation (sort order, open folder).
  final memo = <String, Object?>{};

  void _moved() {
    lyrics = false;
    nowPlaying = false;
    selection.clear();
    notifyListeners();
  }

  /// Rail pages reset the stack; detail pages push onto it.
  void go(String page) {
    _stack
      ..clear()
      ..add(Place(page));
    _forward.clear();
    _moved();
  }

  void push(String page, Object arg) {
    _stack.add(Place(page, arg));
    _forward.clear();
    _moved();
  }

  void back() {
    if (disc) return setDisc(false);
    if (nowPlaying) {
      nowPlaying = false;
    } else if (lyrics) {
      lyrics = false;
    } else if (canBack) {
      _forward.add(_stack.removeLast());
      selection.clear();
    }
    notifyListeners();
  }

  /// The mouse's forward button: undo the last Back.
  void forward() {
    if (_forward.isEmpty) return;
    _stack.add(_forward.removeLast());
    _moved();
  }

  void toggleLyrics() {
    lyrics = !lyrics;
    nowPlaying = false;
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

  void setNowPlaying(bool v) {
    nowPlaying = v;
    notifyListeners();
  }

  void setDisc(bool v) {
    disc = v;
    if (!v) leaveFullScreen();
    notifyListeners();
  }

  /// Use [setMini] in mini_player.dart: it also reshapes the window.
  void setMini(bool v, {bool? expanded}) {
    mini = v;
    miniExpanded = expanded ?? miniExpanded;
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

/// Knows when a dialog or menu is on top, so global keys leave it alone.
class _Modals extends NavigatorObserver {
  Route? _top;
  bool get open => _top != null && !_top!.isFirst;
  @override
  void didPush(Route route, Route? previousRoute) => _top = route;
  @override
  void didPop(Route route, Route? previousRoute) => _top = previousRoute;
  @override
  void didRemove(Route route, Route? previousRoute) {
    if (route == _top) _top = previousRoute;
  }
}

final _modals = _Modals();

/// Settings → Theme: 'dark' (the default), 'light' or 'system' (follow Windows).
final appearance = ValueNotifier<String>('dark');

/// Reads the saved theme and switches the colours to it (before the window shows, so it opens in them).
void loadAppearance() {
  appearance.value = lib.setting('appearance') ?? (Platform.isAndroid ? 'system' : 'dark'); // the phone follows its own setting
  C.use(paletteFor(appearance.value, ui.PlatformDispatcher.instance.platformBrightness));
}

void setAppearance(String mode) {
  lib.setSetting('appearance', mode);
  appearance.value = mode;
}

class App extends StatefulWidget {
  const App({super.key});
  @override
  State<App> createState() => _AppState();
}

class _AppState extends State<App> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_key);
    WidgetsBinding.instance.addObserver(this);
    loadAppearance();
    appearance.addListener(_theme);
    watchArtAccent();
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_key);
    WidgetsBinding.instance.removeObserver(this);
    appearance.removeListener(_theme);
    super.dispose();
  }

  @override
  void didChangePlatformBrightness() => _theme();

  static double get _viewWidth => WidgetsBinding.instance.platformDispatcher.views.first.physicalSize.width;
  double _width = _viewWidth;

  /// A toast's side margins are measured for the window it opened in, so one that gets narrower
  /// would squeeze it: a change of width closes it before the next frame is laid out.
  @override
  void didChangeMetrics() {
    if (_viewWidth != _width) messengerKey.currentState?.removeCurrentSnackBar();
    _width = _viewWidth;
  }

  /// Switches the palette and rebuilds every widget (const widgets too, which a plain setState skips).
  void _theme() {
    final p = paletteFor(appearance.value, ui.PlatformDispatcher.instance.platformBrightness);
    if (p == C.palette) return;
    C.use(p);
    setState(() {});
    void dirty(Element e) {
      e.markNeedsBuild();
      e.visitChildren(dirty);
    }

    (context as Element).visitChildren(dirty);
    refreshArtAccent();
    if (isDesktop) windowManager.setBackgroundColor(C.bg).catchError((_) {});
  }

  /// Global keys. Text fields, dialogs, menus and focused buttons/sliders keep their own keys.
  bool _key(KeyEvent e) {
    if (e is KeyUpEvent) return false;
    final k = e.logicalKey;
    if (_modals.open) return false;
    if (ctrl && k == LogicalKeyboardKey.keyK) {
      nav.setSearch(!nav.search);
      return true;
    }
    if (nav.search || typing) return false;
    final focus = FocusManager.instance.primaryFocus?.context;
    final onSlider = focus?.findAncestorWidgetOfExactType<Slider>() != null;
    if (e is KeyRepeatEvent && k != LogicalKeyboardKey.arrowLeft && k != LogicalKeyboardKey.arrowRight) return false;
    if (k == LogicalKeyboardKey.space) {
      if (focus != null && Clickable.ownsSpace(focus)) return false;
      engine.togglePlay();
    } else if ((k == LogicalKeyboardKey.arrowLeft || k == LogicalKeyboardKey.arrowRight) && onSlider) {
      return false;
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
    } else if (ctrl && k == LogicalKeyboardKey.keyA) {
      selection.selectAll();
    } else if (ctrl && k == LogicalKeyboardKey.keyF && nav.top.page == 'songs' && !nav.lyrics) {
      songsFilterFocus.requestFocus();
    } else if (k == LogicalKeyboardKey.keyD && !ctrl && !nav.mini) {
      nav.setDisc(!nav.disc);
    } else if (k == LogicalKeyboardKey.f11 && nav.disc) {
      toggleFullScreen();
    } else if (k == LogicalKeyboardKey.escape && nav.disc) {
      nav.setDisc(false);
    } else if (k == LogicalKeyboardKey.escape && nav.nowPlaying) {
      nav.setNowPlaying(false);
    } else if (k == LogicalKeyboardKey.escape && selection.length > 0) {
      selection.clear();
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
    title: 'Gleo',
    debugShowCheckedModeBanner: false,
    theme: buildTheme(),
    scaffoldMessengerKey: messengerKey,
    navigatorObservers: [_modals],
    // Around the navigator, so screenshots include menus, dialogs and toasts.
    builder: (context, child) {
      final shot = RepaintBoundary(key: shotKey, child: child);
      return Platform.isAndroid ? AnnotatedRegion(value: phoneBars(), child: shot) : shot;
    },
    home: const Shell(),
  );
}

class Shell extends StatefulWidget {
  const Shell({super.key});
  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  bool _dragging = false;

  /// Mouse back / forward buttons move through pages.
  void _pointer(PointerDownEvent e) {
    if (e.buttons & kBackMouseButton != 0) nav.back();
    if (e.buttons & kForwardMouseButton != 0) nav.forward();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([nav, musicAccess, photosStep, lockView]),
    builder: (context, _) => Stack(
      fit: StackFit.expand,
      children: [
        // Over the phone's lock screen only the lock-screen view shows; the app keeps its place behind it.
        Offstage(
          offstage: lockView.value,
          child: TickerMode(
            enabled: !lockView.value,
            child: !musicAccess.value || photosStep.value
                ? const MusicAccess()
                : nav.mini
                ? const MiniPlayer()
                : phoneLayout(context)
                ? const PhoneShell()
                : _shell(context),
          ),
        ),
        if (lockView.value) const LockView(),
      ],
    ),
  );

  /// Files dropped from Explorer (desktop only).
  Widget _drop(Widget child) => !isDesktop
      ? child
      : DropTarget(
          onDragEntered: (_) => setState(() => _dragging = true),
          onDragExited: (_) => setState(() => _dragging = false),
          onDragDone: (d) {
            setState(() => _dragging = false);
            onDrop(context, [for (final f in d.files) f.path], d.globalPosition);
          },
          child: child,
        );

  Widget _shell(BuildContext context) => Scaffold(
    backgroundColor: C.bg,
    body: Listener(
      onPointerDown: _pointer,
      child: _drop(
        ListenableBuilder(
          listenable: nav,
          builder: (context, _) => Stack(
            children: [
              // Under Now Playing or Disc mode the window is covered: its animations
              // (the playing bars in a list) pause, so nothing draws there for nothing.
              Covered(
                covered: nav.nowPlaying || nav.disc,
                child: Column(
                  children: [
                    const SizedBox(height: TitleBar.height), // the title bar is drawn on top (below)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(S.x4, 0, S.x4, S.x4),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            FocusTraversalGroup(child: const Rail()),
                            const SizedBox(width: S.x4),
                            Expanded(
                              child: Column(
                                children: [
                                  Expanded(
                                    child: LayoutBuilder(
                                      builder: (context, c) => Row(
                                        crossAxisAlignment: CrossAxisAlignment.stretch,
                                        children: [
                                          Expanded(
                                            child: FocusTraversalGroup(
                                              child: Stack(
                                                children: [
                                                  Positioned.fill(
                                                    child: AnimatedSwitcher(
                                                      duration: Motion.normal,
                                                      switchInCurve: Motion.curve,
                                                      child: KeyedSubtree(
                                                        key: ValueKey(nav.lyrics ? 'lyrics' : nav.top.id),
                                                        child: nav.lyrics ? const LyricsView() : pageFor(nav.top),
                                                      ),
                                                    ),
                                                  ),
                                                  const Positioned(
                                                    left: 0,
                                                    right: 0,
                                                    bottom: S.x4,
                                                    child: Center(child: SelectionBar()),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                          if (nav.queue) ...[
                                            const SizedBox(width: S.x4),
                                            SizedBox(
                                              width: c.maxWidth < 900 ? 300 : 340,
                                              child: FocusTraversalGroup(child: const QueuePanel()),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: S.x4),
                                  FocusTraversalGroup(child: const PlayerBar()),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // Now Playing's glow runs under the (transparent) title bar, which stays usable on top.
              Positioned.fill(
                child: MediaQuery(
                  data: MediaQuery.of(context).copyWith(padding: const EdgeInsets.only(top: TitleBar.height)),
                  child: AnimatedSwitcher(
                    duration: Motion.slow,
                    switchInCurve: Motion.curve,
                    switchOutCurve: Curves.easeInCubic,
                    transitionBuilder: (child, a) => FadeTransition(
                      opacity: a,
                      child: ScaleTransition(scale: Tween(begin: 0.98, end: 1.0).animate(a), child: child),
                    ),
                    child: nav.nowPlaying ? const NowPlaying(key: ValueKey('np')) : const SizedBox.shrink(),
                  ),
                ),
              ),
              const Positioned(top: 0, left: 0, right: 0, child: TitleBar()),
              if (nav.search) const SearchConsole(),
              if (nav.disc) const Positioned.fill(child: DiscMode()),
              if (_dragging) const _DropHint(),
            ],
          ),
        ),
      ),
    ),
  );
}

Widget pageFor(Place p) => switch (p.page) {
  'albums' => const AlbumsPage(),
  'album' => AlbumPage(p.arg as String),
  'artists' => const ArtistsPage(),
  'artist' => ArtistPage(p.arg as String),
  'songs' => const SongsPage(),
  'folders' => const FoldersPage(),
  'folder' => FoldersPage(dir: p.arg as String),
  'library' => const LibraryPage(),
  'playlists' => const PlaylistsPage(),
  'playlist' => PlaylistPage(p.arg as int),
  'smart' => SmartPlaylistPage(p.arg as int),
  'genres' => const GenresPage(),
  'genre' => GenrePage(p.arg as String),
  'years' => const YearsPage(),
  'composers' => const ComposersPage(),
  'composer' => ComposerPage(p.arg as String),
  'duplicates' => const DuplicatesPage(),
  'stats' => const StatsPage(),
  'favourites' => const FavouritesPage(),
  'settings' => const SettingsPage(),
  'sound' => const SoundPage(),
  _ => const HomePage(),
};

/// Files or folders dropped from Explorer: folders join the library (after
/// asking); songs already in the library get the play / queue menu.
Future<void> onDrop(BuildContext context, List<String> paths, Offset at) async {
  final dirs = [
    for (final x in paths)
      if (FileSystemEntity.isDirectorySync(x)) x,
  ];
  final files = [
    for (final x in paths)
      if (!dirs.contains(x) && audioExtensions.contains(p.extension(x).toLowerCase())) x,
  ];
  bool inLibrary(String x) => lib.folders.any((f) => p.equals(f, x) || p.isWithin(f, x));
  if (dirs.isNotEmpty) {
    final add = [
      for (final d in dirs)
        if (!inLibrary(d)) d,
    ];
    if (add.isEmpty) {
      toast(context, dirs.length == 1 ? 'That folder is already in your library' : 'Those folders are already in your library');
    } else if (await confirm(
      context,
      add.length == 1 ? 'Add “${p.basename(add.first)}” to your library?' : 'Add ${add.length} folders to your library?',
      '${add.join('\n')}\n\nGleo reads these folders and watches them for new music. Nothing is copied or changed.',
      action: 'Add',
    )) {
      lib.folders = [...lib.folders, ...add];
    }
  }
  if (files.isEmpty || !context.mounted) return;
  final byPath = {for (final t in lib.tracks) t.path.toLowerCase(): t};
  final known = <Track>[for (final f in files) ?byPath[f.toLowerCase()]];
  final unknown = [
    for (final f in files)
      if (!byPath.containsKey(f.toLowerCase())) f,
  ];
  if (known.isNotEmpty) await showTrackMenu(context, at, known);
  if (unknown.isNotEmpty && context.mounted) {
    final parents = {for (final f in unknown) p.dirname(f)}.where((d) => !inLibrary(d)).toList();
    toast(
      context,
      '${plural(unknown.length, 'song')} ${unknown.length == 1 ? 'is' : 'are'} not in your library yet',
      actions: [
        if (parents.isNotEmpty) ('Add folder', () => lib.folders = [...lib.folders, ...parents]),
      ],
    );
  }
}

class _DropHint extends StatelessWidget {
  const _DropHint();
  @override
  Widget build(BuildContext context) => Positioned.fill(
    child: IgnorePointer(
      child: Container(
        margin: const EdgeInsets.all(S.x4),
        decoration: BoxDecoration(
          color: C.scrim,
          borderRadius: BorderRadius.circular(R.panel),
          border: Border.all(color: C.accent, width: 1.5),
        ),
        alignment: Alignment.center,
        child: const EmptyState(
          icon: LucideIcons.import,
          title: 'Drop to add or play',
          body: 'Folders join your library. Songs already in it can be played or queued.',
        ),
      ),
    ),
  );
}

class TitleBar extends StatefulWidget {
  const TitleBar({super.key});
  static const height = 40.0;
  @override
  State<TitleBar> createState() => _TitleBarState();
}

class _TitleBarState extends State<TitleBar> with WindowListener {
  /// The native side reports hover over the maximise button, which it owns
  /// so Windows 11 can show Snap Layouts there.
  static const _channel = MethodChannel('gleo/titlebar');
  bool _max = false, _maxHover = false;

  @override
  void initState() {
    super.initState();
    if (!isDesktop) return;
    windowManager.addListener(this);
    windowManager.isMaximized().then((m) {
      if (mounted) setState(() => _max = m);
    });
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'maxHover' && mounted) setState(() => _maxHover = call.arguments == true);
    });
  }

  @override
  void dispose() {
    if (isDesktop) {
      windowManager.removeListener(this);
      _channel.setMethodCallHandler(null);
    }
    super.dispose();
  }

  @override
  void onWindowMaximize() => setState(() => _max = true);
  @override
  void onWindowUnmaximize() => setState(() => _max = false);

  @override
  Widget build(BuildContext context) => SizedBox(
    height: TitleBar.height,
    child: Row(
      children: [
        Expanded(
          child: dragArea(
            Container(
              color: Colors.transparent,
              padding: const EdgeInsets.only(left: S.x5),
              child: Row(
                children: [
                  const Wordmark(height: 20),
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
          _WinButton(_max ? LucideIcons.copy : LucideIcons.square, _max ? 'Restore' : 'Maximize', toggleMaximize, iconSize: 12, hover: _maxHover),
          _WinButton(LucideIcons.x, 'Close', closeWindow, danger: true),
        ],
      ],
    ),
  );
}

class _WinButton extends StatefulWidget {
  const _WinButton(this.icon, this.label, this.onTap, {this.danger = false, this.iconSize = 15, this.hover = false});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool danger, hover;
  final double iconSize;
  @override
  State<_WinButton> createState() => _WinButtonState();
}

class _WinButtonState extends State<_WinButton> {
  bool _hover = false;
  @override
  Widget build(BuildContext context) {
    final h = _hover || widget.hover;
    return Semantics(
      button: true,
      label: widget.label,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: Motion.fast,
            width: 46,
            height: TitleBar.height,
            color: h ? (widget.danger ? C.closeHover : C.raised2) : Colors.transparent,
            child: Icon(widget.icon, size: widget.iconSize, color: h ? C.text : C.dim),
          ),
        ),
      ),
    );
  }
}

/// The Gleo app icon, a gold g on midnight (assets/brand/gleo.svg, rendered by tool/brand/build_brand.py).
class AppMark extends StatelessWidget {
  const AppMark({super.key, this.size = 32});
  final double size;
  @override
  Widget build(BuildContext context) =>
      Image.asset('assets/brand/gleo_256.png', width: size, height: size, filterQuality: FilterQuality.medium, semanticLabel: 'Gleo');
}

/// The gleo wordmark, for where there is room: gold, or a deeper gold on the light theme.
class Wordmark extends StatelessWidget {
  const Wordmark({super.key, this.height = 24});
  final double height;
  @override
  Widget build(BuildContext context) => Image.asset(
    C.isLight ? 'assets/brand/gleo_wordmark_light.png' : 'assets/brand/gleo_wordmark.png',
    height: height,
    filterQuality: FilterQuality.medium,
    semanticLabel: 'Gleo',
  );
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
                    color: C.text,
                    backgroundColor: C.raised3,
                    value: s.$2 == 0 ? null : s.$1 / s.$2,
                  ),
                ),
                const SizedBox(width: S.x2),
                Text(
                  s.$2 == 0 ? 'Checking for new music…' : 'Reading ${fmtInt(s.$1)} of ${fmtInt(s.$2)}',
                  textScaler: TextScaler.noScaling,
                  style: T.caption,
                ),
              ],
            ),
    ),
  );
}

class Rail extends StatelessWidget {
  const Rail({super.key});
  static final _scroll = ScrollController(); // one rail at a time
  static const items = [
    ('home', LucideIcons.house, 'Home'),
    ('albums', LucideIcons.disc3, 'Albums'),
    ('artists', LucideIcons.users, 'Artists'),
    ('songs', LucideIcons.music, 'Songs'),
    ('folders', LucideIcons.folder, 'Folders'),
    ('browse', LucideIcons.compass, 'Browse  (genres, years, composers, duplicates, statistics)'),
    ('playlists', LucideIcons.listMusic, 'Playlists'),
    ('favourites', LucideIcons.heart, 'Favourites'),
  ];

  static String _section(String page) => switch (page) {
    'album' => 'albums',
    'artist' => 'artists',
    'playlist' || 'smart' => 'playlists',
    'folder' => 'folders',
    'genres' || 'genre' || 'years' || 'composers' || 'composer' || 'duplicates' || 'stats' => 'browse',
    _ => page,
  };

  @override
  Widget build(BuildContext context) => ListenableBuilder(listenable: nav, builder: (context, _) => _build(context));

  Widget _build(BuildContext context) {
    final current = _section(nav.top.page);
    final size = MediaQuery.sizeOf(context);
    final wide = size.width >= 1280; // labels beside the icons; icons only when narrow
    final gap = size.height < 720 ? 0.0 : S.x1 / 2;
    Widget item(String page, IconData icon, String label, VoidCallback onTap, {bool active = false}) {
      final name = label.split('  ').first;
      return Padding(
        padding: EdgeInsets.symmetric(vertical: gap),
        child: Clickable(
          onTap: onTap,
          tooltip: wide && name == label ? null : label,
          semanticLabel: name,
          radius: R.card - S.x1,
          selected: active,
          hover: C.raised2,
          selectedColor: C.raised3,
          child: SizedBox(
            height: 44,
            child: Row(
              children: [
                SizedBox(width: 44, child: Icon(icon, size: 20, color: active ? C.text : C.faint)),
                if (wide)
                  Expanded(
                    child: Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: T.label.copyWith(color: active ? C.text : C.dim),
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
    }

    return Panel(
      padding: const EdgeInsets.symmetric(horizontal: S.x3, vertical: S.x4),
      // Search and Settings sit at the bottom; the rail scrolls (with a thin scrollbar) if the window is very short.
      child: SizedBox(
        width: wide ? 152 : 44,
        child: ScrollConfiguration(
          behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
          child: Scrollbar(
            controller: _scroll,
            thumbVisibility: true, // drawn only when something is out of view
            thickness: 3,
            child: CustomScrollView(
              controller: _scroll,
              slivers: [
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Column(
                    children: [
                      for (final (page, icon, label) in items)
                        item(page, icon, label, () => nav.go(page == 'browse' ? browseTab : page), active: !nav.lyrics && current == page),
                      const Spacer(),
                      const SizedBox(height: S.x6),
                      item('search', LucideIcons.search, 'Search  (Ctrl+K)', () => nav.setSearch(true)),
                      item('sound', LucideIcons.slidersVertical, 'Sound', () => nav.go('sound'), active: !nav.lyrics && current == 'sound'),
                      item('settings', LucideIcons.settings, 'Settings', () => nav.go('settings'), active: !nav.lyrics && current == 'settings'),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
