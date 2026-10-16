import 'dart:math';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../library/lyrics.dart';
import '../library/models.dart';
import 'app.dart';
import 'phone.dart' show phoneLayout;
import 'theme.dart';
import 'widgets.dart';

/// The lyrics of [t] (a `.lrc` next to the file, else the LYRICS tag), or null.
Lyrics? lyricsFor(Track? t) => t == null ? null : loadLyrics(t.path, lib.embeddedLyrics(t.id));

/// Big lyrics over a dark, quiet wash of the cover's colours; the current line
/// is bright. [embedded] = the side panel of Now Playing (no frame, no glow).
class LyricsView extends StatefulWidget {
  const LyricsView({super.key, this.embedded = false});
  final bool embedded;
  @override
  State<LyricsView> createState() => _LyricsViewState();
}

class _LyricsViewState extends State<LyricsView> {
  final _scroll = ScrollController();
  final _keys = <GlobalKey>[];
  int? _trackId;
  Lyrics? _lyrics;
  int _line = -1;

  @override
  void initState() {
    super.initState();
    engine.addListener(_reload);
    engine.position.addListener(_follow);
    _reload();
  }

  @override
  void dispose() {
    engine.removeListener(_reload);
    engine.position.removeListener(_follow);
    _scroll.dispose();
    super.dispose();
  }

  void _reload() {
    final t = engine.current;
    if (t?.id == _trackId) return;
    setState(() {
      _trackId = t?.id;
      _lyrics = lyricsFor(t);
      _keys
        ..clear()
        ..addAll(List.generate(_lyrics?.lines.length ?? 0, (_) => GlobalKey()));
      _line = -1;
    });
    if (_scroll.hasClients) _scroll.jumpTo(0);
    _follow();
  }

  void _follow() {
    final l = _lyrics;
    if (l == null || !l.synced) return;
    final i = l.lineAt(engine.position.value);
    if (i == _line) return;
    setState(() => _line = i);
    if (i >= 0) _reveal(i, 3);
  }

  /// Centres line [i]. A line far away is not built yet (after a long seek),
  /// so jump near it by an estimate first, then settle on it once it exists.
  void _reveal(int i, int tries) {
    final ctx = _keys[i].currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(ctx, alignment: 0.4, duration: Motion.slow, curve: Motion.curve);
      return;
    }
    if (tries <= 0 || !_scroll.hasClients) return;
    final pos = _scroll.position;
    // Step from a line that is built, by that line's height per line.
    final ref = _keys.indexWhere((k) => k.currentContext != null);
    final h = ref < 0 ? 60.0 : (_keys[ref].currentContext!.findRenderObject() as RenderBox).size.height;
    _scroll.jumpTo((pos.pixels + (i - max(ref, 0)) * h).clamp(0.0, pos.maxScrollExtent));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _line == i) _reveal(i, tries - 1);
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = engine.current;
    final l = _lyrics;
    final style = widget.embedded ? T.lyric.copyWith(fontSize: 24) : T.lyric;
    // The phone shows them over the cover's colours in Now Playing: the other lines stay readable there.
    final phone = widget.embedded && phoneLayout(context);
    Widget body;
    if (t == null) {
      body = const EmptyState(icon: LucideIcons.micVocal, title: 'Nothing playing', body: 'Play a song to see its lyrics here.');
    } else if (l == null) {
      body = const EmptyState(
        icon: LucideIcons.micVocal,
        title: 'No lyrics for this song',
        body: 'Put a .lrc file with the same name next to the song, or add a LYRICS tag, and they will show here.',
      );
    } else {
      body = ShaderMask(
        shaderCallback: (r) => const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.transparent, Colors.black, Colors.black, Colors.transparent],
          stops: [0, 0.14, 0.82, 1],
        ).createShader(r),
        blendMode: BlendMode.dstIn,
        child: LayoutBuilder(
          builder: (context, c) => ListView.builder(
            controller: _scroll,
            padding: EdgeInsets.symmetric(horizontal: widget.embedded ? S.x2 : S.x16, vertical: c.maxHeight * 0.4),
            itemCount: l.lines.length,
            itemBuilder: (_, i) {
              final (time, words) = l.lines[i];
              final text = Text(words.isEmpty ? '♪' : words);
              if (!l.synced) {
                // Plain lyrics: calm and fully readable; nothing to click.
                return Padding(
                  key: _keys[i],
                  padding: const EdgeInsets.symmetric(vertical: S.x1),
                  child: DefaultTextStyle(
                    style: style.copyWith(fontWeight: FontWeight.w500, color: C.text.withValues(alpha: 0.88)),
                    child: text,
                  ),
                );
              }
              final current = i == _line;
              return Padding(
                key: _keys[i],
                padding: const EdgeInsets.symmetric(vertical: S.x2),
                child: Clickable(
                  onTap: () => engine.seek(time),
                  hover: Colors.transparent,
                  pressed: Colors.transparent,
                  radius: R.small,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: AnimatedDefaultTextStyle(
                      duration: Motion.slow,
                      curve: Motion.curve,
                      style: style.copyWith(
                        color: current ? C.text : C.text.withValues(alpha: phone ? 0.45 : (i < _line ? 0.2 : 0.34)),
                      ),
                      child: text,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      );
    }
    if (widget.embedded) return body;
    return ClipRRect(
      borderRadius: BorderRadius.circular(R.panel),
      child: Container(
        decoration: BoxDecoration(
          color: C.raised1,
          borderRadius: BorderRadius.circular(R.panel),
          border: Border.all(color: C.border),
        ),
        child: Stack(
          children: [
            // A dark, quiet wash of the cover's colours (like Wora), not a loud glow.
            CoverGlow(t == null ? null : lib.artFor(t.albumKey, t.cover), opacity: 0.3, blur: 90),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(center: Alignment(0.4, 0.5), radius: 1.3, colors: [C.veil(0.95), C.veil(0.55)]),
                ),
              ),
            ),
            body,
            if (l != null)
              Positioned(
                right: S.x5,
                bottom: S.x5,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: S.x3, vertical: S.x1),
                  decoration: BoxDecoration(
                    color: C.raised3,
                    borderRadius: BorderRadius.circular(R.pill),
                    border: Border.all(color: C.borderStrong),
                  ),
                  child: Text(l.synced ? 'Synced' : 'Not synced', style: T.caption.copyWith(color: C.dim)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
