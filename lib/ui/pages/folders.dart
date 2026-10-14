import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:path/path.dart' as p;

import '../../library/models.dart';
import '../app.dart';
import '../theme.dart';
import '../tracks.dart';
import '../widgets.dart';
import 'albums.dart';

/// Browse the library the way it sits on disk.
class FoldersPage extends StatefulWidget {
  const FoldersPage({super.key});
  @override
  State<FoldersPage> createState() => _FoldersPageState();
}

class _FoldersPageState extends State<FoldersPage> {
  /// The open folder (null = the library folders themselves); kept across navigation.
  String? get _dir => nav.memo['folders.dir'] as String?;
  set _dir(String? v) => nav.memo['folders.dir'] = v;

  /// Every song in [dir] and below it.
  List<Track> _under(String dir) => [
    for (final t in lib.tracks)
      if (t.folder == dir || p.isWithin(dir, t.folder)) t,
  ]..sort(compareAlbumOrder);

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: lib,
    builder: (context, _) {
      final roots = lib.folders;
      final dir = _dir;
      final subdirs = <String, int>{}; // child folder -> songs inside
      final here = <Track>[];
      for (final t in lib.tracks) {
        if (dir == null) {
          final root = roots.where((r) => p.isWithin(r, t.path)).firstOrNull;
          if (root != null) subdirs[root] = (subdirs[root] ?? 0) + 1;
        } else if (t.folder == dir) {
          here.add(t);
        } else if (p.isWithin(dir, t.folder)) {
          final child = p.join(dir, p.split(p.relative(t.folder, from: dir)).first);
          subdirs[child] = (subdirs[child] ?? 0) + 1;
        }
      }
      here.sort(compareAlbumOrder);
      final names = subdirs.keys.toList()..sort((a, b) => p.basename(a).toLowerCase().compareTo(p.basename(b).toLowerCase()));
      final crumbs = <String>[];
      if (dir != null) {
        final root = roots.where((r) => r == dir || p.isWithin(r, dir)).firstOrNull ?? dir;
        crumbs.add(root);
        for (final part in p.split(p.relative(dir, from: root))) {
          if (part != '.') crumbs.add(p.join(crumbs.last, part));
        }
      }
      return CustomScrollView(
        key: PageStorageKey('folders/$dir'),
        slivers: [
          SliverToBoxAdapter(
            child: PageHeader(
              'Folders',
              subtitle: dir ?? 'Your library folders',
              trailing: dir == null
                  ? null
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (here.isNotEmpty)
                          PillButton('Play folder', icon: LucideIcons.play, primary: true, onTap: () => engine.playTracks(here)),
                        const SizedBox(width: S.x2),
                        // Everything in this folder and below: play, shuffle, queue, add to a playlist.
                        Builder(
                          builder: (b) => IconBtn(
                            LucideIcons.ellipsis,
                            color: C.text,
                            tooltip: 'More',
                            onTap: () => showCollectionMenu(b, below(b), _under(dir)),
                          ),
                        ),
                      ],
                    ),
            ),
          ),
          if (dir != null)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(0, 0, 0, S.x3),
                child: Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _crumb('Library', null),
                    for (final c in crumbs) ...[
                      Icon(LucideIcons.chevronRight, size: 14, color: C.faint),
                      _crumb(c == crumbs.first ? c : p.basename(c), c),
                    ],
                  ],
                ),
              ),
            ),
          if (roots.isEmpty || (names.isEmpty && here.isEmpty))
            SliverFillRemaining(
              hasScrollBody: false,
              child: roots.isEmpty
                  ? const NoMusic()
                  : const EmptyState(icon: LucideIcons.folder, title: 'Empty folder', body: 'No songs in here.'),
            ),
          SliverList.builder(
            itemCount: names.length,
            itemBuilder: (_, i) => Clickable(
              onTap: () => setState(() => _dir = names[i]),
              onSecondaryTapDown: (d) => showCollectionMenu(context, d.globalPosition, _under(names[i])),
              semanticLabel: 'Folder ${p.basename(names[i])}',
              radius: R.small,
              padding: const EdgeInsets.symmetric(horizontal: S.x2),
              child: SizedBox(
                height: 52,
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(color: C.raised2, borderRadius: BorderRadius.circular(R.tiny + 2)),
                      child: Icon(LucideIcons.folder, size: 18, color: C.dim),
                    ),
                    const SizedBox(width: S.x3),
                    Expanded(
                      child: Text(
                        dir == null ? names[i] : p.basename(names[i]),
                        style: T.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(plural(subdirs[names[i]]!, 'song'), style: T.small),
                    const SizedBox(width: S.x2),
                    Icon(LucideIcons.chevronRight, size: 16, color: C.faint),
                  ],
                ),
              ),
            ),
          ),
          if (here.isNotEmpty) ...[
            if (names.isNotEmpty) const SliverToBoxAdapter(child: SectionTitle('Songs in this folder')),
            SliverTracks(here, primary: true),
          ],
          const SliverToBoxAdapter(child: SizedBox(height: S.x16)),
        ],
      );
    },
  );

  Widget _crumb(String label, String? target) => target == _dir
      ? Padding(
          padding: const EdgeInsets.symmetric(horizontal: S.x2, vertical: S.x1),
          child: Text(label, style: T.small.copyWith(color: C.text)),
        )
      : Clickable(
          onTap: () => setState(() => _dir = target),
          radius: R.tiny + 2,
          padding: const EdgeInsets.symmetric(horizontal: S.x2, vertical: S.x1),
          child: Text(label, style: T.small),
        );
}
