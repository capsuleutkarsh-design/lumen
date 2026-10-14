import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../art/art_cache.dart';
import '../library/library.dart';
import '../library/models.dart';
import 'app.dart';
import 'pages/artists.dart';
import 'theme.dart';
import 'tracks.dart';
import 'widgets.dart';

class _Hit {
  _Hit(this.kind, this.title, this.subtitle, this.art, this.open, this.tracks, {this.round = false, this.song});
  final String kind, title, subtitle;
  final Art? art;
  final VoidCallback open;

  /// What Play next / Add to queue / the right-click menu act on.
  final List<Track> tracks;
  final Track? song;
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

  @override
  void initState() {
    super.initState();
    // Focus the box even if Tab moved the focus elsewhere before the console opened.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

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
                _Hit('Album', a.title, '${a.artist} · ${a.badge}', lib.artFor(a.key, a.cover), () {
                  close();
                  nav.push('album', a.key);
                }, a.tracks),
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
                  artistMeta(a),
                  resolveArt(a.cover, seed: a.name),
                  () {
                    close();
                    nav.push('artist', a.name);
                  },
                  artistTracks(a),
                  round: true,
                ),
            ],
          ),
        if (songs.isNotEmpty)
          (
            'Songs',
            [
              for (final t in songs)
                _Hit(
                  'Song',
                  t.title,
                  '${t.artist} · ${t.album}',
                  lib.artFor(t.albumKey, t.cover),
                  () {
                    close();
                    // Play the song's album from this song, so what comes next makes sense.
                    final album = lib.albumByKey[t.albumKey]?.tracks ?? [t];
                    engine.playTracks(album, album.indexOf(t).clamp(0, album.length - 1));
                  },
                  [t],
                  song: t,
                ),
            ],
          ),
      ];
    });
  }

  KeyEventResult _key(FocusNode _, KeyEvent e) {
    if (e is KeyUpEvent) return KeyEventResult.ignored;
    final n = _flat.length;
    if (e.logicalKey == LogicalKeyboardKey.enter && n > 0 && shift) {
      _playNext(_flat[_sel]);
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

  void _playNext(_Hit h) {
    nav.setSearch(false);
    queueTracks(context, h.tracks, next: true);
  }

  void _menu(_Hit h, Offset at) {
    if (h.song != null) {
      showTrackMenu(context, at, h.tracks);
    } else {
      showCollectionMenu(context, at, h.tracks);
    }
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
      top: TitleBar.height, // the title bar stays usable
      child: FocusScope(
        autofocus: true,
        // Esc closes from anywhere in the console, even after Tab.
        onKeyEvent: (_, e) {
          if (e is KeyDownEvent && e.logicalKey == LogicalKeyboardKey.escape) {
            nav.setSearch(false);
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: GestureDetector(
          onTap: () => nav.setSearch(false),
          // Clipped, so the blur stops below the title bar.
          child: ClipRect(
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 24, sigmaY: 24),
              child: Container(
                color: C.scrim,
                alignment: Alignment.topCenter,
                // A fixed top: the box stays put when results appear.
                padding: EdgeInsets.only(top: MediaQuery.sizeOf(context).height * 0.12),
                child: GestureDetector(
                  onTap: () {},
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0.97, end: 1),
                    duration: Motion.normal,
                    curve: Motion.curve,
                    builder: (_, s, child) => Transform.scale(scale: s, child: child),
                    child: Container(
                      width: 640,
                      margin: const EdgeInsets.symmetric(horizontal: S.x4),
                      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.7),
                      decoration: BoxDecoration(
                        color: C.raised1,
                        borderRadius: BorderRadius.circular(R.panel),
                        border: Border.all(color: C.borderStrong),
                        boxShadow: [BoxShadow(color: C.shadow, blurRadius: 60, offset: Offset(0, 20))],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(S.x5, S.x2, S.x3, S.x2),
                            child: Row(
                              children: [
                                Icon(LucideIcons.search, size: 18, color: C.dim),
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
                            _hint('Type to search. ↑ ↓ to move, Enter to open or play, Shift+Enter to play next, Esc to close.')
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
    onSecondaryTapDown: (d) => _menu(h, d.globalPosition),
    selected: selected,
    hover: C.raised3,
    radius: R.card - S.x1,
    padding: const EdgeInsets.symmetric(horizontal: S.x2),
    child: SizedBox(
      height: 56,
      child: Row(
        children: [
          CoverArt.art(h.art, size: 40, radius: R.tiny + 2, round: h.round),
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
          if (selected) ...[
            Text(h.song != null ? 'Play' : 'Open', style: T.caption),
            Padding(
              padding: EdgeInsets.only(left: S.x2, right: S.x1),
              child: Icon(LucideIcons.cornerDownLeft, size: 14, color: C.faint),
            ),
          ],
        ],
      ),
    ),
  );
}
