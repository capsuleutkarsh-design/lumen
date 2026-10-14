import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../art/art_cache.dart';
import '../art/generative_cover.dart';
import '../library/models.dart';
import 'app.dart';
import 'theme.dart';
import 'widgets.dart';

/// Right-click → Change cover: the album's own cover (if any), the art Lumen drew for it,
/// and 24 more generated choices per page. The pick is stored in the library only;
/// music files are never written.
Future<void> showCoverPicker(BuildContext context, Album a) => showDialog<void>(context: context, builder: (_) => _CoverPicker(a));

class _CoverPicker extends StatefulWidget {
  const _CoverPicker(this.album);
  final Album album;
  @override
  State<_CoverPicker> createState() => _CoverPickerState();
}

class _CoverPickerState extends State<_CoverPicker> {
  int _page = 0;
  static const perPage = 24;

  void _pick(String? choice) {
    lib.setCoverChoice(widget.album.key, choice);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.album, key = a.key;
    final current = lib.artFor(key, a.cover);
    final auto = GenerativeCover.seedFor(key);
    final tiles = <(Art, String?, String)>[
      if (a.cover != null) (Art(a.cover, 0), 'original', lib.lowCovers.contains(a.cover) ? 'Original (low quality)' : 'Original'),
      (Art(null, auto), '$auto', 'Drawn by Lumen'),
      for (var n = _page * perPage + 1; n <= (_page + 1) * perPage; n++) _generated(GenerativeCover.seedFor('$key#$n')),
    ];
    return AlertDialog(
      title: Text('Change cover · ${a.title}', maxLines: 1, overflow: TextOverflow.ellipsis),
      content: SizedBox(
        width: 760,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Pick any artwork. Lumen keeps your choice; the music files are never changed.', style: T.small),
            const SizedBox(height: S.x4),
            Flexible(
              child: GridView.extent(
                shrinkWrap: true,
                maxCrossAxisExtent: 92,
                mainAxisSpacing: S.x3,
                crossAxisSpacing: S.x3,
                childAspectRatio: 0.78,
                children: [
                  for (final (art, choice, label) in tiles) _tile(art, label, art == current, () => _pick(choice)),
                  Clickable(
                    onTap: () => setState(() => _page++),
                    semanticLabel: 'More covers',
                    radius: R.small,
                    child: Column(
                      children: [
                        AspectRatio(
                          aspectRatio: 1,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(R.small),
                              border: Border.all(color: C.borderStrong),
                            ),
                            child: const Center(child: Icon(LucideIcons.ellipsis, color: C.dim)),
                          ),
                        ),
                        const SizedBox(height: S.x1),
                        Text('More…', style: T.caption),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        PillButton('Reset to automatic', icon: LucideIcons.rotateCcw, onTap: lib.coverChoices.containsKey(key) ? () => _pick(null) : null),
        PillButton('Close', onTap: () => Navigator.pop(context)),
      ],
    );
  }

  static (Art, String?, String) _generated(int seed) => (Art(null, seed), '$seed', '');

  Widget _tile(Art art, String label, bool selected, VoidCallback onTap) => Clickable(
    onTap: onTap,
    semanticLabel: label.isEmpty ? 'Generated cover' : label,
    radius: R.small,
    child: Column(
      children: [
        DecoratedBox(
          position: DecorationPosition.foreground,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(R.small),
            border: Border.all(color: selected ? C.accent : C.border, width: selected ? 2 : 1),
          ),
          child: CoverArt.art(art, radius: R.small),
        ),
        const SizedBox(height: S.x1),
        Text(label, style: T.caption, maxLines: 1, overflow: TextOverflow.ellipsis),
      ],
    ),
  );
}
