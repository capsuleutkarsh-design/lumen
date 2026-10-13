import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../library/models.dart';
import '../app.dart';
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
  String _by = 'title';
  bool _desc = false;

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
      radius: R.small - 2,
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
      return CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: PageHeader(
              'Songs',
              subtitle: '${plural(tracks.length, 'song')} · ${fmtLong(Duration(milliseconds: tracks.fold(0, (s, t) => s + t.durationMs)))}',
              trailing: tracks.isEmpty
                  ? null
                  : PillButton('Play all', icon: LucideIcons.play, primary: true, onTap: () => engine.playTracks(tracks)),
            ),
          ),
          if (tracks.isEmpty)
            const SliverFillRemaining(hasScrollBody: false, child: NoMusic())
          else ...[
            SliverPersistentHeader(
              pinned: true,
              delegate: _HeaderDelegate(
                Container(
                  color: C.bg,
                  padding: const EdgeInsets.symmetric(horizontal: S.x2),
                  child: Row(
                    children: [
                      const SizedBox(width: 40 + S.x3),
                      _head('Title', 'title', flex: 5),
                      const SizedBox(width: S.x4),
                      _head('Artist', 'artist', flex: 3),
                      const SizedBox(width: S.x4),
                      _head('Album', 'album', flex: 3),
                      _head('Year', 'year', width: 56),
                      const SizedBox(width: S.x4),
                      _head('Format', 'format', width: 104),
                      const SizedBox(width: 32),
                      _head('Time', 'time', width: 52, align: TextAlign.right),
                      const SizedBox(width: 32),
                    ],
                  ),
                ),
              ),
            ),
            SliverFixedExtentList(
              itemExtent: TrackRow.height,
              delegate: SliverChildBuilderDelegate(
                (_, i) => TrackRow(track: tracks[i], list: tracks, index: i, table: true),
                childCount: tracks.length,
              ),
            ),
          ],
          const SliverToBoxAdapter(child: SizedBox(height: S.x6)),
        ],
      );
    },
  );
}

class _HeaderDelegate extends SliverPersistentHeaderDelegate {
  _HeaderDelegate(this.child);
  final Widget child;
  @override
  double get minExtent => 36;
  @override
  double get maxExtent => 36;
  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) => DecoratedBox(
    decoration: const BoxDecoration(
      border: Border(bottom: BorderSide(color: C.border)),
    ),
    child: child,
  );
  @override
  bool shouldRebuild(_HeaderDelegate old) => true;
}
