import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../library/models.dart';
import '../../platform/window.dart' show isTouch;
import '../app.dart';
import '../theme.dart';
import '../tracks.dart';
import '../widgets.dart';
import 'albums.dart';

/// Whether [t] matches the Songs filter [q] (lower case): in the title, artist or album.
bool songMatches(Track t, String q) =>
    t.title.toLowerCase().contains(q) || t.artist.toLowerCase().contains(q) || t.album.toLowerCase().contains(q);

/// Ctrl+F on the Songs page focuses its filter.
final songsFilterFocus = FocusNode();

/// The Songs filter (Search's "Show all songs" sets it too), kept across navigation.
final songsFilter = ValueNotifier('');

/// Every song in a sortable table. Click a column title to sort; again to reverse.
class SongsPage extends StatefulWidget {
  const SongsPage({super.key});
  @override
  State<SongsPage> createState() => _SongsPageState();
}

class _SongsPageState extends State<SongsPage> {
  late final _filter = TextEditingController(text: songsFilter.value);

  @override
  void dispose() {
    _filter.dispose();
    super.dispose();
  }

  void _setFilter(String v) => songsFilter.value = v;

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
    listenable: Listenable.merge([lib, songsFilter]),
    builder: (context, _) {
      final m = songsFilter.value;
      if (m != _filter.text) _filter.text = m; // set by Search while this page was open
      final q = m.trim().toLowerCase();
      final tracks = [
        for (final t in lib.tracks)
          if (q.isEmpty || songMatches(t, q)) t,
      ]..sort(_cmp);
      if (_desc) {
        final r = tracks.reversed.toList();
        tracks
          ..clear()
          ..addAll(r);
      }
      selection.primary = tracks;
      final length = fmtLong(Duration(milliseconds: tracks.fold(0, (s, t) => s + t.durationMs)));
      return CustomScrollView(
        key: const PageStorageKey('songs'),
        slivers: [
          SliverToBoxAdapter(
            child: PageHeader(
              'Songs',
              subtitle: q.isEmpty
                  ? '${plural(tracks.length, 'song')} · $length'
                  : '${fmtInt(tracks.length)} of ${plural(lib.tracks.length, 'song')} · $length',
              trailing: lib.tracks.isEmpty
                  ? null
                  : Wrap(
                      spacing: S.x3,
                      runSpacing: S.x2,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        SizedBox(
                          width: 240,
                          child: TextField(
                            controller: _filter,
                            focusNode: songsFilterFocus,
                            onChanged: _setFilter,
                            style: T.body,
                            decoration: InputDecoration(
                              isDense: true,
                              hintText: isTouch ? 'Filter songs' : 'Filter songs  (Ctrl+F)',
                              prefixIcon: Icon(LucideIcons.listFilter, size: 16, color: C.faint),
                              suffixIcon: q.isEmpty
                                  ? null
                                  : IconBtn(
                                      LucideIcons.x,
                                      size: 14,
                                      box: 28,
                                      tooltip: 'Clear filter',
                                      onTap: () {
                                        _filter.clear();
                                        _setFilter('');
                                      },
                                    ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(R.pill),
                                borderSide: BorderSide(color: C.border),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(R.pill),
                                borderSide: BorderSide(color: C.border),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(R.pill),
                                borderSide: BorderSide(color: C.accent),
                              ),
                            ),
                          ),
                        ),
                        PillButton(
                          'Play all',
                          icon: LucideIcons.play,
                          primary: true,
                          onTap: tracks.isEmpty ? null : () => engine.playTracks(tracks),
                        ),
                      ],
                    ),
            ),
          ),
          if (lib.tracks.isEmpty)
            const SliverFillRemaining(hasScrollBody: false, child: NoMusic())
          else if (tracks.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: EmptyState(
                icon: LucideIcons.listFilter,
                title: 'No songs match “${_filter.text.trim()}”',
                body: 'The filter looks at titles, artists and albums.',
                action: PillButton(
                  'Clear filter',
                  onTap: () {
                    _filter.clear();
                    _setFilter('');
                  },
                ),
              ),
            )
          else ...[
            SliverPersistentHeader(
              pinned: true,
              delegate: _HeaderDelegate(
                Container(
                  color: C.bg,
                  padding: const EdgeInsets.symmetric(horizontal: S.x2),
                  alignment: Alignment.centerLeft,
                  constraints: const BoxConstraints.tightFor(width: double.infinity),
                  // The same columns the rows show at this width (they drop out in a small window).
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: TrackRow.maxWidth - S.x2 * 2),
                    child: LayoutBuilder(
                      builder: (context, c) {
                        final cols = TrackCols(
                          c.maxWidth,
                          table: true,
                          album: true,
                          badge: true,
                          k: MediaQuery.textScalerOf(context).scale(1),
                        );
                        return Row(
                          children: [
                            const SizedBox(width: 40 + S.x3),
                            _head('Title', 'title', flex: 5),
                            if (cols.artist) ...[const SizedBox(width: S.x4), _head('Artist', 'artist', flex: 3)],
                            if (cols.album) ...[const SizedBox(width: S.x4), _head('Album', 'album', flex: 3)],
                            if (cols.year) ...[const SizedBox(width: S.x4), _head('Year', 'year', width: cols.yearW)],
                            if (cols.badge) ...[const SizedBox(width: S.x4), _head('Format', 'format', width: cols.badgeW)],
                            const SizedBox(width: 32),
                            _head('Time', 'time', width: cols.timeW, align: TextAlign.right),
                            const SizedBox(width: 32),
                          ],
                        );
                      },
                    ),
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
