import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../library/library.dart';
import '../library/models.dart';
import 'app.dart';
import 'theme.dart';
import 'widgets.dart';

class _Hit {
  _Hit(this.kind, this.title, this.subtitle, this.cover, this.open, {this.round = false});
  final String kind, title, subtitle;
  final String? cover;
  final VoidCallback open;
  final bool round;
}

/// Ctrl+K: albums, artists and songs, keyboard first.
class SearchConsole extends StatefulWidget {
  const SearchConsole({super.key});
  @override
  State<SearchConsole> createState() => _SearchConsoleState();
}

class _SearchConsoleState extends State<SearchConsole> {
  final _text = TextEditingController();
  late final _focus = FocusNode(onKeyEvent: _key);
  final _scroll = ScrollController();
  List<(String, List<_Hit>)> _groups = [];
  int _sel = 0;

  List<_Hit> get _flat => [for (final g in _groups) ...g.$2];

  void _search(String q) {
    final s = q.trim().toLowerCase();
    if (s.isEmpty) {
      setState(() => _groups = []);
      return;
    }
    int rank(String text) {
      final l = text.toLowerCase();
      return l.startsWith(s) ? 0 : (l.contains(' $s') ? 1 : (l.contains(s) ? 2 : 9));
    }

    List<X> best<X>(Iterable<X> xs, String Function(X) key, int n) {
      final hits = [
        for (final x in xs)
          if (rank(key(x)) < 9) x,
      ]..sort((a, b) => rank(key(a)).compareTo(rank(key(b))));
      return hits.take(n).toList();
    }

    void close() => nav.setSearch(false);
    final albums = best<Album>(lib.albums, (a) => '${a.title} ${a.artist}', 4);
    final artists = best<Artist>(lib.artists, (a) => a.name, 3);
    final songs = best<Track>(lib.tracks, (t) => '${t.title} ${t.artist}', 8);
    setState(() {
      _sel = 0;
      _groups = [
        if (albums.isNotEmpty)
          (
            'Albums',
            [
              for (final a in albums)
                _Hit('Album', a.title, '${a.artist} · ${a.badge}', a.cover, () {
                  close();
                  nav.push('album', a.key);
                }),
            ],
          ),
        if (artists.isNotEmpty)
          (
            'Artists',
            [
              for (final a in artists)
                _Hit(
                  'Artist',
                  a.name,
                  '${plural(a.albums.length, 'album')} · ${plural(a.albums.fold(0, (n, x) => n + x.tracks.length) + a.appearsOn.length, 'song')}',
                  a.cover,
                  () {
                    close();
                    nav.push('artist', a.name);
                  },
                  round: true,
                ),
            ],
          ),
        if (songs.isNotEmpty)
          (
            'Songs',
            [
              for (final t in songs)
                _Hit('Song', t.title, '${t.artist} · ${t.album}', t.cover, () {
                  close();
                  engine.playTracks([t]);
                }),
            ],
          ),
      ];
    });
  }

  KeyEventResult _key(FocusNode _, KeyEvent e) {
    if (e is KeyUpEvent) return KeyEventResult.ignored;
    final n = _flat.length;
    if (e.logicalKey == LogicalKeyboardKey.escape) {
      nav.setSearch(false);
    } else if (e.logicalKey == LogicalKeyboardKey.arrowDown && n > 0) {
      setState(() => _sel = (_sel + 1) % n);
      _reveal();
    } else if (e.logicalKey == LogicalKeyboardKey.arrowUp && n > 0) {
      setState(() => _sel = (_sel - 1 + n) % n);
      _reveal();
    } else if (e.logicalKey == LogicalKeyboardKey.enter && n > 0) {
      _flat[_sel].open();
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  void _reveal() {
    // Rows are 56 px; headers add 32 px each.
    var y = 0.0, i = 0;
    for (final g in _groups) {
      y += 32;
      for (final _ in g.$2) {
        if (i++ == _sel) {
          final view = _scroll.position.viewportDimension;
          if (y < _scroll.offset) _scroll.jumpTo(y - 32);
          if (y + 56 > _scroll.offset + view) _scroll.jumpTo(y + 56 - view);
          return;
        }
        y += 56;
      }
    }
  }

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    var i = 0;
    return Positioned.fill(
      child: GestureDetector(
        onTap: () => nav.setSearch(false),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 24, sigmaY: 24),
          child: Container(
            color: const Color(0x99000000),
            alignment: const Alignment(0, -0.45),
            child: GestureDetector(
              onTap: () {},
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0.97, end: 1),
                duration: Motion.normal,
                curve: Motion.curve,
                builder: (_, s, child) => Transform.scale(scale: s, child: child),
                child: Container(
                  width: 640,
                  constraints: const BoxConstraints(maxHeight: 520),
                  decoration: BoxDecoration(
                    color: C.raised1,
                    borderRadius: BorderRadius.circular(R.panel),
                    border: Border.all(color: C.borderStrong),
                    boxShadow: const [BoxShadow(color: Color(0xAA000000), blurRadius: 60, offset: Offset(0, 20))],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(S.x5, S.x2, S.x3, S.x2),
                        child: Row(
                          children: [
                            const Icon(LucideIcons.search, size: 18, color: C.dim),
                            const SizedBox(width: S.x3),
                            Expanded(
                              child: TextField(
                                controller: _text,
                                focusNode: _focus,
                                autofocus: true,
                                onChanged: _search,
                                style: T.heading.copyWith(fontWeight: FontWeight.w400),
                                decoration: const InputDecoration(
                                  hintText: 'Search songs, albums and artists',
                                  filled: false,
                                  border: InputBorder.none,
                                  enabledBorder: InputBorder.none,
                                  focusedBorder: InputBorder.none,
                                ),
                              ),
                            ),
                            IconBtn(LucideIcons.x, size: 16, tooltip: 'Close  (Esc)', onTap: () => nav.setSearch(false)),
                          ],
                        ),
                      ),
                      Container(height: 1, color: C.border),
                      if (_text.text.trim().isEmpty)
                        _hint('Type to search. Use ↑ ↓ to move, Enter to open, Esc to close.')
                      else if (_groups.isEmpty)
                        _hint('Nothing matches “${_text.text.trim()}”.')
                      else
                        Flexible(
                          child: ListView(
                            controller: _scroll,
                            shrinkWrap: true,
                            padding: const EdgeInsets.all(S.x2),
                            children: [
                              for (final g in _groups) ...[
                                SizedBox(
                                  height: 32,
                                  child: Padding(
                                    padding: const EdgeInsets.fromLTRB(S.x3, S.x3, 0, 0),
                                    child: Text(g.$1, style: T.caption),
                                  ),
                                ),
                                for (final h in g.$2) _row(h, i++ == _sel),
                              ],
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _hint(String s) => Padding(
    padding: const EdgeInsets.all(S.x6),
    child: Text(s, style: T.small),
  );

  Widget _row(_Hit h, bool selected) => Clickable(
    onTap: h.open,
    selected: selected,
    hover: C.raised3,
    radius: R.panel - S.x2,
    padding: const EdgeInsets.symmetric(horizontal: S.x2),
    child: SizedBox(
      height: 56,
      child: Row(
        children: [
          CoverArt(h.cover, size: 40, radius: R.small - 2, round: h.round),
          const SizedBox(width: S.x3),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(text: h.title, style: T.label),
                      TextSpan(text: '  ${h.kind}', style: T.caption),
                    ],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(h.subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: T.small),
              ],
            ),
          ),
          if (selected) const Icon(LucideIcons.cornerDownLeft, size: 14, color: C.faint),
        ],
      ),
    ),
  );
}
