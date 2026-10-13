import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../library/models.dart';
import 'app.dart';
import 'theme.dart';
import 'widgets.dart';

/// Right-click menu for one or more tracks.
Future<void> showTrackMenu(BuildContext context, Offset at, List<Track> tracks, {Track? single}) async {
  final t = single ?? (tracks.length == 1 ? tracks.first : null);
  PopupMenuItem<String> item(String v, IconData icon, String label) => PopupMenuItem(
    value: v,
    height: 36,
    child: Row(
      children: [
        Icon(icon, size: 16, color: C.dim),
        const SizedBox(width: S.x3),
        Text(label, style: T.label),
      ],
    ),
  );
  final v = await showMenu<String>(
    context: context,
    position: RelativeRect.fromLTRB(at.dx, at.dy, at.dx, at.dy),
    items: [
      item('now', LucideIcons.play, 'Play now'),
      item('next', LucideIcons.listStart, 'Play next'),
      item('queue', LucideIcons.listEnd, 'Add to queue'),
      item('playlist', LucideIcons.listPlus, 'Add to playlist…'),
      if (t != null) ...[
        const PopupMenuDivider(height: 8),
        item('fav', LucideIcons.heart, lib.isFavourite(t.id) ? 'Remove from Favourites' : 'Add to Favourites'),
        item('album', LucideIcons.disc3, 'Go to album'),
        item('artist', LucideIcons.micVocal, 'Go to artist'),
      ],
    ],
  );
  if (!context.mounted) return;
  final n = plural(tracks.length, 'song');
  switch (v) {
    case 'now':
      engine.playTracks(tracks);
    case 'next':
      engine.playNext(tracks);
      toast(context, '$n will play next');
    case 'queue':
      engine.addToQueue(tracks);
      toast(context, 'Added $n to the queue');
    case 'playlist':
      await addToPlaylistDialog(context, tracks);
    case 'fav':
      lib.toggleFavourite(t!.id);
    case 'album':
      nav.push('album', t!.albumKey);
    case 'artist':
      nav.push('artist', t!.artist);
  }
}

Future<void> addToPlaylistDialog(BuildContext context, List<Track> tracks) async {
  final id = await showDialog<int>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Add to playlist'),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Clickable(
              onTap: () async {
                final name = await askText(ctx, 'New playlist', action: 'Create');
                if (name != null && ctx.mounted) Navigator.pop(ctx, lib.createPlaylist(name));
              },
              padding: const EdgeInsets.all(S.x3),
              child: Row(
                children: [
                  const Icon(LucideIcons.plus, size: 16, color: C.accent),
                  const SizedBox(width: S.x3),
                  Text('New playlist', style: T.label.copyWith(color: C.accent)),
                ],
              ),
            ),
            for (final pl in lib.playlists)
              Clickable(
                onTap: () => Navigator.pop(ctx, pl.id),
                padding: const EdgeInsets.all(S.x3),
                child: Row(
                  children: [
                    const Icon(LucideIcons.listMusic, size: 16, color: C.dim),
                    const SizedBox(width: S.x3),
                    Expanded(child: Text(pl.name, style: T.label)),
                    Text(plural(pl.trackIds.length, 'song'), style: T.caption),
                  ],
                ),
              ),
          ],
        ),
      ),
    ),
  );
  if (id == null) return;
  lib.addToPlaylist(id, [for (final t in tracks) t.id]);
  if (context.mounted) toast(context, 'Added ${plural(tracks.length, 'song')} to ${lib.playlists.firstWhere((p) => p.id == id).name}');
}

/// One song row. Double-click plays [list] from this song.
class TrackRow extends StatelessWidget {
  const TrackRow({
    super.key,
    required this.track,
    required this.list,
    required this.index,
    this.number,
    this.showCover = true,
    this.showAlbum = true,
    this.why,
    this.trailing,
    this.table = false,
  });
  final Track track;
  final List<Track> list;
  final int index;
  final int? number;
  final bool showCover, showAlbum;
  final String? why;
  final Widget? trailing;

  /// Songs page layout: artist and year get their own columns.
  final bool table;

  static const height = 56.0;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([engine, lib]),
    builder: (context, _) {
      final isCurrent = engine.current?.id == track.id;
      final fav = lib.isFavourite(track.id);
      Widget lead;
      if (isCurrent) {
        lead = SizedBox(
          width: 40,
          child: Center(child: PlayingBars(playing: engine.playing)),
        );
      } else if (showCover) {
        lead = CoverArt(track.cover, size: 40, radius: R.small - 2);
      } else {
        lead = SizedBox(
          width: 40,
          child: Text(
            '${number ?? index + 1}',
            textAlign: TextAlign.center,
            style: T.small.copyWith(color: C.faint, fontFeatures: T.tabular),
          ),
        );
      }
      final row = Clickable(
        onDoubleTap: () => engine.playTracks(list, index),
        onSecondaryTapDown: (d) => showTrackMenu(context, d.globalPosition, [track]),
        radius: R.small + 2,
        padding: const EdgeInsets.symmetric(horizontal: S.x2),
        child: SizedBox(
          height: height,
          child: Row(
            children: [
              lead,
              const SizedBox(width: S.x3),
              Expanded(
                flex: 5,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      track.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: T.label.copyWith(color: isCurrent ? C.accent : C.text),
                    ),
                    const SizedBox(height: 2),
                    if (!table) Text(why ?? track.artist, maxLines: 1, overflow: TextOverflow.ellipsis, style: T.small),
                  ],
                ),
              ),
              if (table) ...[
                const SizedBox(width: S.x4),
                Expanded(
                  flex: 3,
                  child: Text(track.artist, maxLines: 1, overflow: TextOverflow.ellipsis, style: T.small),
                ),
              ],
              if (showAlbum) ...[
                const SizedBox(width: S.x4),
                Expanded(
                  flex: 3,
                  child: Text(track.album, maxLines: 1, overflow: TextOverflow.ellipsis, style: T.small),
                ),
              ],
              if (table)
                SizedBox(
                  width: 56,
                  child: Text(track.year?.toString() ?? '', style: T.small.copyWith(fontFeatures: T.tabular)),
                ),
              const SizedBox(width: S.x4),
              SizedBox(
                width: 104,
                child: Align(alignment: Alignment.centerLeft, child: FormatBadge(track.badge)),
              ),
              IconBtn(
                fav ? Icons.favorite_rounded : LucideIcons.heart,
                size: 16,
                box: 32,
                color: fav ? C.accent : C.faint,
                tooltip: fav ? 'Remove from Favourites' : 'Add to Favourites',
                onTap: () => lib.toggleFavourite(track.id),
              ),
              SizedBox(
                width: 52,
                child: Text(
                  fmtTime(track.duration),
                  textAlign: TextAlign.right,
                  style: T.small.copyWith(fontFeatures: T.tabular),
                ),
              ),
              ?trailing,
              IconBtn(
                LucideIcons.ellipsis,
                size: 16,
                box: 32,
                color: C.faint,
                tooltip: 'More',
                onTap: () {
                  final box = context.findRenderObject() as RenderBox;
                  showTrackMenu(context, box.localToGlobal(Offset(box.size.width - 40, height)), [track]);
                },
              ),
            ],
          ),
        ),
      );
      return why == null ? row : Tooltip(message: 'Why: $why', child: row);
    },
  );
}

/// A list of songs inside a CustomScrollView.
class SliverTracks extends StatelessWidget {
  const SliverTracks(this.tracks, {super.key, this.numbered = false, this.showAlbum = true, this.whys});
  final List<Track> tracks;
  final bool numbered, showAlbum;
  final List<String>? whys;
  @override
  Widget build(BuildContext context) => SliverFixedExtentList(
    itemExtent: TrackRow.height,
    delegate: SliverChildBuilderDelegate(
      (_, i) => TrackRow(
        track: tracks[i],
        list: tracks,
        index: i,
        number: numbered ? tracks[i].trackNo : null,
        showCover: !numbered,
        showAlbum: showAlbum,
        why: whys?[i],
      ),
      childCount: tracks.length,
    ),
  );
}
