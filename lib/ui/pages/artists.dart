import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../library/library.dart';
import '../../library/models.dart';
import '../app.dart';
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

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: lib,
    builder: (context, _) => CustomScrollView(
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
                    CoverArt(a.cover, round: true, seed: a.name, label: a.name),
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
          icon: LucideIcons.micVocal,
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
              cover: CoverArt(a.cover, round: true, seed: a.name, label: a.name),
              glow: (a.cover, a.name),
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
