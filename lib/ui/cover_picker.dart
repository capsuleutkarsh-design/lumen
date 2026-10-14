import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../art/art_cache.dart';
import '../art/art_sources.dart';
import '../library/models.dart';
import 'app.dart';
import 'theme.dart';
import 'widgets.dart';

/// Right-click → Change cover: the album's own cover (if any) and Lumen's pick on top, then
/// a tab per art source (Masterpieces, Painted, Illustrated, Abstract...). The pick is stored
/// in the library only; music files are never written.
Future<void> showCoverPicker(BuildContext context, Album a) => showDialog<void>(context: context, builder: (_) => _CoverPicker(a));

class _CoverPicker extends StatefulWidget {
  const _CoverPicker(this.album);
  final Album album;
  @override
  State<_CoverPicker> createState() => _CoverPickerState();
}

class _CoverPickerState extends State<_CoverPicker> {
  static const perPage = 24;
  final _sources = [
    for (final s in artSources)
      if (s.weight > 0) s,
  ];
  late ArtSource _tab = () {
    // Open on the source of the art shown now.
    final key = lib.artFor(widget.album.key, widget.album.cover).key ?? '';
    return _sources.firstWhere(
      (s) => s.pack ? key.startsWith('pack:${s.id}/') : s.styles.any((st) => key.startsWith('${st.name}@')),
      orElse: () => _sources.first,
    );
  }();
  int _pages = 1;

  void _pick(String? choice) {
    lib.setCoverChoice(widget.album.key, choice);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.album, key = artKeyOf(a.key); // the album's art identity (survives a moved folder)
    final current = lib.artFor(key, a.cover);
    final auto = lib.autoArtFor(key);
    final credit = creditFor(current);
    final items = _tab.pack
        ? [for (var n = 1; n <= _tab.images.length; n++) _tab.item(key, n)]
        : [for (var n = 1; n <= _pages * perPage; n++) _tab.item(key, n)];
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
            Row(
              children: [
                if (a.cover != null) ...[
                  SizedBox(
                    width: 92,
                    child: _tile(
                      Art.file(a.cover!),
                      lib.lowCovers.contains(a.cover) ? 'Original (low quality)' : 'Original',
                      current,
                      'original',
                    ),
                  ),
                  const SizedBox(width: S.x3),
                ],
                SizedBox(width: 92, child: _tile(auto, 'Lumen’s pick', current, auto.key!)),
                const SizedBox(width: S.x4),
                if (credit != null)
                  Expanded(
                    child: Text(credit, style: T.caption, maxLines: 2, overflow: TextOverflow.ellipsis),
                  ),
              ],
            ),
            const SizedBox(height: S.x4),
            Wrap(
              spacing: S.x2,
              runSpacing: S.x2,
              children: [
                for (final s in _sources)
                  PillButton(
                    s.name,
                    dense: true,
                    primary: s == _tab,
                    onTap: () => setState(() {
                      _tab = s;
                      _pages = 1;
                    }),
                  ),
              ],
            ),
            const SizedBox(height: S.x3),
            Flexible(
              child: GridView.extent(
                key: PageStorageKey('cover-picker/${_tab.id}'),
                shrinkWrap: true,
                maxCrossAxisExtent: 92,
                mainAxisSpacing: S.x3,
                crossAxisSpacing: S.x3,
                childAspectRatio: 0.78,
                children: [
                  for (final art in items) _tile(art, '', current, art.key!),
                  if (!_tab.pack)
                    Clickable(
                      onTap: () => setState(() => _pages++),
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
                              child: Center(child: Icon(LucideIcons.ellipsis, color: C.dim)),
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

  Widget _tile(Art art, String label, Art current, String choice) {
    final credit = creditFor(art);
    Widget w = Clickable(
      onTap: () => _pick(choice),
      semanticLabel: label.isNotEmpty ? label : credit ?? 'Cover by Lumen',
      radius: R.small,
      child: Column(
        children: [
          DecoratedBox(
            position: DecorationPosition.foreground,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(R.small),
              border: Border.all(color: art == current ? C.accent : C.border, width: art == current ? 2 : 1),
            ),
            child: CoverArt.art(art, radius: R.small),
          ),
          const SizedBox(height: S.x1),
          Text(label, style: T.caption, maxLines: 1, overflow: TextOverflow.ellipsis),
        ],
      ),
    );
    if (credit != null) w = Tooltip(message: credit, child: w);
    return w;
  }
}
