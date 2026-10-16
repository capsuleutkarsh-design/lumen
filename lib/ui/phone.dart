import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../platform/android.dart';
import '../platform/window.dart' show isTouch;
import 'app.dart';
import 'lyrics_view.dart';
import 'now_playing.dart';
import 'pages/browse.dart' show browseTab;
import 'queue_panel.dart';
import 'search.dart';
import 'theme.dart';
import 'widgets.dart';

/// A phone (a touch screen under 600 dp on its short side, in either orientation) gets the phone layout;
/// tablets and every desktop window keep the desktop one.
bool phoneLayout(BuildContext context) => isTouch && MediaQuery.sizeOf(context).shortestSide < 600;

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
            if (nav.search) Positioned.fill(child: _Sheet(child: const SearchConsole())),
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

/// Back (on inner pages), the logo, the scan progress and Search.
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
          const AppMark(size: 24),
          const SizedBox(width: S.x2),
          Text('Lumen', style: T.label),
        ],
        const Spacer(),
        const ScanPill(),
        IconBtn(LucideIcons.search, size: 20, color: C.text, tooltip: 'Search', onTap: () => nav.setSearch(true)),
        const SizedBox(width: S.x1),
      ],
    ),
  );
}

class _BottomNav extends StatelessWidget {
  const _BottomNav({this.side = false});

  /// Landscape: a column of icons on the left (with Back and Search), no labels.
  final bool side;

  static const items = [
    ('home', LucideIcons.house, 'Home'),
    ('albums', LucideIcons.disc3, 'Albums'),
    ('artists', LucideIcons.micVocal, 'Artists'),
    ('songs', LucideIcons.music, 'Songs'),
    ('browse', LucideIcons.compass, 'Browse'),
    ('more', LucideIcons.ellipsis, 'More'),
  ];

  static const more = [
    ('playlists', LucideIcons.listMusic, 'Playlists'),
    ('folders', LucideIcons.folder, 'Folders'),
    ('favourites', LucideIcons.heart, 'Favourites'),
    ('sound', LucideIcons.slidersVertical, 'Sound'),
    ('settings', LucideIcons.settings, 'Settings'),
  ];

  static String _section(String page) => switch (page) {
    'album' => 'albums',
    'artist' => 'artists',
    'genres' || 'genre' || 'years' || 'composers' || 'composer' || 'duplicates' || 'stats' => 'browse',
    'home' || 'albums' || 'artists' || 'songs' => page,
    _ => 'more',
  };

  Future<void> _more(BuildContext context) async {
    final page = await phoneSheet(context, more);
    if (page != null) nav.go(page);
  }

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
                    child: pill(
                      icon,
                      label,
                      () => page == 'more' ? _more(context) : nav.go(page == 'browse' ? browseTab : page),
                      on: current == page,
                    ),
                  ),
                pill(LucideIcons.search, 'Search', () => nav.setSearch(true)),
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
                    onTap: () => page == 'more' ? _more(context) : nav.go(page == 'browse' ? browseTab : page),
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

/// A touch menu from the bottom of the screen (More, the sleep timer): the chosen value, null when dismissed.
/// It scrolls when the phone is on its side.
Future<V?> phoneSheet<V>(BuildContext context, List<(V, IconData, String)> items, {String? title}) => showModalBottomSheet<V>(
  context: context,
  backgroundColor: C.raised1,
  shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(R.panel))),
  builder: (context) => SafeArea(
    child: ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.symmetric(vertical: S.x3),
      children: [
        if (title != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(S.x6, S.x2, S.x6, S.x2),
            child: Text(title, style: T.small),
          ),
        for (final (value, icon, label) in items)
          Clickable(
            onTap: () => Navigator.pop(context, value),
            semanticLabel: label,
            radius: 0,
            child: SizedBox(
              height: 56,
              child: Row(
                children: [
                  const SizedBox(width: S.x6),
                  Icon(icon, size: 20, color: C.text),
                  const SizedBox(width: S.x4),
                  Text(label, style: T.body),
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

/// Before Lumen may read the music: what it needs and why, and the button that asks Android.
class MusicAccess extends StatelessWidget {
  const MusicAccess({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: C.bg,
    body: SafeArea(
      child: EmptyState(
        icon: LucideIcons.music,
        title: 'Your music, on this phone',
        body: 'Lumen plays the songs saved on this phone. Allow it to read your music files: it only reads them, and never changes them.',
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
