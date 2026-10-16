import 'dart:io';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../library/models.dart';
import '../app.dart';
import '../theme.dart';
import '../tracks.dart';
import '../widgets.dart';
import 'albums.dart';

// The Browse group: Genres, Years, Composers, Duplicates and Statistics share one
// rail entry and a tab strip, so the rail stays calm.

const browseTabs = [
  ('genres', 'Genres'),
  ('years', 'Years'),
  ('composers', 'Composers'),
  ('duplicates', 'Duplicates'),
  ('stats', 'Statistics'),
];

/// The Browse tab the rail opens: the last one used.
String get browseTab => nav.memo['browse.tab'] as String? ?? 'genres';

/// A row of pill choices; the chosen one is raised.
class Segmented<V> extends StatelessWidget {
  const Segmented({super.key, required this.value, required this.options, required this.onChanged});
  final V value;
  final List<(V, String)> options;
  final ValueChanged<V> onChanged;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(S.x1),
    decoration: BoxDecoration(
      color: C.raised2,
      borderRadius: BorderRadius.circular(R.pill),
      border: Border.all(color: C.border),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final (v, label) in options)
          Clickable(
            onTap: () => onChanged(v),
            selected: v == value,
            selectedColor: C.raised3,
            hover: C.raised3,
            radius: R.pill,
            semanticLabel: label,
            padding: const EdgeInsets.symmetric(horizontal: S.x3 + 2, vertical: S.x1 + 2),
            child: Text(label, style: T.label.copyWith(color: v == value ? C.text : C.dim)),
          ),
      ],
    ),
  );
}

/// The tab strip of a Browse page (it names the page), with the subtitle under it.
class BrowseHeader extends StatelessWidget {
  const BrowseHeader(this.tab, {super.key, this.subtitle, this.trailing});
  final String tab;
  final String? subtitle;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) {
    final sub = shownSubtitle(subtitle);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(S.x2, S.x2, S.x2, S.x3),
          child: Segmented(
            value: tab,
            options: browseTabs,
            onChanged: (t) {
              nav.memo['browse.tab'] = t;
              nav.go(t);
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(S.x2, 0, S.x2, S.x5),
          child: SizedBox(
            width: double.infinity,
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: S.x4,
              runSpacing: S.x3,
              children: [if (sub != null) Text(sub, style: T.small), ?trailing],
            ),
          ),
        ),
      ],
    );
  }
}

/// Up to four album covers in a square, else the first cover, else a gradient.
class CoverMosaic extends StatelessWidget {
  const CoverMosaic(this.tracks, {super.key, required this.seed, this.radius = R.cover});
  final List<Track> tracks;
  final String seed;
  final double radius;
  @override
  Widget build(BuildContext context) {
    final firsts = <String, Track>{};
    for (final t in tracks) {
      firsts.putIfAbsent(t.albumKey, () => t);
      if (firsts.length == 4) break;
    }
    if (firsts.length < 4) {
      return firsts.isEmpty ? CoverArt(null, radius: radius, seed: seed) : CoverArt.track(firsts.values.first, radius: radius);
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: AspectRatio(
        aspectRatio: 1,
        child: GridView.count(
          crossAxisCount: 2,
          physics: const NeverScrollableScrollPhysics(),
          children: [for (final t in firsts.values) CoverArt.track(t, radius: 0)],
        ),
      ),
    );
  }
}

/// A card with a cover, a name and a count line (genres, composers, smart playlists).
class NamedCard extends StatelessWidget {
  const NamedCard({
    super.key,
    required this.cover,
    required this.name,
    required this.meta,
    required this.onTap,
    required this.tracks,
    this.label,
  });
  final Widget cover;
  final String name, meta;
  final String? label;
  final VoidCallback onTap;
  final List<Track> tracks;

  static double extra(BuildContext context) => S.x3 + textHeight(context, [T.label, T.small]) + 2;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(R.card),
      border: Border.all(color: C.border),
    ),
    child: Clickable(
      onTap: onTap,
      onSecondaryTapDown: (d) => showCollectionMenu(context, d.globalPosition, tracks),
      semanticLabel: '${label ?? ''} $name'.trim(),
      radius: R.card,
      padding: const EdgeInsets.all(S.x2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          cover,
          const SizedBox(height: S.x3),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: S.x1),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: T.label),
                Text(meta, maxLines: 1, overflow: TextOverflow.ellipsis, style: T.small),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

String _albumsSongs(List<Track> tracks) {
  final albums = {for (final t in tracks) t.albumKey}.length;
  return '${plural(albums, 'album')} · ${plural(tracks.length, 'song')}';
}

Duration _length(List<Track> tracks) => Duration(milliseconds: tracks.fold(0, (s, t) => s + t.durationMs));

Widget _notFound(IconData icon, String what) => EmptyState(
  icon: icon,
  title: '$what not found',
  body: 'It may have left your library.',
  action: PillButton('Back', onTap: nav.back),
);

const _bottom = SliverToBoxAdapter(child: SizedBox(height: S.x16));

// ------------------------------------------------------------ genres

class GenresPage extends StatelessWidget {
  const GenresPage({super.key});
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: lib,
    builder: (context, _) {
      final genres = lib.genres.entries.toList();
      return CustomScrollView(
        key: const PageStorageKey('genres'),
        slivers: [
          SliverToBoxAdapter(child: BrowseHeader('genres', subtitle: plural(genres.length, 'genre'))),
          if (genres.isEmpty)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: EmptyState(
                icon: LucideIcons.tags,
                title: 'No genres yet',
                body: 'Songs with a genre tag show up here, grouped by genre.',
              ),
            )
          else
            sliverCards(
              count: genres.length,
              extra: NamedCard.extra(context),
              builder: (_, i) {
                final MapEntry(key: g, value: tracks) = genres[i];
                return NamedCard(
                  cover: CoverMosaic(tracks, seed: g, radius: R.card - S.x2),
                  name: g,
                  meta: _albumsSongs(tracks),
                  label: 'Genre',
                  tracks: tracks,
                  onTap: () => nav.push('genre', g),
                );
              },
            ),
          _bottom,
        ],
      );
    },
  );
}

class GenrePage extends StatelessWidget {
  const GenrePage(this.genre, {super.key});
  final String genre;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: lib,
    builder: (context, _) {
      final tracks = lib.genres[genre];
      if (tracks == null) return _notFound(LucideIcons.tags, 'Genre');
      final albums = lib.genreAlbums(genre);
      return CustomScrollView(
        key: PageStorageKey('genre/$genre'),
        slivers: [
          SliverToBoxAdapter(
            child: PageHero(
              cover: CoverMosaic(tracks, seed: genre, radius: R.card),
              glow: lib.artFor(tracks.first.albumKey, tracks.first.cover),
              title: genre,
              label: 'Genre',
              meta: [plural(albums.length, 'album'), plural(tracks.length, 'song'), fmtLong(_length(tracks))],
              tracks: tracks,
            ),
          ),
          const SliverToBoxAdapter(child: SectionTitle('Albums')),
          sliverCards(count: albums.length, extra: AlbumCard.extra(context), builder: (_, i) => AlbumCard(albums[i])),
          const SliverToBoxAdapter(child: SectionTitle('Songs')),
          SliverTracks(tracks, primary: true),
          _bottom,
        ],
      );
    },
  );
}

// ------------------------------------------------------------ years

class YearsPage extends StatefulWidget {
  const YearsPage({super.key});
  @override
  State<YearsPage> createState() => _YearsPageState();
}

class _YearsPageState extends State<YearsPage> {
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: lib,
    builder: (context, _) {
      final years = lib.years;
      final decades = {for (final y in years.keys) y ~/ 10 * 10}.toList(); // newest first, like years
      final picked = nav.memo['years.decade'] as int?;
      final decade = decades.contains(picked) ? picked! : decades.firstOrNull;
      final shown = [
        for (final e in years.entries)
          if (e.key ~/ 10 * 10 == decade) e,
      ];
      final undated = lib.albums.length - years.values.fold<int>(0, (n, a) => n + a.length);
      return CustomScrollView(
        key: PageStorageKey('years/$decade'),
        slivers: [
          SliverToBoxAdapter(
            child: BrowseHeader(
              'years',
              subtitle: [plural(years.length, 'year'), if (undated > 0) '${plural(undated, 'album')} without a year not shown'].join(' · '),
            ),
          ),
          if (decades.isEmpty)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: EmptyState(
                icon: LucideIcons.calendar,
                title: 'No years yet',
                body: 'Albums with a year in their tags show up here, by decade.',
              ),
            )
          else ...[
            SliverToBoxAdapter(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: S.x2),
                child: Segmented(
                  value: decade,
                  options: [for (final d in decades) (d, "${d}s")],
                  onChanged: (d) => setState(() => nav.memo['years.decade'] = d),
                ),
              ),
            ),
            for (final MapEntry(key: y, value: albums) in shown) ...[
              SliverToBoxAdapter(
                child: SectionTitle(
                  '$y',
                  subtitle: plural(albums.length, 'album'),
                  trailing: Builder(
                    builder: (b) => IconBtn(
                      LucideIcons.ellipsis,
                      tooltip: 'More',
                      onTap: () => showCollectionMenu(b, below(b), [for (final a in albums) ...a.tracks]),
                    ),
                  ),
                ),
              ),
              sliverCards(count: albums.length, extra: AlbumCard.extra(context), builder: (_, i) => AlbumCard(albums[i])),
            ],
          ],
          _bottom,
        ],
      );
    },
  );
}

// ------------------------------------------------------------ composers

class ComposersPage extends StatelessWidget {
  const ComposersPage({super.key});
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: lib,
    builder: (context, _) {
      final composers = lib.composers.entries.toList();
      return CustomScrollView(
        key: const PageStorageKey('composers'),
        slivers: [
          SliverToBoxAdapter(child: BrowseHeader('composers', subtitle: plural(composers.length, 'composer'))),
          if (composers.isEmpty)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: EmptyState(
                icon: LucideIcons.feather,
                title: 'No composers yet',
                body: 'Songs with a composer tag show up here, with their works and movements in order.',
              ),
            )
          else
            sliverCards(
              maxWidth: 200,
              count: composers.length,
              extra: NamedCard.extra(context),
              builder: (_, i) {
                final MapEntry(key: name, value: tracks) = composers[i];
                final works = {for (final t in tracks) t.work ?? t.album}.length;
                return NamedCard(
                  cover: CoverArt(tracks.map((t) => t.cover).whereType<String>().firstOrNull, round: true, seed: name),
                  name: name,
                  meta: '${plural(works, 'work')} · ${plural(tracks.length, 'piece')}',
                  label: 'Composer',
                  tracks: tracks,
                  onTap: () => nav.push('composer', name),
                );
              },
            ),
          _bottom,
        ],
      );
    },
  );
}

class ComposerPage extends StatelessWidget {
  const ComposerPage(this.composer, {super.key});
  final String composer;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: lib,
    builder: (context, _) {
      final works = lib.works(composer);
      if (works.isEmpty) return _notFound(LucideIcons.feather, 'Composer');
      final all = [for (final w in works.values) ...w];
      selection.primary = all;
      return CustomScrollView(
        key: PageStorageKey('composer/$composer'),
        slivers: [
          SliverToBoxAdapter(
            child: PageHero(
              cover: CoverArt(all.map((t) => t.cover).whereType<String>().firstOrNull, round: true, seed: composer),
              glow: resolveArt(all.map((t) => t.cover).whereType<String>().firstOrNull, seed: composer),
              title: composer,
              label: 'Composer',
              round: true,
              meta: [plural(works.length, 'work'), plural(all.length, 'piece'), fmtLong(_length(all))],
              tracks: all,
            ),
          ),
          for (final MapEntry(key: work, value: movements) in works.entries) ...[
            SliverToBoxAdapter(child: _WorkHeader(work, movements)),
            SliverFixedExtentList(
              itemExtent: TrackRow.extentOf(context),
              delegate: SliverChildBuilderDelegate(
                (_, i) => TrackRow(
                  track: movements[i],
                  list: movements, // a movement plays on through the rest of its work
                  index: i,
                  number: movements[i].movementNo ?? i + 1,
                  title: movementOf(movements[i], work),
                  showCover: false,
                  showAlbum: false,
                  albumArtist: movements[i].artist,
                ),
                childCount: movements.length,
              ),
            ),
          ],
          _bottom,
        ],
      );
    },
  );
}

/// Under a work's header only the movement: its MOVEMENT tag, else the title without the work's name
/// ("Symphony No. 5: I. Allegro" -> "I. Allegro").
String movementOf(Track t, String work) {
  if (t.movement case final m? when m.isNotEmpty) return m;
  if (!t.title.toLowerCase().startsWith(work.toLowerCase())) return t.title;
  final rest = t.title.substring(work.length).replaceFirst(RegExp('^[ :,.;/–—-]+'), '');
  return rest.isEmpty ? t.title : rest;
}

/// A work's title, its length and performers, and Play work (all movements, in order).
class _WorkHeader extends StatelessWidget {
  const _WorkHeader(this.work, this.movements);
  final String work;
  final List<Track> movements;
  @override
  Widget build(BuildContext context) {
    final performers = {for (final t in movements) t.artist}.join(', ');
    return GestureDetector(
      onSecondaryTapDown: (d) => showCollectionMenu(context, d.globalPosition, movements),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(S.x2, S.x6, S.x2, S.x2),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(work, style: T.heading, maxLines: 2, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: S.x1 / 2),
                  Text(
                    '${plural(movements.length, 'movement')} · ${fmtLong(_length(movements))} · $performers',
                    style: T.caption,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: S.x3),
            PillButton('Play work', icon: LucideIcons.play, dense: true, onTap: () => engine.playTracks(movements)),
            Builder(
              builder: (b) => IconBtn(LucideIcons.ellipsis, tooltip: 'More', onTap: () => showCollectionMenu(b, below(b), movements)),
            ),
          ],
        ),
      ),
    );
  }
}

// ------------------------------------------------------------ duplicates

String _copies(int n) => n == 1 ? '1 copy' : '${fmtInt(n)} copies';

/// Opens Explorer with the file selected. Nothing is changed.
Future<void> showInExplorer(String path) => Process.start('explorer.exe', ['/select,', path]);

class DuplicatesPage extends StatelessWidget {
  const DuplicatesPage({super.key});
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: lib,
    builder: (context, _) {
      final groups = lib.duplicates();
      final hidden = lib.hiddenIds;
      selection.primary = [for (final g in groups) ...g];
      return CustomScrollView(
        key: const PageStorageKey('duplicates'),
        slivers: [
          SliverToBoxAdapter(
            child: BrowseHeader(
              'duplicates',
              subtitle: groups.isEmpty
                  ? 'Same title and artist, nearly the same length'
                  : '${plural(groups.length, 'song')} found more than once · ${_copies(selection.primary.length)}',
              trailing: hidden.isEmpty
                  ? null
                  : PillButton(
                      'Show ${plural(hidden.length, 'hidden song')} again',
                      icon: LucideIcons.eye,
                      onTap: () async {
                        if (await confirm(
                          context,
                          'Show hidden songs again?',
                          '${plural(hidden.length, 'song')} you hid come back to your library.',
                          action: 'Show',
                        )) {
                          lib.setHidden(hidden, false);
                        }
                      },
                    ),
            ),
          ),
          if (groups.isEmpty)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: EmptyState(
                icon: LucideIcons.copy,
                title: 'No duplicates found',
                body: 'Songs with the same title and artist and nearly the same length show up here, so you can compare and hide the extra copies.',
              ),
            )
          else
            for (final g in groups) ...[
              SliverToBoxAdapter(child: SectionTitle(g.first.title, subtitle: '${g.first.artist} · ${_copies(g.length)}')),
              SliverFixedExtentList(
                itemExtent: TrackRow.extentOf(context),
                delegate: SliverChildBuilderDelegate((_, i) => _copy(context, g, i), childCount: g.length),
              ),
            ],
          _bottom,
        ],
      );
    },
  );

  Widget _copy(BuildContext context, List<Track> g, int i) {
    final t = g[i];
    int quality(Track x) => x.bitDepth * x.sampleRate * 10000 + x.bitrate;
    final best = g.reduce((a, b) => quality(b) > quality(a) ? b : a);
    return TrackRow(
      track: t,
      list: g,
      index: i,
      showBadge: true,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 72,
            child: t == best ? Text('Best copy', textAlign: TextAlign.center, style: T.caption.copyWith(color: C.text)) : null,
          ),
          IconBtn(LucideIcons.play, size: 14, box: 32, tooltip: 'Play this copy', onTap: () => engine.playTracks([t])),
          Tooltip(
            message: 'Hide from library (the file stays)',
            child: PillButton(
              'Hide',
              dense: true,
              onTap: () {
              lib.setHidden([t.id], true);
              toast(
                context,
                'Hid “${t.title}” from your library. The file is not touched.',
                actions: [
                  ('Undo', () => lib.setHidden([t.id], false)),
                ],
              );
            },
            ),
          ),
          IconBtn(LucideIcons.folderOpen, size: 14, box: 32, tooltip: 'Show in Explorer\n${t.path}', onTap: () => showInExplorer(t.path)),
        ],
      ),
    );
  }
}
