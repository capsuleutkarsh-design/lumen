import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:path/path.dart' as p;

import '../../library/models.dart';
import '../../platform/window.dart' show isTouch;
import '../app.dart';
import '../theme.dart';
import '../tracks.dart';
import '../widgets.dart';
import 'albums.dart';

/// Where a library folder is, in words: "Phone storage" or "SD card" on Android, else null.
String? storageName(String path) => !path.startsWith('/storage/')
    ? null
    : path.startsWith('/storage/emulated/')
    ? 'Phone storage'
    : 'SD card';

/// Browse the library the way it sits on disk. Each folder opened is a page of its own, so Back
/// (Esc, the mouse, Android's Back) goes up one level.
class FoldersPage extends StatelessWidget {
  const FoldersPage({super.key, this.dir});

  /// The open folder (null = the library folders themselves).
  final String? dir;

  /// Back to [target] (null: the library folders) along the folders opened on the way.
  void _up(String? target) {
    while (nav.top.page == 'folder' && nav.top.arg != target) {
      nav.back();
    }
  }

  /// Every song in [dir] and below it.
  List<Track> _under(String dir) => [
    for (final t in lib.tracks)
      if (t.folder == dir || p.isWithin(dir, t.folder)) t,
  ]..sort(compareAlbumOrder);

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: lib,
    builder: (context, _) {
      final roots = lib.folders, dir = this.dir;
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
                            onTap: () => showCollectionMenu(b, below(b), _under(dir), title: p.basename(dir)),
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
                      _crumb(c == crumbs.first && storageName(c) == null ? c : p.basename(c), c),
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
              onTap: () => nav.push('folder', names[i]),
              onSecondaryTapDown: (d) => showCollectionMenu(context, d.globalPosition, _under(names[i]), title: p.basename(names[i])),
              semanticLabel: 'Folder ${p.basename(names[i])}',
              radius: R.small,
              padding: const EdgeInsets.symmetric(horizontal: S.x2),
              child: SizedBox(
                height: isTouch ? 56 : 52,
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
                      child: dir == null && storageName(names[i]) != null
                          // Android: the folder's name and where it is; the path in small text.
                          ? Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${p.basename(names[i])} · ${storageName(names[i])}',
                                  style: T.label,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Text(names[i], style: T.caption, maxLines: 1, overflow: TextOverflow.ellipsis),
                              ],
                            )
                          : Text(
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

  Widget _crumb(String label, String? target) {
    // A finger needs 48 dp: 14 dp above and below the line of text.
    final pad = EdgeInsets.symmetric(horizontal: S.x2, vertical: isTouch ? 14 : S.x1);
    return target == dir
        ? Padding(
            padding: pad,
            child: Text(label, style: T.small.copyWith(color: C.text)),
          )
        : Clickable(
            onTap: () => _up(target),
            radius: R.tiny + 2,
            padding: pad,
            child: Text(label, style: T.small),
          );
  }
}
