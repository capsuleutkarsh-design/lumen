import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../app.dart';
import '../theme.dart';
import '../tracks.dart';
import '../widgets.dart';

class FavouritesPage extends StatelessWidget {
  const FavouritesPage({super.key});
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: lib,
    builder: (context, _) {
      final tracks = lib.favouriteTracks;
      return CustomScrollView(
        key: const PageStorageKey('favourites'),
        slivers: [
          SliverToBoxAdapter(
            child: PageHeader(
              'Favourites',
              subtitle: plural(tracks.length, 'song'),
              trailing: tracks.isEmpty
                  ? null
                  : PillButton('Play all', icon: LucideIcons.play, primary: true, onTap: () => engine.playTracks(tracks)),
            ),
          ),
          if (tracks.isEmpty)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: EmptyState(
                icon: LucideIcons.heart,
                title: 'No favourites yet',
                body: 'Tap the heart on any song, or in the player bar, to keep it here.',
              ),
            )
          else
            SliverTracks(tracks, primary: true),
          const SliverToBoxAdapter(child: SizedBox(height: S.x16)),
        ],
      );
    },
  );
}
