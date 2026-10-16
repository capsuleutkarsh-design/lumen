import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../art/art_cache.dart';
import '../../library/models.dart';
import '../../platform/window.dart' show isTouch;
import '../app.dart';
import '../cover_picker.dart';
import '../theme.dart';
import '../tracks.dart';
import '../widgets.dart';
import 'settings.dart';

/// A quiet framed card: big cover, title, artist, one caption line. Hovering
/// shows a play button; right-click opens the album menu.
class AlbumCard extends StatefulWidget {
  const AlbumCard(this.album, {super.key, this.why, this.width});
  final Album album;
  final String? why;
  final double? width;

  /// Height of everything below the square cover, at the user's text size.
  static double extra(BuildContext context) => S.x3 + S.x1 + 2 + textHeight(context, [T.label, T.small, T.caption]);
  // (the card's padding and the cover add up to its width)

  @override
  State<AlbumCard> createState() => _AlbumCardState();
}

class _AlbumCardState extends State<AlbumCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final a = widget.album;
    final caption = widget.why ?? [if (a.year != null) '${a.year}', a.badge].join(' · ');
    final card = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(R.card),
        border: Border.all(color: C.border),
      ),
      child: Clickable(
        onTap: () => nav.push('album', a.key),
        onSecondaryTapDown: (d) => albumMenu(context, d.globalPosition, a),
        onHover: (v) => setState(() => _hover = v),
        semanticLabel: 'Album ${a.title} by ${a.artist}',
        radius: R.card,
        hover: C.raised2,
        padding: const EdgeInsets.all(S.x2),
        child: SizedBox(
          width: widget.width,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                children: [
                  CoverArt.album(a, radius: R.card - S.x2),
                  Positioned(
                    right: S.x2,
                    bottom: S.x2,
                    child: AnimatedOpacity(
                      opacity: _hover ? 1 : 0,
                      duration: Motion.fast,
                      child: AnimatedSlide(
                        offset: _hover ? Offset.zero : const Offset(0, 0.15),
                        duration: Motion.normal,
                        curve: Motion.curve,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: C.text,
                            shape: BoxShape.circle,
                            boxShadow: [BoxShadow(color: C.shadow, blurRadius: 16, offset: Offset(0, 6))],
                          ),
                          child: Clickable(
                            onTap: () => engine.playTracks(a.tracks),
                            tooltip: 'Play',
                            semanticLabel: 'Play ${a.title}',
                            radius: R.pill,
                            hover: C.veil(0.13),
                            child: SizedBox(width: 40, height: 40, child: Icon(LucideIcons.play, size: 18, color: C.onLight)),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: S.x3),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: S.x1),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(a.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: T.label),
                    Text(a.artist, maxLines: 1, overflow: TextOverflow.ellipsis, style: T.small),
                    const SizedBox(height: S.x1),
                    Text(caption, maxLines: 1, overflow: TextOverflow.ellipsis, style: T.caption),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
    return widget.why == null ? card : Tooltip(message: 'Why: ${widget.why}', waitDuration: const Duration(seconds: 1), child: card);
  }
}

/// Play, Shuffle, Play next, Add to queue, Add to playlist, Go to artist.
Future<void> albumMenu(BuildContext context, Offset at, Album a) => showCollectionMenu(
  context,
  at,
  a.tracks,
  extra: [
    ('artist', LucideIcons.micVocal, 'Go to artist', () => nav.push('artist', a.artist)),
    ('cover', LucideIcons.image, 'Change cover…', () => showCoverPicker(context, a)),
  ],
);

/// A horizontal row of albums with arrow buttons (Wora's carousel). The arrows
/// show only when there is more to scroll to.
class AlbumShelf extends StatefulWidget {
  const AlbumShelf(this.albums, {super.key, this.whys});
  final List<Album> albums;
  final List<String>? whys;
  @override
  State<AlbumShelf> createState() => _AlbumShelfState();
}

class _AlbumShelfState extends State<AlbumShelf> {
  final _c = ScrollController();
  bool _left = false, _right = false;
  static const _card = 212.0;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  bool _update(ScrollMetrics m) {
    final l = m.pixels > 1, r = m.pixels < m.maxScrollExtent - 1;
    if (l != _left || r != _right) {
      setState(() {
        _left = l;
        _right = r;
      });
    }
    return false;
  }

  void _by(double dx) => _c.animateTo((_c.offset + dx).clamp(0, _c.position.maxScrollExtent), duration: Motion.slow, curve: Motion.curve);

  @override
  Widget build(BuildContext context) => SizedBox(
    height: _card + AlbumCard.extra(context),
    child: Stack(
      children: [
        NotificationListener<ScrollMetricsNotification>(
          onNotification: (n) => _update(n.metrics),
          child: NotificationListener<ScrollNotification>(
            onNotification: (n) => _update(n.metrics),
            child: ListView.separated(
              controller: _c,
              scrollDirection: Axis.horizontal,
              itemCount: widget.albums.length,
              separatorBuilder: (_, _) => const SizedBox(width: S.x4),
              itemBuilder: (_, i) => AlbumCard(widget.albums[i], width: _card - S.x2 * 2, why: widget.whys?[i]),
            ),
          ),
        ),
        if (_left) Positioned(left: S.x2, top: _card / 2 - 18, child: _arrow(LucideIcons.chevronLeft, 'Back', () => _by(-_card * 3))),
        if (_right) Positioned(right: S.x2, top: _card / 2 - 18, child: _arrow(LucideIcons.chevronRight, 'More', () => _by(_card * 3))),
      ],
    ),
  );

  Widget _arrow(IconData i, String tip, VoidCallback onTap) => DecoratedBox(
    decoration: BoxDecoration(
      color: C.raised2.withValues(alpha: 0.92),
      shape: BoxShape.circle,
      border: Border.all(color: C.borderStrong),
      boxShadow: [BoxShadow(color: C.shadow, blurRadius: 16)],
    ),
    child: IconBtn(i, onTap: onTap, color: C.text, tooltip: tip),
  );
}

class AlbumsPage extends StatefulWidget {
  const AlbumsPage({super.key});
  @override
  State<AlbumsPage> createState() => _AlbumsPageState();
}

class _AlbumsPageState extends State<AlbumsPage> {
  String get _sort => nav.memo['albums.sort'] as String? ?? 'Title';
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: lib,
    builder: (context, _) {
      final albums = List.of(lib.albums);
      switch (_sort) {
        case 'Artist':
          albums.sort((a, b) => a.artist.toLowerCase().compareTo(b.artist.toLowerCase()));
        case 'Year':
          albums.sort((a, b) => (b.year ?? 0).compareTo(a.year ?? 0));
        case 'Recently added':
          albums.sort((a, b) => b.addedAt.compareTo(a.addedAt));
      }
      return CustomScrollView(
        key: const PageStorageKey('albums'),
        slivers: [
          SliverToBoxAdapter(
            child: PageHeader(
              'Albums',
              subtitle: plural(albums.length, 'album'),
              trailing: SortMenu(
                value: _sort,
                options: const ['Title', 'Artist', 'Year', 'Recently added'],
                onChanged: (v) => setState(() => nav.memo['albums.sort'] = v),
              ),
            ),
          ),
          if (albums.isEmpty)
            const SliverFillRemaining(hasScrollBody: false, child: NoMusic())
          else
            sliverCards(count: albums.length, extra: AlbumCard.extra(context), builder: (_, i) => AlbumCard(albums[i])),
          const SliverToBoxAdapter(child: SizedBox(height: S.x16)),
        ],
      );
    },
  );
}

class SortMenu extends StatelessWidget {
  const SortMenu({super.key, required this.value, required this.options, required this.onChanged});
  final String value;
  final List<String> options;
  final ValueChanged<String> onChanged;
  @override
  Widget build(BuildContext context) => Builder(
    builder: (context) => PillButton(
      'Sort: $value',
      icon: LucideIcons.arrowUpDown,
      onTap: () async {
        final v = await popMenu(context, below(context), [
          for (final o in options)
            PopupMenuItem(
              value: o,
              height: 36,
              child: Row(
                children: [
                  SizedBox(width: 24, child: o == value ? Icon(LucideIcons.check, size: 14, color: C.text) : null),
                  Text(o, style: T.label),
                ],
              ),
            ),
        ]);
        if (v != null) onChanged(v);
      },
    ),
  );
}

/// Shown when there is no music yet: pick a folder right here, or watch the
/// first scan's progress instead of an alarming "nothing found".
class NoMusic extends StatelessWidget {
  const NoMusic({super.key});
  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: lib.scan,
    builder: (context, s, _) {
      if (s != null) {
        return EmptyState(
          icon: LucideIcons.audioLines,
          title: 'Reading your music…',
          body: s.$2 == 0
              ? 'Looking through your folders for songs.'
              : 'Songs appear here as they are read. ${fmtInt(s.$1)} of ${fmtInt(s.$2)} files so far.',
          extra: SizedBox(
            width: 280,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(R.pill),
              child: LinearProgressIndicator(
                value: s.$2 == 0 ? null : s.$1 / s.$2,
                minHeight: 4,
                color: C.text,
                backgroundColor: C.raised3,
              ),
            ),
          ),
        );
      }
      final none = lib.folders.isEmpty;
      return EmptyState(
        icon: LucideIcons.folderOpen,
        title: none ? 'Add your music folder' : 'No songs found',
        body: none
            ? 'Choose the folder where your music lives${isTouch ? '' : ', or drop it on this window'}. Nothing is copied or changed; Gleo only reads it.'
            : 'Gleo found no audio files in your folders. Check them in Settings.',
        action: none
            ? const PillButton('Choose folder', primary: true, icon: LucideIcons.folderPlus, onTap: addMusicFolder)
            : PillButton('Open Settings', icon: LucideIcons.settings, onTap: () => nav.go('settings')),
      );
    },
  );
}

class AlbumPage extends StatelessWidget {
  const AlbumPage(this.albumKey, {super.key});
  final String albumKey;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: lib,
    builder: (context, _) {
      final a = lib.albumByKey[albumKey];
      if (a == null) {
        return EmptyState(
          icon: LucideIcons.disc3,
          title: 'Album not found',
          body: 'It may have been removed from your library.',
          action: PillButton('Back', onTap: nav.back),
        );
      }
      final discs = a.discCount > 1;
      final mixed = a.tracks.map((t) => t.badge).toSet().length > 1;
      Widget list(List<Track> tracks, {bool primary = false}) =>
          SliverTracks(tracks, all: a.tracks, numbered: true, showAlbum: false, showBadge: mixed, albumArtist: a.artist, primary: primary);
      return CustomScrollView(
        key: PageStorageKey('album/$albumKey'),
        slivers: [
          SliverToBoxAdapter(
            child: PageHero(
              cover: CoverArt.album(a, radius: R.card),
              glow: lib.artFor(a.key, a.cover),
              title: a.title,
              meta: [a.artist, if (a.year != null) '${a.year}', plural(a.tracks.length, 'song'), fmtLong(a.duration)],
              badge: a.badge,
              onArtist: () => nav.push('artist', a.artist),
              tracks: a.tracks,
              menu: [
                ('artist', LucideIcons.micVocal, 'Go to artist', () => nav.push('artist', a.artist)),
                ('cover', LucideIcons.image, 'Change cover…', () => showCoverPicker(context, a)),
              ],
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: S.x4)),
          if (!discs)
            list(a.tracks, primary: true)
          else
            for (final d in {for (final t in a.tracks) t.discNo ?? 1}) ...[
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(S.x3, S.x4, S.x3, S.x2),
                  child: Row(
                    children: [
                      Icon(LucideIcons.disc, size: 14, color: C.faint),
                      const SizedBox(width: S.x2),
                      Text('Disc $d', style: T.caption.copyWith(fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              ),
              list([
                for (final t in a.tracks)
                  if ((t.discNo ?? 1) == d) t,
              ], primary: d == (a.tracks.first.discNo ?? 1)),
            ],
          const SliverToBoxAdapter(child: SizedBox(height: S.x16)),
        ],
      );
    },
  );
}

/// The header of an album, artist or playlist: the cover over its own blurred
/// colours, Play (the one primary button), Shuffle and a ••• menu. It shrinks
/// and wraps so it never overflows, even in a small window with the queue open.
class PageHero extends StatelessWidget {
  const PageHero({
    super.key,
    required this.cover,
    required this.glow,
    required this.title,
    required this.meta,
    required this.tracks,
    this.badge,
    this.onArtist,
    this.menu = const [],
    this.round = false,
    this.label = 'Album',
  });

  /// The square (or round) cover widget.
  final Widget cover;

  /// The art blurred behind the header.
  final Art? glow;
  final String title, label;
  final List<String> meta;
  final List<Track> tracks;
  final String? badge;
  final VoidCallback? onArtist;

  /// Extra entries for the ••• menu (rename, export, delete…).
  final List<(String, IconData, String, VoidCallback)> menu;
  final bool round;

  void _menu(BuildContext context, Offset at) => showCollectionMenu(context, at, tracks, extra: menu);

  @override
  Widget build(BuildContext context) => GestureDetector(
    onSecondaryTapDown: (d) => _menu(context, d.globalPosition),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(R.panel),
      child: Container(
        decoration: BoxDecoration(
          color: C.raised1,
          borderRadius: BorderRadius.circular(R.panel),
          border: Border.all(color: C.border),
        ),
        child: Stack(
          children: [
            CoverGlow(glow, opacity: 0.8, blur: 80),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [C.veil(0.15), C.veil(0.55), C.veil(0.9)],
                    stops: [0, 0.55, 1],
                  ),
                ),
              ),
            ),
            LayoutBuilder(
              builder: (context, c) {
                final w = c.maxWidth;
                final size = (w * 0.3).clamp(120.0, 232.0);
                final stacked = w < 480;
                final titleStyle = w >= 720 ? T.display : T.title;
                final art = DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(round ? R.pill : R.card),
                    boxShadow: [BoxShadow(color: C.shadow, blurRadius: 48, offset: Offset(0, 20))],
                  ),
                  child: SizedBox(width: size, height: size, child: cover),
                );
                final text = Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      label.toUpperCase(),
                      style: T.caption.copyWith(letterSpacing: 1.2, fontWeight: FontWeight.w600, color: C.dim),
                    ),
                    const SizedBox(height: S.x2),
                    Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: titleStyle),
                    const SizedBox(height: S.x3),
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: S.x2,
                      runSpacing: S.x1,
                      children: [
                        for (var i = 0; i < meta.length; i++) ...[
                          if (i > 0) Text('·', style: T.small),
                          i == 0 && onArtist != null
                              ? Clickable(
                                  onTap: onArtist,
                                  radius: R.tiny,
                                  hover: Colors.transparent,
                                  child: Text(meta[i], style: T.label),
                                )
                              : Text(meta[i], style: T.small.copyWith(color: C.text.withValues(alpha: 0.75))),
                        ],
                        if (badge != null) FormatBadge(badge!),
                      ],
                    ),
                    const SizedBox(height: S.x5),
                    Wrap(
                      spacing: S.x3,
                      runSpacing: S.x2,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        PillButton(
                          'Play',
                          icon: LucideIcons.play,
                          primary: true,
                          onTap: tracks.isEmpty ? null : () => engine.playTracks(tracks),
                        ),
                        PillButton(
                          'Shuffle',
                          icon: LucideIcons.shuffle,
                          glass: true,
                          onTap: tracks.isEmpty ? null : () => shufflePlay(tracks),
                        ),
                        Builder(
                          builder: (b) => DecoratedBox(
                            decoration: BoxDecoration(
                              color: C.glass,
                              shape: BoxShape.circle,
                              border: Border.all(color: C.glassBorder),
                            ),
                            child: IconBtn(LucideIcons.ellipsis, color: C.text, tooltip: 'More', onTap: () => _menu(b, below(b))),
                          ),
                        ),
                      ],
                    ),
                  ],
                );
                return Padding(
                  padding: EdgeInsets.all(w >= 720 ? S.x6 : S.x5),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (nav.canBack) const _BackPill() else const SizedBox(height: S.x8),
                      SizedBox(height: w >= 720 ? S.x16 : S.x8),
                      if (stacked) ...[
                        art,
                        const SizedBox(height: S.x5),
                        text,
                      ] else
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            art,
                            const SizedBox(width: S.x6),
                            Expanded(child: text),
                          ],
                        ),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      ),
    ),
  );
}

class _BackPill extends StatelessWidget {
  const _BackPill();
  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: C.glass,
      borderRadius: BorderRadius.circular(R.card - S.x1),
      border: Border.all(color: C.glassBorder),
    ),
    child: Clickable(
      onTap: nav.back,
      tooltip: 'Back  (Esc)',
      semanticLabel: 'Back',
      radius: R.card - S.x1,
      hover: C.glassBorder,
      padding: const EdgeInsets.symmetric(horizontal: S.x3, vertical: S.x2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(LucideIcons.arrowLeft, size: 16, color: C.text),
          SizedBox(width: S.x2),
          Text('Back', style: T.label),
        ],
      ),
    ),
  );
}
