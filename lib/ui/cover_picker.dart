import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../art/art_cache.dart';
import '../art/art_sources.dart';
import '../library/models.dart';
import 'app.dart';
import 'pages/browse.dart' show Segmented;
import 'phone.dart';
import 'theme.dart';
import 'widgets.dart';

/// Right-click → Change cover: the album's own cover (if any) and Gleo's pick on top, then
/// a tab per art source (Masterpieces, Painted, Illustrated, Abstract...). The pick is stored
/// in the library only; music files are never written.
/// The phone gets a tall bottom sheet with a 3-column grid instead of the dialog.
Future<void> showCoverPicker(BuildContext context, Album a) => phoneLayout(context)
    ? showPhoneSheet<void>(context, (_) => _CoverPicker(a, phone: true))
    : showDialog<void>(context: context, builder: (_) => _CoverPicker(a));

class _CoverPicker extends StatefulWidget {
  const _CoverPicker(this.album, {this.phone = false});
  final Album album;
  final bool phone;
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
    final reset = lib.coverChoices.containsKey(key) ? () => _pick(null) : null;
    if (widget.phone) return _phone(a, key, current, auto, credit, items, reset);
    return AlertDialog(
      title: Text('Change cover · ${a.title}', maxLines: 1, overflow: TextOverflow.ellipsis),
      content: SizedBox(
        width: 760,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Pick any artwork. Gleo keeps your choice; the music files are never changed.', style: T.small),
            const SizedBox(height: S.x4),
            Row(
              children: [
                if (a.cover != null) ...[
                  SizedBox(
                    width: 92,
                    child: _tile(Art.file(a.cover!), lib.lowCovers.contains(a.cover) ? 'Original (low quality)' : 'Original', current, 'original'),
                  ),
                  const SizedBox(width: S.x3),
                ],
                SizedBox(width: 92, child: _tile(auto, 'Gleo’s pick', current, auto.key!)),
                const SizedBox(width: S.x4),
                if (credit != null)
                  Expanded(
                    child: Text(credit, style: T.caption, maxLines: 2, overflow: TextOverflow.ellipsis),
                  ),
              ],
            ),
            const SizedBox(height: S.x4),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Segmented(
                value: _tab,
                options: [for (final s in _sources) (s, s.name)],
                onChanged: (s) => setState(() {
                  _tab = s;
                  _pages = 1;
                }),
              ),
            ),
            const SizedBox(height: S.x3),
            Flexible(
              child: GridView.extent(
                key: PageStorageKey('cover-picker/${_tab.id}'),
                shrinkWrap: true,
                maxCrossAxisExtent: 92,
                mainAxisSpacing: S.x2,
                crossAxisSpacing: S.x2,
                children: [for (final art in items) _tile(art, '', current, art.key!), if (!_tab.pack) _more()],
              ),
            ),
          ],
        ),
      ),
      actions: [
        PillButton('Reset to automatic', icon: LucideIcons.rotateCcw, onTap: reset),
        PillButton('Close', onTap: () => Navigator.pop(context)),
      ],
    );
  }

  Widget _more() => Clickable(
    onTap: () => setState(() => _pages++),
    semanticLabel: 'More covers',
    radius: R.small,
    child: Align(
      alignment: Alignment.topCenter,
      child: AspectRatio(
        aspectRatio: 1,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(R.small),
            border: Border.all(color: C.borderStrong),
          ),
          child: Center(child: Text('More…', style: T.caption)),
        ),
      ),
    ),
  );

  /// The phone: Reset in the header, the sources as one scrolling row of 48 dp chips, 3 covers a row.
  Widget _phone(Album a, String key, Art current, Art auto, String? credit, List<Art> items, VoidCallback? reset) => SizedBox(
    height: MediaQuery.sizeOf(context).height * 0.9,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(S.x4, S.x3, S.x4, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Change cover', style: T.heading),
                    Text(a.title, style: T.small, maxLines: 1, overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
              PillButton('Reset to automatic', icon: LucideIcons.rotateCcw, dense: true, onTap: reset),
            ],
          ),
          const SizedBox(height: S.x3),
          Row(
            children: [
              if (a.cover != null) ...[
                SizedBox(
                  width: 80,
                  child: _tile(Art.file(a.cover!), lib.lowCovers.contains(a.cover) ? 'Original (low quality)' : 'Original', current, 'original'),
                ),
                const SizedBox(width: S.x2),
              ],
              SizedBox(width: 80, child: _tile(auto, 'Gleo’s pick', current, auto.key!)),
              const SizedBox(width: S.x3),
              Expanded(
                child: Text(
                  credit ?? 'Gleo keeps your choice; the music files are never changed.',
                  style: T.caption,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: S.x2),
          SizedBox(
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final s in _sources)
                  Padding(
                    padding: const EdgeInsets.only(right: S.x2),
                    child: Center(
                      child: PillButton(
                        s.name,
                        dense: true,
                        primary: s == _tab,
                        onTap: () => setState(() {
                          _tab = s;
                          _pages = 1;
                        }),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: S.x2),
          Expanded(
            child: GridView.count(
              key: PageStorageKey('cover-picker/${_tab.id}'),
              crossAxisCount: 3,
              mainAxisSpacing: S.x2,
              crossAxisSpacing: S.x2,
              childAspectRatio: 0.85,
              padding: EdgeInsets.only(bottom: S.x4 + MediaQuery.paddingOf(context).bottom),
              children: [for (final art in items) _tile(art, '', current, art.key!, caption: false), if (!_tab.pack) _more()],
            ),
          ),
        ],
      ),
    ),
  );

  Widget _tile(Art art, String label, Art current, String choice, {bool caption = true}) {
    final credit = creditFor(art);
    Widget w = Clickable(
      onTap: () => _pick(choice),
      semanticLabel: label.isNotEmpty ? label : credit ?? 'Cover by Gleo',
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
          if (caption && label.isNotEmpty) ...[
            const SizedBox(height: S.x1),
            Text(label, style: T.caption, maxLines: 1, overflow: TextOverflow.ellipsis),
          ],
        ],
      ),
    );
    if (credit != null) w = Tooltip(message: credit, child: w);
    return w;
  }
}
