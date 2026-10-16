import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../library/models.dart';
import '../app.dart';
import '../phone.dart';
import '../theme.dart';
import '../tracks.dart';
import '../widgets.dart';
import 'albums.dart';

/// Every song in a sortable table. Click a column title to sort; again to reverse.
class SongsPage extends StatefulWidget {
  const SongsPage({super.key});
  @override
  State<SongsPage> createState() => _SongsPageState();
}

class _SongsPageState extends State<SongsPage> {
  final _scroll = ScrollController();

  /// The phone's fast scroll: the letter under the thumb while it moves.
  final _letter = ValueNotifier<String?>(null);
  Timer? _hide;

  @override
  void dispose() {
    _scroll.dispose();
    _letter.dispose();
    _hide?.cancel();
    super.dispose();
  }

  static const _sorts = [
    ('title', 'Title'),
    ('artist', 'Artist'),
    ('album', 'Album'),
    ('year', 'Year'),
    ('format', 'Format'),
    ('time', 'Time'),
  ];

  /// Not a finger on the list (the scrollbar thumb, a fling): show the letter there.
  bool _scrolled(ScrollNotification n, List<Track> tracks) {
    String? key(Track t) => switch (_by) {
      'title' => t.title,
      'artist' => t.artist,
      'album' => t.album,
      'year' => '${t.year ?? ''}',
      _ => null,
    };
    if (n.depth != 0 || tracks.isEmpty) return false;
    if (n is ScrollUpdateNotification && n.dragDetails == null && n.metrics.maxScrollExtent > 0) {
      // ponytail: the row under the thumb by proportion, close enough for a letter.
      final i = (n.metrics.pixels / n.metrics.maxScrollExtent * (tracks.length - 1)).round().clamp(0, tracks.length - 1);
      final k = key(tracks[i])?.trim();
      _letter.value = k == null || k.isEmpty ? null : (_by == 'year' ? k : k.characters.first.toUpperCase());
      _hide?.cancel();
    } else if (n is ScrollEndNotification) {
      _hide = Timer(const Duration(milliseconds: 600), () => _letter.value = null);
    }
    return false;
  }

  Future<void> _sortSheet() async {
    final v = await phoneSheet(context, [
      for (final (k, label) in _sorts)
        (k, k == _by ? (_desc ? LucideIcons.arrowUp : LucideIcons.arrowDown) : LucideIcons.arrowUpDown, label),
    ], title: 'Sort songs by (again to reverse)');
    if (v != null) _sort(v);
  }

  // Kept across navigation.
  String get _by => nav.memo['songs.by'] as String? ?? 'title';
  set _by(String v) => nav.memo['songs.by'] = v;
  bool get _desc => nav.memo['songs.desc'] == true;
  set _desc(bool v) => nav.memo['songs.desc'] = v;

  static int _cmpStr(String a, String b) => a.toLowerCase().compareTo(b.toLowerCase());

  int Function(Track, Track) get _cmp => switch (_by) {
    'artist' => (a, b) => _cmpStr(a.artist, b.artist) != 0 ? _cmpStr(a.artist, b.artist) : _cmpStr(a.title, b.title),
    'album' => (a, b) => a.albumKey != b.albumKey ? _cmpStr(a.album, b.album) : compareAlbumOrder(a, b),
    'year' => (a, b) => (a.year ?? 0).compareTo(b.year ?? 0),
    'format' => (a, b) => (a.bitDepth * a.sampleRate).compareTo(b.bitDepth * b.sampleRate),
    'time' => (a, b) => a.durationMs.compareTo(b.durationMs),
    _ => (a, b) => _cmpStr(a.title, b.title),
  };

  void _sort(String by) => setState(() {
    _desc = _by == by ? !_desc : false;
    _by = by;
  });

  Widget _head(String label, String key, {int? flex, double? width, TextAlign align = TextAlign.left}) {
    final active = _by == key;
    final w = Clickable(
      onTap: () => _sort(key),
      radius: R.tiny + 2,
      hover: C.raised2,
      padding: const EdgeInsets.symmetric(vertical: S.x1, horizontal: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: align == TextAlign.right ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: T.caption.copyWith(fontWeight: FontWeight.w600, color: active ? C.text : C.faint),
            ),
          ),
          if (active) Icon(_desc ? LucideIcons.chevronDown : LucideIcons.chevronUp, size: 12, color: C.text),
        ],
      ),
    );
    final cell = Align(alignment: align == TextAlign.right ? Alignment.centerRight : Alignment.centerLeft, child: w);
    return flex != null ? Expanded(flex: flex, child: cell) : SizedBox(width: width, child: cell);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: lib,
    builder: (context, _) {
      final tracks = List.of(lib.tracks)..sort(_cmp);
      if (_desc) {
        final r = tracks.reversed.toList();
        tracks
          ..clear()
          ..addAll(r);
      }
      selection.primary = tracks;
      final phone = phoneLayout(context);
      final list = CustomScrollView(
        key: const PageStorageKey('songs'),
        controller: _scroll,
        slivers: [
          SliverToBoxAdapter(
            child: PageHeader(
              'Songs',
              subtitle: '${plural(tracks.length, 'song')} · ${fmtLong(Duration(milliseconds: tracks.fold(0, (s, t) => s + t.durationMs)))}',
              trailing: tracks.isEmpty
                  ? null
                  : phone
                  // Shuffle first (what a phone mostly does), Play, and the sort as a chip: no table header.
                  ? Wrap(
                      spacing: S.x2,
                      runSpacing: S.x2,
                      children: [
                        PillButton('Shuffle', icon: LucideIcons.shuffle, primary: true, onTap: () => shufflePlay(tracks)),
                        PillButton('Play', icon: LucideIcons.play, onTap: () => engine.playTracks(tracks)),
                        PillButton(
                          'Sort: ${_sorts.firstWhere((s) => s.$1 == _by).$2}',
                          key: const ValueKey('songs.sort'),
                          icon: _desc ? LucideIcons.arrowUp : LucideIcons.arrowDown,
                          onTap: _sortSheet,
                        ),
                      ],
                    )
                  : PillButton('Play all', icon: LucideIcons.play, primary: true, onTap: () => engine.playTracks(tracks)),
            ),
          ),
          if (tracks.isEmpty)
            const SliverFillRemaining(hasScrollBody: false, child: NoMusic())
          else ...[
            if (!phone)
              SliverPersistentHeader(
                pinned: true,
                delegate: _HeaderDelegate(
                  Container(
                    color: C.bg,
                    padding: const EdgeInsets.symmetric(horizontal: S.x2),
                    // The same columns the rows show at this width (they drop out in a small window).
                    child: LayoutBuilder(
                      builder: (context, c) {
                        final cols = TrackCols(c.maxWidth, table: true, album: true, badge: true);
                        return Row(
                          children: [
                            const SizedBox(width: 40 + S.x3),
                            _head('Title', 'title', flex: 5),
                            if (cols.artist) ...[const SizedBox(width: S.x4), _head('Artist', 'artist', flex: 3)],
                            if (cols.album) ...[const SizedBox(width: S.x4), _head('Album', 'album', flex: 3)],
                            if (cols.year) _head('Year', 'year', width: 56),
                            if (cols.badge) ...[const SizedBox(width: S.x4), _head('Format', 'format', width: 104)],
                            const SizedBox(width: 32),
                            _head('Time', 'time', width: 48, align: TextAlign.right),
                            const SizedBox(width: 32),
                          ],
                        );
                      },
                    ),
                  ),
                ),
              ),
            SliverFixedExtentList(
              itemExtent: TrackRow.extentOf(context),
              delegate: SliverChildBuilderDelegate(
                (_, i) => TrackRow(track: tracks[i], list: tracks, index: i, table: true),
                childCount: tracks.length,
              ),
            ),
          ],
          const SliverToBoxAdapter(child: SizedBox(height: S.x16)),
        ],
      );
      if (!phone) return list;
      // The phone: drag the scrollbar to fly through the list, with the letter you are at.
      return Stack(
        children: [
          NotificationListener<ScrollNotification>(
            onNotification: (n) => _scrolled(n, tracks),
            child: Scrollbar(controller: _scroll, interactive: true, thickness: 6, radius: const Radius.circular(R.pill), child: list),
          ),
          ValueListenableBuilder(
            valueListenable: _letter,
            builder: (_, l, _) => l == null
                ? const SizedBox.shrink()
                : Align(
                    alignment: const Alignment(0.8, 0),
                    child: IgnorePointer(
                      child: Container(
                        width: 64,
                        height: 64,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: C.raised3,
                          borderRadius: BorderRadius.circular(R.card),
                          border: Border.all(color: C.borderStrong),
                        ),
                        child: Text(l, style: T.title),
                      ),
                    ),
                  ),
          ),
        ],
      );
    },
  );
}

class _HeaderDelegate extends SliverPersistentHeaderDelegate {
  _HeaderDelegate(this.child);
  final Widget child;
  @override
  double get minExtent => 40;
  @override
  double get maxExtent => 40;
  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) => DecoratedBox(
    decoration: BoxDecoration(
      border: Border(bottom: BorderSide(color: C.border)),
    ),
    child: child,
  );
  @override
  bool shouldRebuild(_HeaderDelegate old) => true;
}
