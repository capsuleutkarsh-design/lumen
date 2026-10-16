import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../library/library.dart';
import '../../library/models.dart';
import '../app.dart';
import '../phone.dart';
import '../theme.dart';
import '../tracks.dart';
import '../widgets.dart';
import 'albums.dart';

/// Every song by [a]: their albums, then the songs they appear on.
List<Track> artistTracks(Artist a) => [for (final al in a.albums) ...al.tracks, ...a.appearsOn];

/// "3 albums · 31 songs", or just "2 songs" for someone with no album of their own.
String artistMeta(Artist a) {
  final songs = plural(a.albums.fold(0, (n, x) => n + x.tracks.length) + a.appearsOn.length, 'song');
  return a.albums.isEmpty ? songs : '${plural(a.albums.length, 'album')} · $songs';
}

class ArtistsPage extends StatelessWidget {
  const ArtistsPage({super.key});

  static double _extra(BuildContext context) => S.x3 * 2 + S.x3 + textHeight(context, [T.label, T.small]) + 2;

  /// The phone: 64 dp rows, sorted by name or by plays.
  Widget _phone(BuildContext context, StateSetter setState) {
    final byPlays = nav.memo['artists.sort'] == 'Most played';
    var artists = lib.artists;
    if (byPlays) {
      final stats = lib.playStats();
      int plays(Artist a) => artistTracks(a).fold(0, (n, t) => n + (stats[t.id]?.plays ?? 0));
      final n = {for (final a in artists) a.name: plays(a)};
      artists = List.of(artists)..sort((a, b) => n[b.name]!.compareTo(n[a.name]!));
    }
    return CustomScrollView(
      key: const PageStorageKey('artists'),
      slivers: [
        SliverToBoxAdapter(
          child: PageHeader(
            'Artists',
            subtitle: plural(artists.length, 'artist'),
            trailing: artists.isEmpty
                ? null
                : SortMenu(
                    value: byPlays ? 'Most played' : 'Name',
                    options: const ['Name', 'Most played'],
                    onChanged: (v) => setState(() => nav.memo['artists.sort'] = v),
                  ),
          ),
        ),
        if (artists.isEmpty)
          const SliverFillRemaining(hasScrollBody: false, child: NoMusic())
        else
          SliverFixedExtentList(
            itemExtent: 64,
            delegate: SliverChildBuilderDelegate((_, i) {
              final a = artists[i];
              return Clickable(
                onTap: () => nav.push('artist', a.name),
                onSecondaryTapDown: (d) => showCollectionMenu(context, d.globalPosition, artistTracks(a), title: a.name),
                semanticLabel: 'Artist ${a.name}',
                radius: R.small,
                padding: const EdgeInsets.symmetric(horizontal: S.x2),
                child: Row(
                  children: [
                    CoverArt(a.cover, size: 48, round: true, seed: a.name),
                    const SizedBox(width: S.x3),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(a.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: T.label),
                          Text(artistMeta(a), maxLines: 1, overflow: TextOverflow.ellipsis, style: T.small),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }, childCount: artists.length),
          ),
        const SliverToBoxAdapter(child: SizedBox(height: S.x16)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: lib,
    builder: (context, _) => phoneLayout(context)
        ? StatefulBuilder(builder: _phone)
        : CustomScrollView(
            key: const PageStorageKey('artists'),
            slivers: [
              SliverToBoxAdapter(child: PageHeader('Artists', subtitle: plural(lib.artists.length, 'artist'))),
              if (lib.artists.isEmpty)
                const SliverFillRemaining(hasScrollBody: false, child: NoMusic())
              else
                sliverCards(
                  maxWidth: 200,
                  extra: _extra(context) - S.x3 * 2,
                  count: lib.artists.length,
                  builder: (_, i) {
                    final a = lib.artists[i];
                    return Clickable(
                      onTap: () => nav.push('artist', a.name),
                      onSecondaryTapDown: (d) => showCollectionMenu(context, d.globalPosition, artistTracks(a)),
                      semanticLabel: 'Artist ${a.name}',
                      radius: R.card,
                      padding: const EdgeInsets.all(S.x3),
                      child: Column(
                        children: [
                          CoverArt(a.cover, round: true, seed: a.name),
                          const SizedBox(height: S.x3),
                          Text(a.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: T.label, textAlign: TextAlign.center),
                          Text(artistMeta(a), maxLines: 1, overflow: TextOverflow.ellipsis, style: T.small),
                        ],
                      ),
                    );
                  },
                ),
              const SliverToBoxAdapter(child: SizedBox(height: S.x16)),
            ],
          ),
  );
}

class ArtistPage extends StatelessWidget {
  const ArtistPage(this.name, {super.key});
  final String name;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: lib,
    builder: (context, _) {
      final a = lib.artistNamed(name);
      if (a == null) {
        return EmptyState(
          icon: LucideIcons.users,
          title: 'Artist not found',
          body: 'They may have been removed from your library.',
          action: PillButton('Back', onTap: nav.back),
        );
      }
      final all = artistTracks(a);
      return CustomScrollView(
        key: PageStorageKey('artist/$name'),
        slivers: [
          SliverToBoxAdapter(
            child: PageHero(
              cover: CoverArt(a.cover, round: true, seed: a.name),
              glow: resolveArt(a.cover, seed: a.name),
              title: a.name,
              label: 'Artist',
              round: true,
              meta: artistMeta(a).split(' · '),
              tracks: all,
            ),
          ),
          if (a.albums.isNotEmpty) ...[
            const SliverToBoxAdapter(child: SectionTitle('Albums')),
            sliverCards(count: a.albums.length, extra: AlbumCard.extra(context), builder: (_, i) => AlbumCard(a.albums[i])),
          ],
          if (a.appearsOn.isNotEmpty) ...[
            SliverToBoxAdapter(child: SectionTitle('Appears on', subtitle: 'Songs by ${a.name} on other albums')),
            SliverTracks(a.appearsOn, primary: true),
          ],
          const SliverToBoxAdapter(child: SizedBox(height: S.x16)),
        ],
      );
    },
  );
}
