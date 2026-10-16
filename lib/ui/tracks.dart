import 'dart:math';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../library/models.dart';
import '../platform/window.dart' show isTouch;
import 'app.dart';
import 'theme.dart';
import 'widgets.dart';

// ------------------------------------------------------------ selection

/// The selected songs. Click selects one, Ctrl+click toggles, Shift+click
/// selects a range, Ctrl+A selects the whole list. Cleared on navigation.
class Selection extends ChangeNotifier {
  final ids = <int>{};
  List<Track> _list = const [];
  int? _anchor; // track id

  /// The page's main list (what Ctrl+A selects before anything is clicked).
  List<Track> primary = const [];

  bool has(int id) => ids.contains(id);
  int get length => ids.length;

  /// Selected songs in list order.
  List<Track> get tracks {
    final inList = [
      for (final t in _list)
        if (ids.contains(t.id)) t,
    ];
    if (inList.length == ids.length) return inList;
    final seen = {for (final t in inList) t.id};
    return [
      ...inList,
      for (final id in ids)
        if (!seen.contains(id)) ?lib.byId[id],
    ];
  }

  void click(List<Track> list, int i, {bool toggle = false, bool range = false}) {
    final id = list[i].id;
    final a = _anchor == null ? -1 : list.indexWhere((t) => t.id == _anchor);
    if (range && a >= 0) {
      if (!toggle) ids.clear();
      ids.addAll([for (var k = min(a, i); k <= max(a, i); k++) list[k].id]);
    } else if (toggle) {
      if (!ids.remove(id)) ids.add(id);
      _anchor = id;
    } else {
      ids
        ..clear()
        ..add(id);
      _anchor = id;
    }
    _list = list;
    notifyListeners();
  }

  void selectAll() {
    final l = _list.isNotEmpty ? _list : primary;
    if (l.isEmpty) return;
    ids
      ..clear()
      ..addAll(l.map((t) => t.id));
    _list = l;
    notifyListeners();
  }

  void clear() {
    _anchor = null;
    _list = const [];
    if (ids.isEmpty) return;
    ids.clear();
    notifyListeners();
  }
}

final selection = Selection();

// ------------------------------------------------------------ menus and queue actions

PopupMenuItem<String> menuItem(String v, IconData icon, String label, {String? hint}) => PopupMenuItem(
  value: v,
  height: 36,
  child: Row(
    children: [
      Icon(icon, size: 16, color: C.dim),
      const SizedBox(width: S.x3),
      Expanded(child: Text(label, style: T.label)),
      if (hint != null && !isTouch) ...[const SizedBox(width: S.x4), Text(hint, style: T.caption)],
    ],
  ),
);

Future<String?> popMenu(BuildContext context, Offset at, List<PopupMenuEntry<String>> items) => showMenu<String>(
  context: context,
  position: RelativeRect.fromLTRB(at.dx, at.dy, at.dx, at.dy),
  popUpAnimationStyle: const AnimationStyle(duration: Motion.fast),
  items: items,
);

/// Play next / add to queue, with a toast that can show the queue or undo it.
Future<void> queueTracks(BuildContext context, List<Track> tracks, {required bool next}) async {
  if (tracks.isEmpty) return;
  final before = {for (final e in engine.queue.items) e.uid};
  await (next ? engine.playNext(tracks) : engine.addToQueue(tracks));
  final added = {
    for (final e in engine.queue.items)
      if (!before.contains(e.uid)) e.uid,
  };
  final n = tracks.length == 1 ? '“${tracks.first.title}”' : plural(tracks.length, 'song');
  if (!context.mounted) return;
  toast(
    context,
    next ? '$n will play next' : 'Added $n to the queue',
    actions: [('Undo', () => _unqueue(added)), if (!nav.queue) ('Show queue', nav.toggleQueue)],
  );
}

Future<void> _unqueue(Set<int> uids) async {
  final items = engine.queue.items;
  for (var i = items.length - 1; i >= 0; i--) {
    if (uids.contains(items[i].uid) && i != engine.queue.index) await engine.removeFromQueue(i);
  }
}

Future<void> shufflePlay(List<Track> tracks) async {
  if (tracks.isEmpty) return;
  await engine.setShuffle(true);
  await engine.playTracks(tracks, Random().nextInt(tracks.length));
}

void favouriteAll(List<Track> tracks) {
  final allFav = tracks.every((t) => lib.isFavourite(t.id));
  for (final t in tracks) {
    if (allFav || !lib.isFavourite(t.id)) lib.toggleFavourite(t.id);
  }
}

/// Right-click menu for one or more songs.
Future<void> showTrackMenu(BuildContext context, Offset at, List<Track> tracks, {Track? single}) async {
  final t = single ?? (tracks.length == 1 ? tracks.first : null);
  final allFav = tracks.every((x) => lib.isFavourite(x.id));
  final v = await popMenu(context, at, [
    menuItem(
      'now',
      LucideIcons.play,
      tracks.length > 1 ? 'Play ${tracks.length} songs' : 'Play now',
      hint: tracks.length == 1 ? 'Enter' : null,
    ),
    menuItem('next', LucideIcons.listStart, 'Play next'),
    menuItem('queue', LucideIcons.listEnd, 'Add to queue'),
    menuItem('playlist', LucideIcons.listPlus, 'Add to playlist…'),
    const PopupMenuDivider(height: S.x2),
    menuItem('fav', LucideIcons.heart, allFav ? 'Remove from Favourites' : 'Add to Favourites'),
    if (t != null) ...[menuItem('album', LucideIcons.disc3, 'Go to album'), menuItem('artist', LucideIcons.users, 'Go to artist')],
  ]);
  if (!context.mounted) return;
  switch (v) {
    case 'now':
      engine.playTracks(tracks);
    case 'next':
      await queueTracks(context, tracks, next: true);
    case 'queue':
      await queueTracks(context, tracks, next: false);
    case 'playlist':
      await addToPlaylistDialog(context, tracks);
    case 'fav':
      favouriteAll(tracks);
    case 'album':
      nav.push('album', t!.albumKey);
    case 'artist':
      nav.push('artist', t!.artist);
  }
}

/// Right-click menu for an album, artist, folder or playlist (and their ••• buttons).
Future<void> showCollectionMenu(
  BuildContext context,
  Offset at,
  List<Track> tracks, {
  List<(String, IconData, String, VoidCallback)> extra = const [],
}) async {
  final v = await popMenu(context, at, [
    menuItem('now', LucideIcons.play, 'Play'),
    menuItem('shuffle', LucideIcons.shuffle, 'Shuffle'),
    menuItem('next', LucideIcons.listStart, 'Play next'),
    menuItem('queue', LucideIcons.listEnd, 'Add to queue'),
    menuItem('playlist', LucideIcons.listPlus, 'Add to playlist…'),
    if (extra.isNotEmpty) const PopupMenuDivider(height: S.x2),
    for (final (id, icon, label, _) in extra) menuItem(id, icon, label),
  ]);
  if (!context.mounted || v == null) return;
  switch (v) {
    case 'now':
      engine.playTracks(tracks);
    case 'shuffle':
      await shufflePlay(tracks);
    case 'next':
      await queueTracks(context, tracks, next: true);
    case 'queue':
      await queueTracks(context, tracks, next: false);
    case 'playlist':
      await addToPlaylistDialog(context, tracks);
    default:
      for (final (id, _, _, f) in extra) {
        if (id == v) f();
      }
  }
}

/// Where a ••• button's menu opens: under the button.
Offset below(BuildContext context) {
  final box = context.findRenderObject() as RenderBox;
  return box.localToGlobal(Offset(0, box.size.height + S.x1));
}

Future<void> addToPlaylistDialog(BuildContext context, List<Track> tracks) async {
  final id = await showDialog<int>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('Add ${plural(tracks.length, 'song')} to a playlist'),
      content: SizedBox(
        width: 360,
        child: SingleChildScrollView(
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
                    Icon(LucideIcons.plus, size: 16, color: C.text),
                    const SizedBox(width: S.x3),
                    Text('New playlist', style: T.label),
                  ],
                ),
              ),
              for (final pl in lib.playlists)
                Clickable(
                  onTap: () => Navigator.pop(ctx, pl.id),
                  padding: const EdgeInsets.all(S.x3),
                  child: Row(
                    children: [
                      Icon(LucideIcons.listMusic, size: 16, color: C.dim),
                      const SizedBox(width: S.x3),
                      Expanded(
                        child: Text(pl.name, style: T.label, maxLines: 1, overflow: TextOverflow.ellipsis),
                      ),
                      Text(plural(pl.trackIds.length, 'song'), style: T.caption),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
  );
  if (id == null) return;
  final before = List.of(lib.playlists.firstWhere((p) => p.id == id).trackIds);
  lib.addToPlaylist(id, [for (final t in tracks) t.id]);
  if (context.mounted) {
    toast(
      context,
      'Added ${plural(tracks.length, 'song')} to ${lib.playlists.firstWhere((p) => p.id == id).name}',
      actions: [('Undo', () => lib.setPlaylistTracks(id, before))],
    );
  }
}

// ------------------------------------------------------------ rows

/// Which columns a song row has room for at [width].
class TrackCols {
  TrackCols(double width, {required bool table, required bool album, required bool badge})
    : artist = table && width >= 520,
      album = album && width >= (table ? 640 : 600),
      year = table && width >= 760,
      badge = badge && width >= (table ? 700 : 520);
  final bool artist, album, year, badge;
}

/// One song row. Click selects, double-click or Enter plays [list] from here,
/// right-click (or the menu key) opens the menu.
class TrackRow extends StatefulWidget {
  const TrackRow({
    super.key,
    required this.track,
    required this.list,
    required this.index,
    this.number,
    this.showCover = true,
    this.showAlbum = true,
    this.showBadge = true,
    this.albumArtist,
    this.why,
    this.trailing,
    this.lead,
    this.table = false,
  });
  final Track track;
  final List<Track> list;
  final int index;
  final int? number;
  final bool showCover, showAlbum, showBadge;

  /// On an album page: the artist line is shown only for songs by someone else.
  final String? albumArtist;
  final String? why;
  final Widget? trailing, lead;

  /// Songs page layout: artist and year get their own columns.
  final bool table;

  static const height = 56.0;

  /// Row height at the user's text size.
  static double extentOf(BuildContext context) => max(height, textHeight(context, [T.label, T.small]) + S.x4);

  @override
  State<TrackRow> createState() => _TrackRowState();
}

class _TrackRowState extends State<TrackRow> {
  bool _hover = false, _pointer = false;

  void _select(PointerDownEvent e) {
    _pointer = true; // the focus change this click causes is not a keyboard move
    WidgetsBinding.instance.addPostFrameCallback((_) => _pointer = false);
    if (e.buttons != kPrimaryMouseButton || isTouch) return; // touch: a tap plays; a long press selects for its menu
    selection.click(widget.list, widget.index, toggle: ctrl, range: shift);
  }

  void _menu(TapDownDetails d) {
    final t = widget.track;
    if (!selection.has(t.id)) selection.click(widget.list, widget.index);
    final tracks = selection.length > 1 ? selection.tracks : [t];
    showTrackMenu(context, d.globalPosition, tracks, single: tracks.length == 1 ? t : null);
  }

  void _play() => engine.playTracks(widget.list, widget.index);

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([engine, lib, selection]),
    builder: (context, _) {
      final track = widget.track;
      final isCurrent = engine.current?.id == track.id;
      final fav = lib.isFavourite(track.id);
      final selected = selection.has(track.id);
      final quiet = !(_hover || selected || isCurrent);
      // Hovering shows a play button on the lead: one click plays from this row.
      final playBtn = _hover && !isCurrent && !isTouch;
      Widget scrim(Widget child) => Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(color: C.scrim, borderRadius: BorderRadius.circular(R.tiny + 2)),
        child: child,
      );
      Widget play({bool onCover = false}) => Clickable(
        onTap: _play,
        tooltip: 'Play',
        semanticLabel: 'Play ${track.title}',
        radius: R.tiny + 2,
        hover: Colors.transparent,
        child: onCover
            ? scrim(Icon(LucideIcons.play, size: 16, color: C.text))
            : SizedBox(height: 40, child: Icon(LucideIcons.play, size: 16, color: C.text)),
      );
      Widget lead;
      if (widget.lead != null) {
        lead = widget.lead!;
      } else if (widget.showCover) {
        lead = Stack(
          alignment: Alignment.center,
          children: [
            CoverArt.track(track, size: 40, radius: R.tiny + 2),
            if (isCurrent) scrim(Center(child: PlayingBars(playing: engine.playing))),
            if (playBtn) play(onCover: true),
          ],
        );
      } else {
        lead = SizedBox(
          width: 40,
          child: isCurrent
              ? Center(child: PlayingBars(playing: engine.playing))
              : playBtn
              ? play()
              : Text(
                  '${widget.number ?? widget.index + 1}',
                  textAlign: TextAlign.center,
                  style: T.small.copyWith(color: C.faint, fontFeatures: T.tabular),
                ),
        );
      }
      // A suggestion's reason ([why]) shows in the tooltip; the row keeps the artist.
      final sub = widget.table || (widget.albumArtist != null && track.artist.toLowerCase() == widget.albumArtist!.toLowerCase())
          ? null
          : track.artist;
      final row = Listener(
        onPointerDown: _select,
        child: Clickable(
          onDoubleTap: _play,
          onActivate: _play,
          onSecondaryTapDown: _menu,
          onHover: (v) => setState(() => _hover = v),
          spaceActivates: false,
          focusOnTap: true,
          onFocusChange: (f) {
            // Arrow keys move the selection with the focus (Shift extends it).
            if (f && !_pointer) selection.click(widget.list, widget.index, range: shift);
          },
          selected: selected,
          selectedColor: C.raised3,
          semanticLabel: '${track.title}, ${track.artist}',
          radius: R.small,
          padding: const EdgeInsets.symmetric(horizontal: S.x2),
          child: SizedBox(
            height: TrackRow.extentOf(context),
            child: LayoutBuilder(
              builder: (context, c) {
                final cols = TrackCols(c.maxWidth, table: widget.table, album: widget.showAlbum, badge: widget.showBadge);
                return Row(
                  children: [
                    lead,
                    const SizedBox(width: S.x3),
                    Expanded(
                      flex: 5,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  track.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: T.label.copyWith(color: isCurrent ? C.accent : C.text),
                                ),
                              ),
                              if (engine.cantPlay.contains(track.id))
                                Padding(
                                  padding: const EdgeInsets.only(left: S.x2),
                                  child: Tooltip(
                                    message: "Can't play this file (missing or unreadable)",
                                    child: Icon(LucideIcons.fileX, size: 14, color: C.faint),
                                  ),
                                ),
                            ],
                          ),
                          if (sub != null) Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: T.small),
                        ],
                      ),
                    ),
                    if (cols.artist) ...[
                      const SizedBox(width: S.x4),
                      Expanded(
                        flex: 3,
                        child: Text(track.artist, maxLines: 1, overflow: TextOverflow.ellipsis, style: T.small),
                      ),
                    ],
                    if (cols.album) ...[
                      const SizedBox(width: S.x4),
                      Expanded(
                        flex: 3,
                        child: Text(track.album, maxLines: 1, overflow: TextOverflow.ellipsis, style: T.small),
                      ),
                    ],
                    if (cols.year)
                      SizedBox(
                        width: 56,
                        child: Text(track.year?.toString() ?? '', style: T.small.copyWith(fontFeatures: T.tabular)),
                      ),
                    if (cols.badge) ...[
                      const SizedBox(width: S.x4),
                      SizedBox(
                        width: 104,
                        child: Align(alignment: Alignment.centerLeft, child: FormatBadge(track.badge)),
                      ),
                    ],
                    AnimatedOpacity(
                      opacity: fav || !quiet ? 1 : 0,
                      duration: Motion.fast,
                      child: IconBtn(
                        fav ? Icons.favorite_rounded : LucideIcons.heart,
                        size: 16,
                        box: 32,
                        color: fav ? C.accent : C.faint,
                        tooltip: fav ? 'Remove from Favourites' : 'Add to Favourites',
                        onTap: () => lib.toggleFavourite(track.id),
                      ),
                    ),
                    SizedBox(
                      width: 48,
                      child: Text(
                        fmtTime(track.duration),
                        textAlign: TextAlign.right,
                        style: T.small.copyWith(fontFeatures: T.tabular),
                      ),
                    ),
                    ?widget.trailing,
                    AnimatedOpacity(
                      opacity: quiet ? 0 : 1,
                      duration: Motion.fast,
                      child: Builder(
                        builder: (b) => IconBtn(
                          LucideIcons.ellipsis,
                          size: 16,
                          box: 32,
                          color: C.dim,
                          tooltip: 'More',
                          onTap: () => _menu(TapDownDetails(globalPosition: below(b))),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      );
      return widget.why == null ? row : Tooltip(message: 'Why: ${widget.why}', waitDuration: const Duration(seconds: 1), child: row);
    },
  );
}

/// A list of songs inside a CustomScrollView.
class SliverTracks extends StatelessWidget {
  const SliverTracks(
    this.tracks, {
    super.key,
    this.numbered = false,
    this.showAlbum = true,
    this.showBadge = true,
    this.albumArtist,
    this.whys,
    this.all,
    this.primary = false,
  });
  final List<Track> tracks;
  final bool numbered, showAlbum, showBadge;
  final String? albumArtist;
  final List<String>? whys;

  /// The list double-click plays from (an album's discs play the whole album).
  final List<Track>? all;

  /// This is the page's main list: Ctrl+A selects it.
  final bool primary;
  @override
  Widget build(BuildContext context) {
    final list = all ?? tracks;
    if (primary) selection.primary = list;
    return SliverFixedExtentList(
      itemExtent: TrackRow.extentOf(context),
      delegate: SliverChildBuilderDelegate((_, i) {
        final t = tracks[i];
        final index = identical(list, tracks) ? i : list.indexOf(t);
        return TrackRow(
          track: t,
          list: list,
          index: index,
          number: numbered ? t.trackNo : null,
          showCover: !numbered,
          showAlbum: showAlbum,
          showBadge: showBadge,
          albumArtist: albumArtist,
          why: whys?[i],
        );
      }, childCount: tracks.length),
    );
  }
}

/// Shown while two or more songs are selected.
class SelectionBar extends StatelessWidget {
  const SelectionBar({super.key});
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([selection, lib]),
    builder: (context, _) {
      final n = selection.length;
      final show = n > 1;
      return IgnorePointer(
        ignoring: !show,
        child: AnimatedSlide(
          offset: show ? Offset.zero : const Offset(0, 0.3),
          duration: Motion.normal,
          curve: Motion.curve,
          child: AnimatedOpacity(
            opacity: show ? 1 : 0,
            duration: Motion.normal,
            child: !show
                ? const SizedBox(height: 56)
                : Container(
                    padding: const EdgeInsets.fromLTRB(S.x5, S.x2, S.x2, S.x2),
                    decoration: BoxDecoration(
                      color: C.raised2,
                      borderRadius: BorderRadius.circular(R.pill),
                      border: Border.all(color: C.borderStrong),
                      boxShadow: [BoxShadow(color: C.shadow, blurRadius: 32, offset: Offset(0, 12))],
                    ),
                    child: Builder(
                      builder: (context) {
                        final tracks = selection.tracks;
                        final allFav = tracks.every((t) => lib.isFavourite(t.id));
                        return Wrap(
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: S.x1,
                          runSpacing: S.x1,
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(right: S.x3),
                              child: Text('$n selected', style: T.label),
                            ),
                            PillButton('Play', icon: LucideIcons.play, primary: true, dense: true, onTap: () => engine.playTracks(tracks)),
                            IconBtn(
                              LucideIcons.listStart,
                              color: C.text,
                              tooltip: 'Play next',
                              onTap: () => queueTracks(context, tracks, next: true),
                            ),
                            IconBtn(
                              LucideIcons.listEnd,
                              color: C.text,
                              tooltip: 'Add to queue',
                              onTap: () => queueTracks(context, tracks, next: false),
                            ),
                            IconBtn(
                              LucideIcons.listPlus,
                              color: C.text,
                              tooltip: 'Add to playlist',
                              onTap: () => addToPlaylistDialog(context, tracks),
                            ),
                            IconBtn(
                              allFav ? Icons.favorite_rounded : LucideIcons.heart,
                              color: allFav ? C.accent : C.text,
                              tooltip: allFav ? 'Remove from Favourites' : 'Add to Favourites',
                              onTap: () => favouriteAll(tracks),
                            ),
                            IconBtn(LucideIcons.x, tooltip: 'Clear selection  (Esc)', onTap: selection.clear),
                          ],
                        );
                      },
                    ),
                  ),
          ),
        ),
      );
    },
  );
}
