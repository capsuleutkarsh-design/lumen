import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../library/models.dart';
import '../app.dart';
import '../theme.dart';
import '../tracks.dart';
import '../widgets.dart';
import 'albums.dart';

const _m3u = XTypeGroup(label: 'Playlists', extensions: ['m3u8', 'm3u']);

Future<void> importPlaylist(BuildContext context) async {
  final f = await openFile(acceptedTypeGroups: [_m3u]);
  if (f == null) return;
  (int, int) r;
  try {
    r = lib.importM3u(f.path);
  } catch (e) {
    debugPrint('M3U import of ${f.path}: $e');
    if (context.mounted) toast(context, 'Could not read ${f.name}');
    return;
  }
  final (id, missing) = r;
  if (!context.mounted) return;
  toast(context, missing == 0 ? 'Playlist imported' : 'Imported; $missing songs are not in your library');
  nav.push('playlist', id);
}

class PlaylistsPage extends StatelessWidget {
  const PlaylistsPage({super.key});
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: lib,
    builder: (context, _) => CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: PageHeader(
            'Playlists',
            subtitle: plural(lib.playlists.length, 'playlist'),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                PillButton('Import M3U', icon: LucideIcons.download, onTap: () => importPlaylist(context)),
                const SizedBox(width: S.x3),
                PillButton(
                  'New playlist',
                  icon: LucideIcons.plus,
                  primary: true,
                  onTap: () async {
                    final name = await askText(context, 'New playlist', action: 'Create');
                    if (name != null) nav.push('playlist', lib.createPlaylist(name));
                  },
                ),
              ],
            ),
          ),
        ),
        if (lib.playlists.isEmpty)
          const SliverFillRemaining(
            hasScrollBody: false,
            child: EmptyState(
              icon: LucideIcons.listMusic,
              title: 'No playlists yet',
              body: 'Make one with New playlist, or right-click any song and choose Add to playlist.',
            ),
          )
        else
          sliverCards(
            extra: 52,
            count: lib.playlists.length,
            builder: (_, i) {
              final pl = lib.playlists[i];
              final covers = [for (final id in pl.trackIds) lib.byId[id]?.cover].whereType<String>().toSet().take(4).toList();
              return Clickable(
                onTap: () => nav.push('playlist', pl.id),
                radius: R.card,
                padding: const EdgeInsets.all(S.x2),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _Mosaic(covers),
                    const SizedBox(height: S.x3),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: S.x1),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(pl.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: T.label),
                          const SizedBox(height: 2),
                          Text(plural(pl.trackIds.length, 'song'), style: T.small),
                        ],
                      ),
                    ),
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

/// Up to four covers in a square.
class _Mosaic extends StatelessWidget {
  const _Mosaic(this.covers);
  final List<String> covers;
  @override
  Widget build(BuildContext context) {
    if (covers.length < 4) return CoverArt(covers.firstOrNull, radius: R.card - S.x2);
    return ClipRRect(
      borderRadius: BorderRadius.circular(R.card - S.x2),
      child: AspectRatio(
        aspectRatio: 1,
        child: GridView.count(
          crossAxisCount: 2,
          physics: const NeverScrollableScrollPhysics(),
          children: [for (final c in covers) CoverArt(c, radius: 0)],
        ),
      ),
    );
  }
}

class PlaylistPage extends StatelessWidget {
  const PlaylistPage(this.id, {super.key});
  final int id;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: lib,
    builder: (context, _) {
      final pl = lib.playlists.where((x) => x.id == id).firstOrNull;
      if (pl == null) {
        return EmptyState(
          icon: LucideIcons.listMusic,
          title: 'Playlist not found',
          body: 'It may have been deleted.',
          action: PillButton('Back', onTap: nav.back),
        );
      }
      final tracks = [for (final i in pl.trackIds) lib.byId[i]].whereType<Track>().toList();
      return CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: PageHero(
              cover: tracks.map((t) => t.cover).whereType<String>().firstOrNull,
              title: pl.name,
              label: 'Playlist',
              meta: [
                plural(tracks.length, 'song'),
                fmtLong(Duration(milliseconds: tracks.fold(0, (s, t) => s + t.durationMs))),
              ],
              tracks: tracks,
              actions: [
                IconBtn(
                  LucideIcons.pencil,
                  tooltip: 'Rename',
                  color: C.text,
                  onTap: () async {
                    final name = await askText(context, 'Rename playlist', initial: pl.name);
                    if (name != null) lib.renamePlaylist(pl.id, name);
                  },
                ),
                IconBtn(
                  LucideIcons.upload,
                  tooltip: 'Export as M3U8',
                  color: C.text,
                  onTap: () async {
                    final loc = await getSaveLocation(suggestedName: '${pl.name}.m3u8', acceptedTypeGroups: [_m3u]);
                    if (loc == null) return;
                    lib.exportM3u(pl.id, loc.path);
                    if (context.mounted) toast(context, 'Saved ${loc.path}');
                  },
                ),
                IconBtn(
                  LucideIcons.trash2,
                  tooltip: 'Delete playlist',
                  color: C.text,
                  onTap: () async {
                    if (await confirm(context, 'Delete “${pl.name}”?', 'The songs stay in your library; only the playlist is removed.')) {
                      lib.deletePlaylist(pl.id);
                      nav.back();
                    }
                  },
                ),
              ],
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: S.x4)),
          if (tracks.isEmpty)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: EmptyState(
                icon: LucideIcons.listPlus,
                title: 'This playlist is empty',
                body: 'Right-click any song and choose Add to playlist.',
              ),
            )
          else
            SliverReorderableList(
              itemCount: tracks.length,
              onReorderItem: (from, to) {
                final ids = [for (final t in tracks) t.id];
                ids.insert(to, ids.removeAt(from));
                lib.setPlaylistTracks(pl.id, ids);
              },
              proxyDecorator: (child, _, _) => Material(color: C.raised3, borderRadius: BorderRadius.circular(R.small + 2), child: child),
              itemBuilder: (_, i) => ReorderableDelayedDragStartListener(
                key: ValueKey('$i-${tracks[i].id}'),
                index: i,
                child: TrackRow(
                  track: tracks[i],
                  list: tracks,
                  index: i,
                  trailing: IconBtn(
                    LucideIcons.x,
                    size: 14,
                    box: 32,
                    color: C.faint,
                    tooltip: 'Remove from playlist',
                    onTap: () => lib.setPlaylistTracks(pl.id, [for (final t in tracks) t.id]..removeAt(i)),
                  ),
                ),
              ),
            ),
          const SliverToBoxAdapter(child: SizedBox(height: S.x6)),
        ],
      );
    },
  );
}
