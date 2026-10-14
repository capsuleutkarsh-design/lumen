import 'dart:math';

import 'package:flutter/material.dart';

import '../../library/stats.dart';
import '../app.dart';
import '../theme.dart';
import '../tracks.dart';
import '../widgets.dart';
import 'albums.dart';
import 'browse.dart';

const _periods = [('7d', '7 days'), ('30d', '30 days'), ('12m', '12 months'), ('all', 'All time')];
const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const _days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

/// What you listened to, from Lumen's own play counts (nothing leaves the computer).
class StatsPage extends StatefulWidget {
  const StatsPage({super.key});
  @override
  State<StatsPage> createState() => _StatsPageState();
}

class _StatsPageState extends State<StatsPage> {
  String get _period => nav.memo['stats.period'] as String? ?? '30d';

  (DateTime, Bucket) _range(DateTime today) {
    switch (_period) {
      case '7d':
        return (today.subtract(const Duration(days: 6)), Bucket.day);
      case '30d':
        return (today.subtract(const Duration(days: 29)), Bucket.day);
      case '12m':
        return (bucketStart(DateTime(today.year - 1, today.month, today.day + 7), Bucket.week), Bucket.week);
      default:
        final first = lib.firstPlay ?? today;
        final long = today.difference(first).inDays > 366;
        return (bucketStart(first, long ? Bucket.month : Bucket.week), long ? Bucket.month : Bucket.week);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([lib, lib.plays]),
    builder: (context, _) {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final (from, bucket) = _range(today);
      final s = listenStats(lib.playsSince(from), lib.byId, from, DateTime(today.year, today.month, today.day + 1), bucket);
      return ListView(
        key: const PageStorageKey('stats'),
        padding: EdgeInsets.zero,
        children: [
          BrowseHeader(
            'stats',
            subtitle: '${fmtLong(s.total)} listened · ${plural(s.plays, 'play')}',
            trailing: Segmented(value: _period, options: _periods, onChanged: (v) => setState(() => nav.memo['stats.period'] = v)),
          ),
          _Card(
            'Listening time',
            subtitle: 'Each play counted in full: a song played past its play count point. Skips are left out.',
            child: _Bars(s.buckets, bucket),
          ),
          LayoutBuilder(
            builder: (context, c) {
              final cards = [
                _top('Top songs', [
                  for (final (id, n) in s.songs)
                    if (lib.byId[id] case final t?)
                      _Line(t.title, t.artist, n, () => nav.push('album', t.albumKey), (at) => showTrackMenu(context, at, [t])),
                ]),
                _top('Top albums', [
                  for (final (key, n) in s.albums)
                    if (lib.albumByKey[key] case final a?)
                      _Line(a.title, a.artist, n, () => nav.push('album', a.key), (at) => albumMenu(context, at, a)),
                ]),
                _top('Top artists', [for (final (name, n) in s.artists) _Line(name, null, n, () => nav.push('artist', name), null)]),
              ];
              if (c.maxWidth < 860) return Column(children: cards);
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var i = 0; i < cards.length; i++) ...[if (i > 0) const SizedBox(width: S.x4), Expanded(child: cards[i])],
                ],
              );
            },
          ),
          _library(),
          const SizedBox(height: S.x16),
        ],
      );
    },
  );

  Widget _top(String title, List<_Line> lines) => _Card(
    title,
    child: lines.isEmpty
        ? Text('Nothing played in this period yet.', style: T.small)
        : Column(children: [for (var i = 0; i < lines.length; i++) lines[i].build(i + 1)]),
  );

  Widget _library() {
    final tracks = lib.tracks;
    final formats = formatCounts(tracks);
    final total = Duration(milliseconds: tracks.fold(0, (n, t) => n + t.durationMs));
    final most = formats.isEmpty ? 1 : formats.first.$2;
    return _Card(
      'Your library',
      subtitle: [plural(tracks.length, 'song'), plural(lib.albums.length, 'album'), fmtLong(total), fmtBytes(lib.librarySize)].join(' · '),
      child: Column(
        children: [
          for (final (codec, n) in formats)
            Padding(
              padding: const EdgeInsets.only(bottom: S.x2),
              child: Row(
                children: [
                  SizedBox(width: 72, child: Text(codec, style: T.label)),
                  Expanded(
                    child: SizedBox(height: 8, child: CustomPaint(painter: _Meter(n / most, C.dim, C.raised3))),
                  ),
                  SizedBox(
                    width: 96,
                    child: Text(
                      plural(n, 'song'),
                      textAlign: TextAlign.right,
                      style: T.small.copyWith(fontFeatures: T.tabular),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card(this.title, {this.subtitle, required this.child});
  final String title;
  final String? subtitle;
  final Widget child;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: S.x4),
    child: Panel(
      padding: const EdgeInsets.all(S.x5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: T.heading),
          if (subtitle != null) ...[const SizedBox(height: S.x1), Text(subtitle!, style: T.small)],
          const SizedBox(height: S.x4),
          child,
        ],
      ),
    ),
  );
}

/// One row of a top list: rank, name, by-line and plays.
class _Line {
  _Line(this.name, this.by, this.plays, this.onTap, this.menu);
  final String name;
  final String? by;
  final int plays;
  final VoidCallback onTap;
  final void Function(Offset)? menu;

  Widget build(int rank) => Clickable(
    onTap: onTap,
    onSecondaryTapDown: menu == null ? null : (d) => menu!(d.globalPosition),
    semanticLabel: '$rank. $name, ${plural(plays, 'play')}',
    padding: const EdgeInsets.symmetric(horizontal: S.x2, vertical: S.x2),
    child: Row(
      children: [
        SizedBox(
          width: 24,
          child: Text(
            '$rank',
            style: T.small.copyWith(color: C.faint, fontFeatures: T.tabular),
          ),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: T.label),
              if (by != null) Text(by!, maxLines: 1, overflow: TextOverflow.ellipsis, style: T.small),
            ],
          ),
        ),
        const SizedBox(width: S.x2),
        Text(plural(plays, 'play'), style: T.caption.copyWith(fontFeatures: T.tabular)),
      ],
    ),
  );
}

/// Listening time per day / week / month. Hover a bar for its date and time.
class _Bars extends StatefulWidget {
  const _Bars(this.buckets, this.bucket);
  final List<(DateTime, Duration)> buckets;
  final Bucket bucket;
  @override
  State<_Bars> createState() => _BarsState();
}

class _BarsState extends State<_Bars> {
  int? _hover;

  String _label(DateTime d) => switch (widget.bucket) {
    Bucket.day => '${_days[d.weekday - 1]} ${d.day} ${_months[d.month - 1]}',
    Bucket.week => 'Week of ${d.day} ${_months[d.month - 1]} ${d.year}',
    Bucket.month => '${_months[d.month - 1]} ${d.year}',
  };

  @override
  Widget build(BuildContext context) {
    final b = widget.buckets;
    if (b.isEmpty) return const SizedBox.shrink();
    final i = _hover;
    final caption = i == null
        ? 'Most in one ${widget.bucket.name}: ${fmtLong(b.map((x) => x.$2).reduce((x, y) => x > y ? x : y))}'
        : '${_label(b[i].$1)} · ${b[i].$2 == Duration.zero ? 'nothing' : fmtLong(b[i].$2)}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(caption, style: T.small.copyWith(color: i == null ? C.dim : C.text)),
        const SizedBox(height: S.x3),
        LayoutBuilder(
          builder: (context, c) => MouseRegion(
            onHover: (e) => setState(() => _hover = (e.localPosition.dx / c.maxWidth * b.length).floor().clamp(0, b.length - 1)),
            onExit: (_) => setState(() => _hover = null),
            child: Semantics(
              label: 'Listening time chart, ${b.length} bars',
              child: SizedBox(
                height: 140,
                width: c.maxWidth,
                child: CustomPaint(
                  painter: _BarPainter([for (final x in b) x.$2.inSeconds.toDouble()], _hover, C.dim, C.accent, C.raised3),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: S.x2),
        Row(
          children: [
            Text(_label(b.first.$1), style: T.caption),
            const Spacer(),
            Text(_label(b.last.$1), style: T.caption),
          ],
        ),
      ],
    );
  }
}

class _BarPainter extends CustomPainter {
  _BarPainter(this.values, this.hover, this.bar, this.active, this.empty);
  final List<double> values;
  final int? hover;
  final Color bar, active, empty;

  @override
  void paint(Canvas canvas, Size size) {
    final most = values.fold(0.0, max);
    final slot = size.width / values.length;
    final gap = min(S.x1, slot * 0.25);
    for (var i = 0; i < values.length; i++) {
      final h = most == 0 ? 0.0 : values[i] / most * size.height;
      final r = Rect.fromLTWH(i * slot + gap / 2, size.height - max(h, 2), slot - gap, max(h, 2));
      canvas.drawRRect(
        RRect.fromRectAndCorners(r, topLeft: const Radius.circular(R.tiny), topRight: const Radius.circular(R.tiny)),
        Paint()..color = values[i] == 0 ? empty : (i == hover ? active : bar),
      );
    }
  }

  @override
  bool shouldRepaint(_BarPainter old) =>
      old.hover != hover || old.bar != bar || old.active != active || old.empty != empty || !_same(old.values, values);
  static bool _same(List<double> a, List<double> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// A thin horizontal meter, [value] from 0 to 1.
class _Meter extends CustomPainter {
  _Meter(this.value, this.fill, this.track);
  final double value;
  final Color fill, track;
  @override
  void paint(Canvas canvas, Size size) {
    final r = Radius.circular(size.height / 2);
    canvas.drawRRect(RRect.fromRectAndRadius(Offset.zero & size, r), Paint()..color = track);
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(0, 0, max(size.height, size.width * value), size.height), r),
      Paint()..color = fill,
    );
  }

  @override
  bool shouldRepaint(_Meter old) => old.value != value || old.fill != fill || old.track != track;
}
