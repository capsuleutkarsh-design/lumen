import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../library/library.dart';
import '../app.dart';
import '../theme.dart';
import '../tracks.dart';
import '../widgets.dart';
import 'albums.dart';

int _songs(Artist a) => a.albums.fold(0, (n, x) => n + x.tracks.length) + a.appearsOn.length;

class ArtistsPage extends StatelessWidget {
  const ArtistsPage({super.key});
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: lib,
    builder: (context, _) => CustomScrollView(
      slivers: [
        SliverToBoxAdapter(child: PageHeader('Artists', subtitle: plural(lib.artists.length, 'artist'))),
        if (lib.artists.isEmpty)
          const SliverFillRemaining(hasScrollBody: false, child: NoMusic())
        else
          sliverCards(
            maxWidth: 200,
            extra: 52,
            count: lib.artists.length,
            builder: (_, i) {
              final a = lib.artists[i];
              return Clickable(
                onTap: () => nav.push('artist', a.name),
                radius: R.card,
                padding: const EdgeInsets.all(S.x3),
                child: Column(
                  children: [
                    CoverArt(a.cover, round: true),
                    const SizedBox(height: S.x3),
                    Text(a.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: T.label, textAlign: TextAlign.center),
                    const SizedBox(height: 2),
                    Text('${plural(a.albums.length, 'album')} · ${plural(_songs(a), 'song')}', maxLines: 1, style: T.small),
                  ],
                ),
              );
            },
          ),
        const SliverToBoxAdapter(child: SizedBox(height: S.x6)),
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
      final a = lib.artists.where((x) => x.name.toLowerCase() == name.toLowerCase()).firstOrNull;
      if (a == null) {
        return EmptyState(
          icon: LucideIcons.micVocal,
          title: 'Artist not found',
          body: 'They may have been removed from your library.',
          action: PillButton('Back', onTap: nav.back),
        );
      }
      final all = [for (final al in a.albums) ...al.tracks, ...a.appearsOn];
      return CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: PageHero(
              cover: a.cover,
              title: a.name,
              label: 'Artist',
              round: true,
              meta: [plural(a.albums.length, 'album'), plural(all.length, 'song')],
              tracks: all,
            ),
          ),
          if (a.albums.isNotEmpty) ...[
            const SliverToBoxAdapter(child: SectionTitle('Albums')),
            sliverCards(count: a.albums.length, builder: (_, i) => AlbumCard(a.albums[i])),
          ],
          if (a.appearsOn.isNotEmpty) ...[
            SliverToBoxAdapter(child: SectionTitle('Appears on', subtitle: 'Songs by ${a.name} on other albums')),
            SliverTracks(a.appearsOn),
          ],
          const SliverToBoxAdapter(child: SizedBox(height: S.x6)),
        ],
      );
    },
  );
}
