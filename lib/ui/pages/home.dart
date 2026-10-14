import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../library/models.dart';
import '../../library/suggestions.dart';
import '../app.dart';
import '../theme.dart';
import '../tracks.dart';
import '../widgets.dart';
import 'albums.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  static String _greeting() {
    final h = DateTime.now().hour;
    return h < 5
        ? 'Late night listening'
        : h < 12
        ? 'Good morning'
        : h < 18
        ? 'Good afternoon'
        : 'Good evening';
  }

  List<Widget> _tracks(String title, String subtitle, List<Pick<Track>> picks, {int max = 5}) {
    if (picks.isEmpty) return [];
    final shown = picks.take(max).toList();
    return [
      SliverToBoxAdapter(child: SectionTitle(title, subtitle: subtitle)),
      SliverTracks([for (final p in shown) p.item], whys: [for (final p in shown) p.why]),
    ];
  }

  List<Widget> _albums(String title, String subtitle, List<Pick<Album>> picks) {
    if (picks.isEmpty) return [];
    return [
      SliverToBoxAdapter(child: SectionTitle(title, subtitle: subtitle)),
      SliverToBoxAdapter(child: AlbumShelf([for (final p in picks) p.item], whys: [for (final p in picks) p.why])),
    ];
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: lib,
    builder: (context, _) {
      final h = lib.home;
      final played = h.mostPlayed.isNotEmpty;
      return CustomScrollView(
        key: const PageStorageKey('home'),
        slivers: [
          SliverToBoxAdapter(
            child: PageHeader(
              _greeting(),
              subtitle: lib.tracks.isEmpty
                  ? 'Your music, played the way it was recorded.'
                  : '${plural(lib.tracks.length, 'song')} · ${plural(lib.albums.length, 'album')} · ${plural(lib.artists.length, 'artist')}',
            ),
          ),
          if (lib.tracks.isEmpty)
            const SliverFillRemaining(hasScrollBody: false, child: NoMusic())
          else ...[
            if (!played)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: S.x2),
                  child: Panel(
                    padding: const EdgeInsets.all(S.x5),
                    child: Row(
                      children: [
                        Icon(LucideIcons.sparkles, size: 20, color: C.dim),
                        const SizedBox(width: S.x4),
                        Expanded(
                          child: Text(
                            'Play a few songs and suggestions will appear here. They come only from what you play on this computer: '
                            'plays count after half a song (or 4 minutes), skips are songs left in the first 30 seconds.',
                            style: T.small,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ..._albums('Jump back in', 'Albums you played recently', h.jumpBackIn),
            if (h.seed != null)
              ..._tracks(
                'Because you played “${h.seed!.title}”',
                'Same artist first, then album artist, then same genre and decade',
                h.because,
              ),
            ..._tracks('Most played', 'Your most-played songs', h.mostPlayed),
            ..._tracks('Not played in a while', 'Songs you played often, but not in the last 30 days', h.notLately),
            ..._albums('Recently added', 'Newest in your library', h.recentlyAdded),
          ],
          const SliverToBoxAdapter(child: SizedBox(height: S.x16)),
        ],
      );
    },
  );
}
