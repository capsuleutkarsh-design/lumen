import 'dart:math';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../library/models.dart';
import '../app.dart';
import '../theme.dart';
import '../tracks.dart';
import '../widgets.dart';

class AlbumCard extends StatelessWidget {
  const AlbumCard(this.album, {super.key, this.why, this.width});
  final Album album;
  final String? why;
  final double? width;
  @override
  Widget build(BuildContext context) {
    final card = Clickable(
      onTap: () => nav.push('album', album.key),
      onSecondaryTapDown: (d) => showTrackMenu(context, d.globalPosition, album.tracks),
      radius: R.card,
      hover: C.raised2,
      padding: const EdgeInsets.all(S.x2),
      child: SizedBox(
        width: width,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            CoverArt(album.cover, radius: R.card - S.x2),
            const SizedBox(height: S.x3),
            // Fixed height so grids can size cards exactly (card = width + 78).
            SizedBox(
              height: 66,
              child: ClipRect(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: S.x1),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(album.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: T.label),
                      const SizedBox(height: 2),
                      Text(why ?? album.artist, maxLines: 1, overflow: TextOverflow.ellipsis, style: T.small),
                      const SizedBox(height: S.x2),
                      FormatBadge(album.badge),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
    return why == null ? card : Tooltip(message: 'Why: $why', child: card);
  }
}

/// A horizontal row of albums with arrow buttons (Wora's carousel).
class AlbumShelf extends StatefulWidget {
  const AlbumShelf(this.albums, {super.key, this.whys});
  final List<Album> albums;
  final List<String>? whys;
  @override
  State<AlbumShelf> createState() => _AlbumShelfState();
}

class _AlbumShelfState extends State<AlbumShelf> {
  final _c = ScrollController();
  static const _w = 196.0, _card = _w - S.x4;
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _by(double dx) =>
      _c.animateTo((_c.offset + dx).clamp(0, _c.position.maxScrollExtent), duration: Motion.normal * 2, curve: Motion.curve);

  @override
  Widget build(BuildContext context) => SizedBox(
    height: _card + 82,
    child: Stack(
      children: [
        ListView.separated(
          controller: _c,
          scrollDirection: Axis.horizontal,
          itemCount: widget.albums.length,
          separatorBuilder: (_, _) => const SizedBox(width: S.x2),
          itemBuilder: (_, i) => AlbumCard(widget.albums[i], width: _card - S.x4, why: widget.whys?[i]),
        ),
        if (widget.albums.length > 4) ...[
          Positioned(left: 0, top: _card / 2 - 18, child: _arrow(LucideIcons.chevronLeft, () => _by(-_w * 3))),
          Positioned(right: 0, top: _card / 2 - 18, child: _arrow(LucideIcons.chevronRight, () => _by(_w * 3))),
        ],
      ],
    ),
  );

  Widget _arrow(IconData i, VoidCallback onTap) => DecoratedBox(
    decoration: BoxDecoration(
      color: C.raised2.withValues(alpha: 0.9),
      shape: BoxShape.circle,
      border: Border.all(color: C.borderStrong),
    ),
    child: IconBtn(i, onTap: onTap, color: C.text),
  );
}

class AlbumsPage extends StatefulWidget {
  const AlbumsPage({super.key});
  @override
  State<AlbumsPage> createState() => _AlbumsPageState();
}

class _AlbumsPageState extends State<AlbumsPage> {
  String _sort = 'Title';
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
        slivers: [
          SliverToBoxAdapter(
            child: PageHeader(
              'Albums',
              subtitle: plural(albums.length, 'album'),
              trailing: SortMenu(
                value: _sort,
                options: const ['Title', 'Artist', 'Year', 'Recently added'],
                onChanged: (v) => setState(() => _sort = v),
              ),
            ),
          ),
          if (albums.isEmpty)
            const SliverFillRemaining(hasScrollBody: false, child: NoMusic())
          else
            sliverCards(count: albums.length, builder: (_, i) => AlbumCard(albums[i])),
          const SliverToBoxAdapter(child: SizedBox(height: S.x6)),
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
        final box = context.findRenderObject() as RenderBox;
        final at = box.localToGlobal(Offset(0, box.size.height + 4));
        final v = await showMenu<String>(
          context: context,
          position: RelativeRect.fromLTRB(at.dx, at.dy, at.dx, at.dy),
          items: [
            for (final o in options)
              PopupMenuItem(
                value: o,
                height: 36,
                child: Row(
                  children: [
                    SizedBox(width: 24, child: o == value ? const Icon(LucideIcons.check, size: 14, color: C.accent) : null),
                    Text(o, style: T.label),
                  ],
                ),
              ),
          ],
        );
        if (v != null) onChanged(v);
      },
    ),
  );
}

/// Shown when there is no music yet.
class NoMusic extends StatelessWidget {
  const NoMusic({super.key});
  @override
  Widget build(BuildContext context) => EmptyState(
    icon: LucideIcons.folderOpen,
    title: lib.folders.isEmpty ? 'Add your music folder' : 'No music found yet',
    body: lib.folders.isEmpty
        ? 'Choose the folder where your music lives. Nothing is copied or changed; the player only reads it.'
        : 'Your folders are being read, or they have no audio files. Check them in Settings.',
    action: PillButton(
      lib.folders.isEmpty ? 'Choose folder' : 'Open Settings',
      primary: true,
      icon: LucideIcons.folderPlus,
      onTap: () => nav.go('settings'),
    ),
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
      return CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: PageHero(
              cover: a.cover,
              title: a.title,
              meta: [a.artist, if (a.year != null) '${a.year}', plural(a.tracks.length, 'song'), fmtLong(a.duration)],
              badge: a.badge,
              onArtist: () => nav.push('artist', a.artist),
              tracks: a.tracks,
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: S.x4)),
          if (!discs)
            SliverTracks(a.tracks, numbered: true, showAlbum: false)
          else
            for (final d in {for (final t in a.tracks) t.discNo ?? 1}) ...[
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(S.x3, S.x4, S.x3, S.x2),
                  child: Row(
                    children: [
                      const Icon(LucideIcons.disc, size: 14, color: C.faint),
                      const SizedBox(width: S.x2),
                      Text('Disc $d', style: T.caption.copyWith(fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              ),
              _DiscTracks(a.tracks, d),
            ],
          const SliverToBoxAdapter(child: SizedBox(height: S.x6)),
        ],
      );
    },
  );
}

/// One disc's songs; double-click still plays the whole album from that song.
class _DiscTracks extends StatelessWidget {
  const _DiscTracks(this.all, this.disc);
  final List<Track> all;
  final int disc;
  @override
  Widget build(BuildContext context) {
    final idx = [
      for (var i = 0; i < all.length; i++)
        if ((all[i].discNo ?? 1) == disc) i,
    ];
    return SliverFixedExtentList(
      itemExtent: TrackRow.height,
      delegate: SliverChildBuilderDelegate(
        (_, k) => TrackRow(track: all[idx[k]], list: all, index: idx[k], number: all[idx[k]].trackNo, showCover: false, showAlbum: false),
        childCount: idx.length,
      ),
    );
  }
}

/// Blurred-cover header with Play (the one primary button) and Shuffle.
class PageHero extends StatelessWidget {
  const PageHero({
    super.key,
    required this.cover,
    required this.title,
    required this.meta,
    required this.tracks,
    this.badge,
    this.onArtist,
    this.actions = const [],
    this.round = false,
    this.label = 'Album',
  });
  final String? cover;
  final String title, label;
  final List<String> meta;
  final List<Track> tracks;
  final String? badge;
  final VoidCallback? onArtist;
  final List<Widget> actions;
  final bool round;
  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(R.panel),
    child: Container(
      decoration: BoxDecoration(
        color: C.raised1,
        borderRadius: BorderRadius.circular(R.panel),
        border: Border.all(color: C.border),
      ),
      child: Stack(
        children: [
          CoverGlow(cover, opacity: 0.6),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.black.withValues(alpha: 0.05), Colors.black.withValues(alpha: 0.65)],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(S.x5),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (nav.canBack) _BackPill() else const SizedBox(height: 36),
                const SizedBox(height: S.x10),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(round ? R.pill : R.card),
                        boxShadow: const [BoxShadow(color: Color(0x88000000), blurRadius: 40, offset: Offset(0, 16))],
                      ),
                      child: CoverArt(cover, size: 200, radius: R.card, round: round),
                    ),
                    const SizedBox(width: S.x6),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            label.toUpperCase(),
                            style: T.caption.copyWith(letterSpacing: 1.2, fontWeight: FontWeight.w600, color: C.dim),
                          ),
                          const SizedBox(height: S.x2),
                          Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: T.display.copyWith(fontSize: 40)),
                          const SizedBox(height: S.x2),
                          Wrap(
                            crossAxisAlignment: WrapCrossAlignment.center,
                            spacing: S.x2,
                            runSpacing: S.x1,
                            children: [
                              for (var i = 0; i < meta.length; i++) ...[
                                if (i > 0) const Text('·', style: T.small),
                                i == 0 && onArtist != null
                                    ? Clickable(
                                        onTap: onArtist,
                                        radius: 4,
                                        hover: Colors.transparent,
                                        child: Text(meta[i], style: T.label),
                                      )
                                    : Text(meta[i], style: T.small.copyWith(color: C.text.withValues(alpha: 0.75))),
                              ],
                              if (badge != null) FormatBadge(badge!),
                            ],
                          ),
                          const SizedBox(height: S.x5),
                          Row(
                            children: [
                              PillButton(
                                'Play',
                                icon: LucideIcons.play,
                                primary: true,
                                onTap: tracks.isEmpty ? null : () => engine.playTracks(tracks),
                              ),
                              const SizedBox(width: S.x3),
                              PillButton(
                                'Shuffle',
                                icon: LucideIcons.shuffle,
                                onTap: tracks.isEmpty
                                    ? null
                                    : () async {
                                        await engine.setShuffle(true);
                                        await engine.playTracks(tracks, Random().nextInt(tracks.length));
                                      },
                              ),
                              for (final a in actions) ...[const SizedBox(width: S.x3), a],
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class _BackPill extends StatelessWidget {
  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: Colors.black.withValues(alpha: 0.35),
      borderRadius: BorderRadius.circular(R.small + 4),
      border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
    ),
    child: Clickable(
      onTap: nav.back,
      tooltip: 'Back  (Esc)',
      radius: R.small + 4,
      hover: Colors.white.withValues(alpha: 0.08),
      padding: const EdgeInsets.symmetric(horizontal: S.x3, vertical: S.x2),
      child: const Row(
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
