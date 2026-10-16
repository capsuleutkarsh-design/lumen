import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../library/models.dart';
import '../../library/suggestions.dart';
import '../../platform/window.dart' show isTouch;
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
        ? 'Good night'
        : h < 12
        ? 'Good morning'
        : h < 18
        ? 'Good afternoon'
        : 'Good evening';
  }

  // On a touch screen the sections keep just their names: how suggestions work is for Windows' wider page.
  List<Widget> _tracks(String title, String subtitle, List<Pick<Track>> picks, {int max = 5}) {
    if (picks.isEmpty) return [];
    final shown = picks.take(max).toList();
    return [
      SliverToBoxAdapter(child: SectionTitle(title, subtitle: isTouch ? null : subtitle)),
      SliverTracks([for (final p in shown) p.item], whys: [for (final p in shown) p.why]),
    ];
  }

  List<Widget> _albums(String title, String subtitle, List<Pick<Album>> picks) {
    if (picks.isEmpty) return [];
    return [
      SliverToBoxAdapter(child: SectionTitle(title, subtitle: isTouch ? null : subtitle)),
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
              trailing: isTouch && lib.tracks.isNotEmpty
                  ? PillButton('Shuffle all', icon: LucideIcons.shuffle, primary: true, onTap: () => shufflePlay(lib.tracks))
                  : null,
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
                        Icon(LucideIcons.history, size: 20, color: C.dim),
                        const SizedBox(width: S.x4),
                        Expanded(
                          child: Text(
                            isTouch
                                ? 'Play a few songs and Gleo will suggest more here.'
                                : 'Suggestions appear after you play a few songs. They come only from what you play here.',
                            style: T.small,
                          ),
                        ),
                        // Touch has Shuffle all in the header already.
                        if (!isTouch) ...[
                          const SizedBox(width: S.x4),
                          PillButton('Shuffle all', icon: LucideIcons.shuffle, primary: true, onTap: () => shufflePlay(lib.tracks)),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ..._albums('Jump back in', 'Albums you played recently', h.jumpBackIn),
            if (h.seed != null) ..._tracks('Because you played “${h.seed!.title}”', 'More like this, from your library', h.because),
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
