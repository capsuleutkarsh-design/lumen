import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../library/library.dart';
import '../../library/models.dart';
import '../../platform/android.dart' show saveText;
import '../app.dart';
import '../theme.dart';
import '../tracks.dart';
import '../widgets.dart';
import 'albums.dart';
import 'smart_playlists.dart';

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

List<Track> playlistTracks(Playlist pl) => [for (final i in pl.trackIds) lib.byId[i]].whereType<Track>().toList();

/// Rename, export and delete: the playlist's own entries in its menus.
List<(String, IconData, String, VoidCallback)> playlistActions(BuildContext context, Playlist pl, {bool leave = false}) => [
  (
    'rename',
    LucideIcons.pencil,
    'Rename…',
    () async {
      final name = await askText(context, 'Rename playlist', initial: pl.name);
      if (name != null) lib.renamePlaylist(pl.id, name);
    },
  ),
  (
    'export',
    LucideIcons.upload,
    'Export as M3U8…',
    () async {
      final to = await saveText('${pl.name}.m3u8', lib.exportM3u(pl.id), _m3u);
      if (to != null && context.mounted) toast(context, 'Saved $to');
    },
  ),
  (
    'delete',
    LucideIcons.trash2,
    'Delete…',
    () async {
      if (await confirm(context, 'Delete “${pl.name}”?', 'The songs stay in your library; only the playlist is removed.')) {
        lib.deletePlaylist(pl.id);
        if (leave) nav.back();
      }
    },
  ),
];

class PlaylistsPage extends StatelessWidget {
  const PlaylistsPage({super.key});

  static double _extra(BuildContext context) => S.x3 + textHeight(context, [T.label, T.small]) + 2;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: lib,
    builder: (context, _) => CustomScrollView(
      key: const PageStorageKey('playlists'),
      slivers: [
        SliverToBoxAdapter(
          child: PageHeader(
            'Playlists',
            subtitle: plural(lib.playlists.length, 'playlist'),
            trailing: Wrap(
              spacing: S.x3,
              runSpacing: S.x2,
              children: [
                PillButton('Import M3U', icon: LucideIcons.download, onTap: () => importPlaylist(context)),
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
        ...smartPlaylistSlivers(context),
        if (lib.playlists.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: EmptyState(
              icon: LucideIcons.listMusic,
              title: 'No playlists yet',
              body: 'Make one with New playlist, or $menuWord any song and choose Add to playlist.',
            ),
          )
        else
          sliverCards(
            extra: _extra(context),
            count: lib.playlists.length,
            builder: (_, i) {
              final pl = lib.playlists[i];
              return DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(R.card),
                  border: Border.all(color: C.border),
                ),
                child: Clickable(
                  onTap: () => nav.push('playlist', pl.id),
                  onSecondaryTapDown: (d) =>
                      showCollectionMenu(context, d.globalPosition, playlistTracks(pl), extra: playlistActions(context, pl)),
                  semanticLabel: 'Playlist ${pl.name}',
                  radius: R.card,
                  padding: const EdgeInsets.all(S.x2),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      PlaylistCover(pl, radius: R.card - S.x2),
                      const SizedBox(height: S.x3),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: S.x1),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(pl.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: T.label),
                            Text(plural(pl.trackIds.length, 'song'), maxLines: 1, style: T.small),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        const SliverToBoxAdapter(child: SizedBox(height: S.x16)),
      ],
    ),
  );
}

/// A playlist's cover: four album covers in a square, else the first one,
/// else its own gradient. The same on the card and the header.
class PlaylistCover extends StatelessWidget {
  const PlaylistCover(this.pl, {super.key, this.radius = R.cover});
  final Playlist pl;
  final double radius;
  @override
  Widget build(BuildContext context) {
    final albums = <String, Track>{};
    for (final id in pl.trackIds) {
      final t = lib.byId[id];
      if (t != null) albums.putIfAbsent(t.albumKey, () => t);
      if (albums.length == 4) break;
    }
    final firsts = albums.values.toList();
    if (firsts.length < 4) {
      return firsts.isEmpty ? CoverArt(null, radius: radius, seed: pl.name) : CoverArt.track(firsts.first, radius: radius);
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: AspectRatio(
        aspectRatio: 1,
        child: GridView.count(
          crossAxisCount: 2,
          physics: const NeverScrollableScrollPhysics(),
          children: [for (final t in firsts) CoverArt.track(t, radius: 0)],
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
      final tracks = playlistTracks(pl);
      selection.primary = tracks;
      final first = tracks.firstOrNull;
      return CustomScrollView(
        key: PageStorageKey('playlist/$id'),
        slivers: [
          SliverToBoxAdapter(
            child: PageHero(
              cover: PlaylistCover(pl, radius: R.card),
              glow: first == null ? resolveArt(null, seed: pl.name) : lib.artFor(first.albumKey, first.cover),
              title: pl.name,
              label: 'Playlist',
              meta: [
                plural(tracks.length, 'song'),
                fmtLong(Duration(milliseconds: tracks.fold(0, (s, t) => s + t.durationMs))),
              ],
              tracks: tracks,
              menu: playlistActions(context, pl, leave: true),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: S.x4)),
          if (tracks.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: EmptyState(
                icon: LucideIcons.listPlus,
                title: 'This playlist is empty',
                body: '${menuWord[0].toUpperCase()}${menuWord.substring(1)} any song and choose Add to playlist.',
              ),
            )
          else
            SliverReorderableList(
              itemCount: tracks.length,
              itemExtent: TrackRow.extentOf(context),
              onReorderItem: (from, to) {
                final ids = [for (final t in tracks) t.id];
                ids.insert(to, ids.removeAt(from));
                lib.setPlaylistTracks(pl.id, ids);
              },
              proxyDecorator: (child, _, _) => Material(color: C.raised3, borderRadius: BorderRadius.circular(R.small), child: child),
              itemBuilder: (_, i) => KeyedSubtree(
                key: ValueKey('$i-${tracks[i].id}'),
                child: TrackRow(
                  track: tracks[i],
                  list: tracks,
                  index: i,
                  // A grip to drag the song to a new place.
                  lead: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ReorderableDragStartListener(
                        index: i,
                        child: MouseRegion(
                          cursor: SystemMouseCursors.grab,
                          child: Tooltip(
                            message: 'Drag to reorder',
                            child: SizedBox(width: 20, height: 40, child: Icon(LucideIcons.gripVertical, size: 14, color: C.faint)),
                          ),
                        ),
                      ),
                      const SizedBox(width: S.x1),
                      CoverArt.track(tracks[i], size: 40, radius: R.tiny + 2),
                    ],
                  ),
                  trailing: IconBtn(
                    LucideIcons.x,
                    size: 14,
                    box: 32,
                    color: C.faint,
                    tooltip: 'Remove from playlist',
                    onTap: () {
                      final before = [for (final t in tracks) t.id];
                      lib.setPlaylistTracks(pl.id, List.of(before)..removeAt(i));
                      toast(context, 'Removed “${tracks[i].title}”', actions: [('Undo', () => lib.setPlaylistTracks(pl.id, before))]);
                    },
                  ),
                ),
              ),
            ),
          const SliverToBoxAdapter(child: SizedBox(height: S.x16)),
        ],
      );
    },
  );
}
