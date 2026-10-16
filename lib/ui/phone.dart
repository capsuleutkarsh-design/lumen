import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../platform/android.dart';
import '../platform/window.dart' show isTouch;
import 'app.dart';
import 'lyrics_view.dart';
import 'now_playing.dart';
import 'queue_panel.dart';
import 'search.dart';
import 'theme.dart';
import 'widgets.dart';

/// A phone (a touch screen under 600 dp on its short side, in either orientation) gets the phone layout;
/// tablets and every desktop window keep the desktop one.
bool phoneLayout(BuildContext context) => isTouch && MediaQuery.sizeOf(context).shortestSide < 600;

/// Android's status and navigation bars in the theme's colours, with icons that read on them (dark on
/// light), so there is no black strip under the light theme's navigation. (Android 15+ draws the app
/// behind both bars anyway and ignores the colours.) Given as an AnnotatedRegion around the app: a plain
/// SystemChrome call loses to MaterialApp, which sets a black navigation bar on every build.
SystemUiOverlayStyle phoneBars() {
  final icons = C.isLight ? Brightness.dark : Brightness.light;
  return SystemUiOverlayStyle(
    statusBarColor: C.bg,
    statusBarIconBrightness: icons,
    statusBarBrightness: C.palette.brightness,
    systemNavigationBarColor: C.raised1, // the bottom navigation's colour
    systemNavigationBarDividerColor: C.border,
    systemNavigationBarIconBrightness: icons,
    systemNavigationBarContrastEnforced: false,
  );
}

/// The phone layout: the page, a mini player above the bottom navigation, and Now Playing, the queue,
/// search and Disc mode over everything. Android's Back closes the top-most of those first.
class PhoneShell extends StatefulWidget {
  const PhoneShell({super.key});
  @override
  State<PhoneShell> createState() => _PhoneShellState();
}

class _PhoneShellState extends State<PhoneShell> {
  StreamSubscription<String>? _messages;

  @override
  void initState() {
    super.initState();
    // The engine's messages (a song can't be played, ...) as toasts: the desktop player bar isn't here.
    _messages = engine.messages.listen((m) {
      if (mounted) toast(context, m);
    });
  }

  @override
  void dispose() {
    _messages?.cancel();
    super.dispose();
  }

  Widget _page() => Padding(
    padding: const EdgeInsets.symmetric(horizontal: S.x3),
    // Pull down on any list to look for new music (Android has no folder watching).
    child: RefreshIndicator(
      color: C.accent,
      backgroundColor: C.raised2,
      notificationPredicate: (n) => n.metrics.axis == Axis.vertical,
      onRefresh: lib.rescan,
      child: AnimatedSwitcher(
        duration: Motion.normal,
        switchInCurve: Motion.curve,
        child: KeyedSubtree(key: ValueKey(nav.lyrics ? 'lyrics' : nav.top.id), child: nav.lyrics ? const LyricsView() : pageFor(nav.top)),
      ),
    ),
  );

  bool get _overlay => nav.disc || nav.nowPlaying || nav.queue || nav.search || nav.lyrics || nav.canBack;

  void back() {
    if (nav.search) return nav.setSearch(false);
    if (nav.queue) return nav.toggleQueue();
    nav.back();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: nav,
    builder: (context, _) => PopScope(
      canPop: !_overlay,
      onPopInvokedWithResult: (popped, _) {
        if (!popped) back();
      },
      child: Scaffold(
        backgroundColor: C.bg,
        resizeToAvoidBottomInset: false,
        body: Stack(
          children: [
            TickerMode(
              enabled: !nav.nowPlaying && !nav.disc && !nav.queue,
              // Landscape: the navigation moves to the side, so the page keeps the short height.
              child: MediaQuery.orientationOf(context) == Orientation.landscape
                  ? Row(
                      children: [
                        const _BottomNav(side: true),
                        Expanded(
                          child: SafeArea(
                            left: false,
                            child: Column(
                              children: [
                                Expanded(child: _page()),
                                const PhoneBar(),
                              ],
                            ),
                          ),
                        ),
                      ],
                    )
                  : Column(
                      children: [
                        const SafeArea(bottom: false, child: _TopBar()),
                        Expanded(child: SafeArea(top: false, bottom: false, child: _page())),
                        const PhoneBar(),
                        const _BottomNav(),
                      ],
                    ),
            ),
            if (nav.queue) Positioned.fill(child: _Sheet(child: const QueuePanel())),
            AnimatedSwitcher(
              duration: Motion.slow,
              switchInCurve: Motion.curve,
              transitionBuilder: (child, a) => SlideTransition(
                position: Tween(begin: const Offset(0, 0.08), end: Offset.zero).animate(a),
                child: FadeTransition(opacity: a, child: child),
              ),
              // Swipe down to close, as it was swiped up to open.
              child: nav.nowPlaying
                  ? GestureDetector(
                      key: const ValueKey('np'),
                      onVerticalDragEnd: (d) {
                        if ((d.primaryVelocity ?? 0) > 300) nav.setNowPlaying(false);
                      },
                      child: const NowPlaying(),
                    )
                  : const SizedBox.shrink(),
            ),
            if (nav.search)
              Positioned.fill(
                child: ColoredBox(
                  color: C.bg,
                  child: const SafeArea(child: SearchConsole()),
                ),
              ),
            if (nav.disc) const Positioned.fill(child: DiscMode()),
          ],
        ),
      ),
    ),
  );
}

/// A full-screen panel under the status bar and over the navigation bar.
class _Sheet extends StatelessWidget {
  const _Sheet({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => ColoredBox(
    color: C.bg,
    child: SafeArea(
      child: Padding(padding: const EdgeInsets.all(S.x2), child: child),
    ),
  );
}

/// Back (on inner pages), the logo, the scan progress, Search and Settings.
class _TopBar extends StatelessWidget {
  const _TopBar();
  @override
  Widget build(BuildContext context) => ListenableBuilder(listenable: nav, builder: (context, _) => _build());

  Widget _build() => SizedBox(
    height: 56,
    child: Row(
      children: [
        if (nav.canBack || nav.lyrics)
          IconBtn(LucideIcons.chevronLeft, size: 22, color: C.text, tooltip: 'Back', onTap: nav.back)
        else ...[
          const SizedBox(width: S.x4),
          const Wordmark(height: 28),
        ],
        const Spacer(),
        const ScanPill(),
        IconBtn(LucideIcons.search, size: 20, color: C.text, tooltip: 'Search', onTap: () => nav.setSearch(true)),
        IconBtn(
          LucideIcons.settings,
          key: const ValueKey('nav.settings'),
          size: 20,
          color: C.text,
          active: nav.top.page == 'settings',
          tooltip: 'Settings',
          onTap: () => nav.go('settings'),
        ),
        const SizedBox(width: S.x1),
      ],
    ),
  );
}

class _BottomNav extends StatelessWidget {
  const _BottomNav({this.side = false});

  /// Landscape: a column of icons on the left (with Back, Search and Settings), no labels.
  final bool side;

  static const items = [
    ('home', LucideIcons.house, 'Home'),
    ('songs', LucideIcons.music, 'Songs'),
    ('albums', LucideIcons.disc3, 'Albums'),
    ('artists', LucideIcons.micVocal, 'Artists'),
    ('library', LucideIcons.libraryBig, 'Library'),
  ];

  /// The tab a page belongs to. Settings and Sound (from the top bar and Now Playing) light none.
  static String _section(String page) => switch (page) {
    'album' => 'albums',
    'artist' => 'artists',
    'home' || 'albums' || 'artists' || 'songs' => page,
    'settings' || 'sound' => '',
    _ => 'library',
  };

  @override
  Widget build(BuildContext context) => ListenableBuilder(listenable: nav, builder: (context, _) => _build(context));

  Widget _build(BuildContext context) {
    final current = nav.lyrics ? '' : _section(nav.top.page);
    if (side) {
      Widget pill(IconData icon, String label, VoidCallback onTap, {bool on = false}) => Clickable(
        onTap: onTap,
        semanticLabel: label,
        radius: R.pill,
        child: Container(
          width: 56,
          height: 40,
          decoration: BoxDecoration(color: on ? C.accentSoft : Colors.transparent, borderRadius: BorderRadius.circular(R.pill)),
          child: Icon(icon, size: 20, color: on ? C.accent : C.dim),
        ),
      );
      return DecoratedBox(
        decoration: BoxDecoration(
          color: C.raised1,
          border: Border(right: BorderSide(color: C.border)),
        ),
        child: SafeArea(
          right: false,
          child: SizedBox(
            width: 72,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                if (nav.canBack || nav.lyrics) pill(LucideIcons.chevronLeft, 'Back', nav.back),
                for (final (page, icon, label) in items)
                  KeyedSubtree(
                    key: ValueKey('nav.$page'),
                    child: pill(icon, label, () => nav.go(page), on: current == page),
                  ),
                pill(LucideIcons.search, 'Search', () => nav.setSearch(true)),
                pill(LucideIcons.settings, 'Settings', () => nav.go('settings'), on: nav.top.page == 'settings'),
              ],
            ),
          ),
        ),
      );
    }
    return DecoratedBox(
      decoration: BoxDecoration(
        color: C.raised1,
        border: Border(top: BorderSide(color: C.border)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 64,
          child: Row(
            children: [
              for (final (page, icon, label) in items)
                Expanded(
                  child: Clickable(
                    key: ValueKey('nav.$page'),
                    onTap: () => nav.go(page),
                    semanticLabel: label,
                    selected: current == page,
                    selectedColor: Colors.transparent,
                    radius: R.small,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        AnimatedContainer(
                          duration: Motion.fast,
                          padding: const EdgeInsets.symmetric(horizontal: S.x4, vertical: S.x1),
                          decoration: BoxDecoration(
                            color: current == page ? C.accentSoft : Colors.transparent,
                            borderRadius: BorderRadius.circular(R.pill),
                          ),
                          child: Icon(icon, size: 20, color: current == page ? C.accent : C.dim),
                        ),
                        const SizedBox(height: S.x1),
                        Text(
                          label,
                          maxLines: 1,
                          style: T.caption.copyWith(color: current == page ? C.text : C.dim, fontWeight: FontWeight.w500),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The Library tab: your playlists, favourites and folders, then the Browse pages, as 56 dp rows.
class LibraryPage extends StatelessWidget {
  const LibraryPage({super.key});
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: lib,
    builder: (context, _) {
      Widget row(String page, IconData icon, String label, [String? meta]) => Clickable(
        key: ValueKey('library.$page'),
        onTap: () => nav.push(page, ''),
        semanticLabel: label,
        radius: R.small,
        padding: const EdgeInsets.symmetric(horizontal: S.x2),
        child: SizedBox(
          height: 56,
          child: Row(
            children: [
              Icon(icon, size: 20, color: C.dim),
              const SizedBox(width: S.x4),
              Expanded(child: Text(label, style: T.label)),
              if (meta != null) Text(meta, style: T.small),
              const SizedBox(width: S.x2),
              Icon(LucideIcons.chevronRight, size: 16, color: C.faint),
            ],
          ),
        ),
      );
      return ListView(
        key: const PageStorageKey('library'),
        padding: EdgeInsets.zero,
        children: [
          const PageHeader('Library'),
          row('playlists', LucideIcons.listMusic, 'Playlists', plural(lib.playlists.length, 'playlist')),
          row('favourites', LucideIcons.heart, 'Favourites', plural(lib.favouriteTracks.length, 'song')),
          row('folders', LucideIcons.folder, 'Folders', plural(lib.folders.length, 'folder')),
          const SectionTitle('Browse'),
          row('genres', LucideIcons.tags, 'Genres', fmtInt(lib.genres.length)),
          row('years', LucideIcons.calendar, 'Years', fmtInt(lib.years.length)),
          row('composers', LucideIcons.feather, 'Composers', fmtInt(lib.composers.length)),
          row('duplicates', LucideIcons.copy, 'Duplicates'),
          row('stats', LucideIcons.chartColumn, 'Statistics'),
          const SizedBox(height: S.x16),
        ],
      );
    },
  );
}

/// The look of every phone bottom sheet: raised, rounded, a handle on top, the page dimmed behind.
/// It is as tall as its content, up to the whole screen (a long menu, Change cover).
Future<V?> showPhoneSheet<V>(BuildContext context, WidgetBuilder builder) => showModalBottomSheet<V>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  backgroundColor: C.raised2,
  barrierColor: Colors.black.withValues(alpha: 0.6),
  shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(R.panel))),
  builder: (context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Padding(
        padding: const EdgeInsets.only(top: S.x2),
        child: Container(
          width: 32,
          height: 4,
          decoration: BoxDecoration(color: C.borderStrong, borderRadius: BorderRadius.circular(R.pill)),
        ),
      ),
      Flexible(child: builder(context)),
    ],
  ),
);

/// The top of a song's or album's sheet: its cover, name and a second line.
Widget sheetHeader(Widget cover, String title, String subtitle) => Padding(
  padding: const EdgeInsets.fromLTRB(S.x6, S.x2, S.x6, S.x3),
  child: Row(
    children: [
      cover,
      const SizedBox(width: S.x3),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: T.label),
            if (subtitle.isNotEmpty) Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: T.small),
          ],
        ),
      ),
    ],
  ),
);

/// A touch menu from the bottom of the screen (menus, the sleep timer): the chosen value, null when dismissed.
/// A null item is a divider. It scrolls when the phone is on its side.
Future<V?> phoneSheet<V>(BuildContext context, List<(V, IconData, String)?> items, {String? title, Widget? header}) => showPhoneSheet<V>(
  context,
  (context) => SafeArea(
    top: false,
    child: ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.symmetric(vertical: S.x2),
      children: [
        ?header,
        if (header != null) Divider(height: 1, color: C.border),
        if (title != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(S.x6, S.x2, S.x6, S.x2),
            child: Text(title, style: T.small),
          ),
        for (final item in items)
          if (item == null)
            Divider(height: S.x2 + 1, color: C.border)
          else
            Clickable(
              onTap: () => Navigator.pop(context, item.$1),
              semanticLabel: item.$3,
              radius: 0,
              child: SizedBox(
                height: 56,
                child: Row(
                  children: [
                    const SizedBox(width: S.x6),
                    Icon(item.$2, size: 20, color: C.text),
                    const SizedBox(width: S.x4),
                    Expanded(
                      child: Text(item.$3, style: T.body, maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
                    const SizedBox(width: S.x4),
                  ],
                ),
              ),
            ),
      ],
    ),
  ),
);

/// The phone's mini player: the song, play/pause and next, with a thin progress line.
/// Tap it, or swipe it up, for Now Playing.
class PhoneBar extends StatelessWidget {
  const PhoneBar({super.key});
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([engine, lib]),
    builder: (context, _) {
      final t = engine.current;
      if (t == null) return const SizedBox.shrink();
      return GestureDetector(
        key: const ValueKey('phoneBar'),
        behavior: HitTestBehavior.opaque,
        onTap: () => nav.setNowPlaying(true),
        onVerticalDragEnd: (d) {
          if ((d.primaryVelocity ?? 0) < -150) nav.setNowPlaying(true);
        },
        child: Container(
          margin: const EdgeInsets.fromLTRB(S.x2, 0, S.x2, S.x2),
          decoration: BoxDecoration(
            color: C.raised2,
            borderRadius: BorderRadius.circular(R.card),
            border: Border.all(color: C.border),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(S.x2, S.x2, S.x1, S.x2),
                child: Row(
                  children: [
                    CoverArt.track(t, size: 44),
                    const SizedBox(width: S.x3),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: T.label),
                          Text(t.artist, maxLines: 1, overflow: TextOverflow.ellipsis, style: T.small),
                        ],
                      ),
                    ),
                    IconBtn(
                      engine.playing ? LucideIcons.pause : LucideIcons.play,
                      size: 22,
                      color: C.text,
                      tooltip: engine.playing ? 'Pause' : 'Play',
                      onTap: engine.togglePlay,
                    ),
                    IconBtn(LucideIcons.skipForward, size: 20, color: C.text, tooltip: 'Next', onTap: engine.next),
                  ],
                ),
              ),
              ValueListenableBuilder(
                valueListenable: engine.position,
                builder: (_, pos, _) {
                  final total = engine.duration.inMilliseconds;
                  return LinearProgressIndicator(
                    value: total <= 0 ? 0 : (pos.inMilliseconds / total).clamp(0.0, 1.0),
                    minHeight: 2,
                    color: C.accent,
                    backgroundColor: Colors.transparent,
                  );
                },
              ),
            ],
          ),
        ),
      );
    },
  );
}

/// Before Gleo may read the music: what it needs and why, and the button that asks Android.
class MusicAccess extends StatelessWidget {
  const MusicAccess({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: C.bg,
    body: SafeArea(
      child: EmptyState(
        icon: LucideIcons.music,
        title: 'Your music, on this phone',
        body: 'Gleo plays the songs saved on this phone. Allow it to read your music files: it only reads them, and never changes them.',
        action: PillButton(
          'Allow access',
          key: const ValueKey('allowMusic'),
          icon: LucideIcons.check,
          primary: true,
          onTap: () => askMusicAccess(lib),
        ),
      ),
    ),
  );
}
