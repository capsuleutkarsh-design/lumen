import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../library/models.dart';
import '../../library/smart.dart';
import '../app.dart';
import '../theme.dart';
import '../tracks.dart';
import '../widgets.dart';
import 'albums.dart';
import 'browse.dart';

/// A smart playlist's cover: its songs' covers with a sparkle badge, so it never looks like a plain playlist.
class SmartCover extends StatelessWidget {
  const SmartCover(this.s, this.tracks, {super.key, this.radius = R.cover});
  final SmartPlaylist s;
  final List<Track> tracks;
  final double radius;
  @override
  Widget build(BuildContext context) => Stack(
    children: [
      CoverMosaic(tracks, seed: s.name, radius: radius),
      Positioned(
        left: S.x2,
        top: S.x2,
        child: Container(
          padding: const EdgeInsets.all(S.x1 + 2),
          decoration: BoxDecoration(
            color: C.glass,
            shape: BoxShape.circle,
            border: Border.all(color: C.glassBorder),
          ),
          child: Icon(LucideIcons.sparkles, size: 14, color: C.text, semanticLabel: 'Smart playlist'),
        ),
      ),
    ],
  );
}

/// The smart playlists, as cards above the ordinary ones on the Playlists page.
List<Widget> smartPlaylistSlivers(BuildContext context) {
  final all = lib.smartPlaylists;
  return [
    SliverToBoxAdapter(
      child: SectionTitle(
        'Smart playlists',
        subtitle: 'Fill themselves from rules and stay up to date',
        trailing: PillButton('New smart playlist', icon: LucideIcons.sparkles, dense: true, onTap: () => editSmart(context)),
      ),
    ),
    sliverCards(
      extra: NamedCard.extra(context),
      count: all.length,
      builder: (_, i) {
        final s = all[i];
        final tracks = lib.smartTracks(s);
        return NamedCard(
          cover: SmartCover(s, tracks, radius: R.card - S.x2),
          name: s.name,
          meta: 'Smart · ${plural(tracks.length, 'song')}',
          label: 'Smart playlist',
          tracks: tracks,
          onTap: () => nav.push('smart', s.id),
        );
      },
    ),
    const SliverToBoxAdapter(child: SectionTitle('Playlists')),
  ];
}

class SmartPlaylistPage extends StatelessWidget {
  const SmartPlaylistPage(this.id, {super.key});
  final int id;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    // Plays change "Most played" and "Never played" while the page is open.
    listenable: Listenable.merge([lib, lib.plays]),
    builder: (context, _) {
      final s = lib.smartPlaylist(id);
      if (s == null) {
        return EmptyState(
          icon: LucideIcons.sparkles,
          title: 'Smart playlist not found',
          body: 'It may have been deleted.',
          action: PillButton('Back', onTap: nav.back),
        );
      }
      final tracks = lib.smartTracks(s);
      final first = tracks.firstOrNull;
      return CustomScrollView(
        key: PageStorageKey('smart/$id'),
        slivers: [
          SliverToBoxAdapter(
            child: PageHero(
              cover: SmartCover(s, tracks, radius: R.card),
              glow: first == null ? resolveArt(null, seed: s.name) : lib.artFor(first.albumKey, first.cover),
              title: s.name,
              label: 'Smart playlist',
              meta: [
                plural(tracks.length, 'song'),
                fmtLong(Duration(milliseconds: tracks.fold(0, (n, t) => n + t.durationMs))),
              ],
              tracks: tracks,
              menu: [
                ('edit', LucideIcons.slidersHorizontal, 'Edit rules…', () => editSmart(context, s)),
                (
                  'delete',
                  LucideIcons.trash2,
                  'Delete…',
                  () async {
                    if (await confirm(context, 'Delete “${s.name}”?', 'Only the rules are removed; every song stays in your library.')) {
                      lib.deleteSmart(s.id);
                      nav.back();
                    }
                  },
                ),
              ],
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(S.x2, S.x4, S.x2, S.x2),
              child: Wrap(
                spacing: S.x2,
                runSpacing: S.x2,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(s.rules.length > 1 ? (s.any ? 'Any of' : 'All of') : 'Rule', style: T.caption),
                  for (final r in s.rules) _Chip(r.describe()),
                  Text(
                    'Sorted by ${SmartPlaylist.sorts[s.sort]?.toLowerCase() ?? s.sort}${s.limit > 0 ? ', up to ${s.limit}' : ''}',
                    style: T.caption,
                  ),
                  IconBtn(LucideIcons.slidersHorizontal, size: 14, box: 28, tooltip: 'Edit rules', onTap: () => editSmart(context, s)),
                ],
              ),
            ),
          ),
          if (tracks.isEmpty)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: EmptyState(
                icon: LucideIcons.sparkles,
                title: 'No songs match yet',
                body: 'Songs appear here by themselves as soon as they match the rules.',
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

class _Chip extends StatelessWidget {
  const _Chip(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: S.x3, vertical: S.x1),
    decoration: BoxDecoration(
      color: C.raised2,
      borderRadius: BorderRadius.circular(R.pill),
      border: Border.all(color: C.borderStrong),
    ),
    child: Text(text, style: T.caption.copyWith(color: C.text)),
  );
}

// ------------------------------------------------------------ the rules editor

/// One rule while it is being edited.
class _Edit {
  _Edit(this.f, [Object? a, Object? b])
    : a = TextEditingController(text: a?.toString() ?? ''),
      b = TextEditingController(text: b?.toString() ?? '');
  String f;
  final TextEditingController a, b;

  SmartRule? get rule {
    if (SmartRule.noValue.contains(f)) return SmartRule(f);
    if (SmartRule.text.contains(f)) return a.text.trim().isEmpty ? null : SmartRule(f, a.text.trim());
    final x = int.tryParse(a.text.trim());
    if (x == null) return null;
    return SmartRule.range.contains(f) ? SmartRule(f, x, int.tryParse(b.text.trim()) ?? x) : SmartRule(f, x);
  }
}

/// New (no [s]) or edit: name, match all / any, the rules, sort and limit, with a live count.
Future<void> editSmart(BuildContext context, [SmartPlaylist? s]) async {
  final name = TextEditingController(text: s?.name ?? '');
  final rules = [for (final r in s?.rules ?? const <SmartRule>[]) _Edit(r.f, r.a, r.b)];
  if (rules.isEmpty) rules.add(_Edit('genre'));
  var any = s?.any ?? false;
  var sort = s?.sort ?? 'added';
  final limit = TextEditingController(text: (s?.limit ?? 0) == 0 ? '' : '${s!.limit}');

  SmartPlaylist build() => SmartPlaylist(
    s?.id ?? 0,
    name.text.trim().isEmpty ? 'Smart playlist' : name.text.trim(),
    rules: [for (final e in rules) ?e.rule],
    any: any,
    sort: sort,
    limit: int.tryParse(limit.text.trim()) ?? 0,
  );

  final saved = await showDialog<SmartPlaylist>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, set) {
        final draft = build();
        final count = lib.smartTracks(draft).length;
        return AlertDialog(
          title: Text(s == null ? 'New smart playlist' : 'Edit smart playlist'),
          content: SizedBox(
            width: 560,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: name,
                    autofocus: s == null,
                    style: T.body,
                    decoration: const InputDecoration(hintText: 'Name'),
                  ),
                  const SizedBox(height: S.x4),
                  Row(
                    children: [
                      Text('Songs that match', style: T.label),
                      const SizedBox(width: S.x3),
                      Segmented(
                        value: any,
                        options: const [(false, 'all rules'), (true, 'any rule')],
                        onChanged: (v) => set(() => any = v),
                      ),
                    ],
                  ),
                  const SizedBox(height: S.x3),
                  for (final (i, e) in rules.indexed)
                    Padding(
                      padding: const EdgeInsets.only(bottom: S.x2),
                      child: Row(
                        children: [
                          Expanded(
                            flex: 5,
                            child: _Drop(
                              value: e.f,
                              items: SmartRule.fields,
                              onChanged: (v) => set(() {
                                e.f = v;
                                e.a.clear();
                                e.b.clear();
                              }),
                            ),
                          ),
                          const SizedBox(width: S.x2),
                          Expanded(flex: 5, child: _values(e, () => set(() {}))),
                          IconBtn(
                            LucideIcons.x,
                            size: 14,
                            box: 32,
                            tooltip: 'Remove rule',
                            onTap: rules.length == 1 ? null : () => set(() => rules.removeAt(i)),
                          ),
                        ],
                      ),
                    ),
                  PillButton('Add rule', icon: LucideIcons.plus, dense: true, onTap: () => set(() => rules.add(_Edit('genre')))),
                  const SizedBox(height: S.x4),
                  Row(
                    children: [
                      SizedBox(width: 72, child: Text('Sort by', style: T.label)),
                      Expanded(
                        child: _Drop(value: sort, items: SmartPlaylist.sorts, onChanged: (v) => set(() => sort = v)),
                      ),
                      const SizedBox(width: S.x3),
                      Text('Up to', style: T.label),
                      const SizedBox(width: S.x2),
                      SizedBox(width: 96, child: _number(limit, 'all', () => set(() {}))),
                      const SizedBox(width: S.x2),
                      Text('songs', style: T.label),
                    ],
                  ),
                  const SizedBox(height: S.x4),
                  Text(draft.rules.isEmpty ? 'Add a rule to start.' : 'Matches ${plural(count, 'song')} right now.', style: T.small),
                ],
              ),
            ),
          ),
          actions: [
            PillButton('Cancel', onTap: () => Navigator.pop(ctx)),
            PillButton(s == null ? 'Create' : 'Save', primary: true, onTap: draft.rules.isEmpty ? null : () => Navigator.pop(ctx, draft)),
          ],
        );
      },
    ),
  );
  if (saved == null) return;
  final id = lib.saveSmart(saved);
  if (s == null) nav.push('smart', id);
}

Widget _values(_Edit e, VoidCallback changed) {
  if (SmartRule.noValue.contains(e.f)) return const SizedBox.shrink();
  if (SmartRule.text.contains(e.f)) {
    final hint = switch (e.f) {
      'genre' => lib.genres.keys.firstOrNull ?? 'Jazz',
      'format' => 'FLAC',
      _ => 'Name',
    };
    return TextField(
      controller: e.a,
      style: T.body,
      onChanged: (_) => changed(),
      decoration: InputDecoration(hintText: hint, isDense: true),
    );
  }
  if (SmartRule.range.contains(e.f)) {
    return Row(
      children: [
        Expanded(child: _number(e.a, '1990', changed)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: S.x2),
          child: Text('and', style: T.small),
        ),
        Expanded(child: _number(e.b, '1999', changed)),
      ],
    );
  }
  return _number(e.a, switch (e.f) {
    'added' => '30',
    'rate' => '96000',
    'bits' => '24',
    _ => '5',
  }, changed);
}

Widget _number(TextEditingController c, String hint, VoidCallback changed) => TextField(
  controller: c,
  style: T.body,
  keyboardType: TextInputType.number,
  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
  onChanged: (_) => changed(),
  decoration: InputDecoration(hintText: hint, isDense: true),
);

class _Drop extends StatelessWidget {
  const _Drop({required this.value, required this.items, required this.onChanged});
  final String value;
  final Map<String, String> items;
  final ValueChanged<String> onChanged;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: S.x3),
    decoration: BoxDecoration(
      color: C.raised2,
      borderRadius: BorderRadius.circular(R.small),
      border: Border.all(color: C.border),
    ),
    child: DropdownButtonHideUnderline(
      child: DropdownButton<String>(
        value: value,
        isExpanded: true,
        dropdownColor: C.raised2,
        borderRadius: BorderRadius.circular(R.small),
        style: T.label,
        icon: Icon(LucideIcons.chevronDown, size: 16, color: C.dim),
        items: [
          for (final MapEntry(:key, value: label) in items.entries)
            DropdownMenuItem(
              value: key,
              child: Text(label, overflow: TextOverflow.ellipsis),
            ),
        ],
        onChanged: (v) => v == null ? null : onChanged(v),
      ),
    ),
  );
}
