import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../library/lyrics.dart';
import 'app.dart';
import 'theme.dart';
import 'widgets.dart';

/// Big lyrics over the blurred cover; the current line is bright and centred.
class LyricsView extends StatefulWidget {
  const LyricsView({super.key});
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
      _lyrics = t == null ? null : loadLyrics(t.path, lib.embeddedLyrics(t.id));
      _keys
        ..clear()
        ..addAll(List.generate(_lyrics?.lines.length ?? 0, (_) => GlobalKey()));
      _line = -1;
    });
    _follow();
  }

  void _follow() {
    final l = _lyrics;
    if (l == null || !l.synced) return;
    final i = l.lineAt(engine.position.value);
    if (i == _line) return;
    setState(() => _line = i);
    final ctx = i >= 0 ? _keys[i].currentContext : null;
    if (ctx != null) Scrollable.ensureVisible(ctx, alignment: 0.4, duration: Motion.normal, curve: Motion.curve);
  }

  @override
  Widget build(BuildContext context) {
    final t = engine.current;
    final l = _lyrics;
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
            CoverGlow(t?.cover, opacity: 0.35),
            if (t == null)
              const EmptyState(icon: LucideIcons.micVocal, title: 'Nothing playing', body: 'Play a song to see its lyrics here.')
            else if (l == null)
              EmptyState(
                icon: LucideIcons.micVocal,
                title: 'No lyrics for this song',
                body: 'Put a .lrc file with the same name next to “${t.title}”, or add a LYRICS tag, and they will show here.',
              )
            else
              ShaderMask(
                shaderCallback: (r) => const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Colors.black, Colors.black, Colors.transparent],
                  stops: [0, 0.12, 0.85, 1],
                ).createShader(r),
                blendMode: BlendMode.dstIn,
                child: ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.symmetric(horizontal: S.x12 + S.x4, vertical: 200),
                  itemCount: l.lines.length,
                  itemBuilder: (_, i) {
                    final (time, words) = l.lines[i];
                    final current = !l.synced || i == _line;
                    return Padding(
                      key: _keys[i],
                      padding: const EdgeInsets.symmetric(vertical: S.x3),
                      child: Clickable(
                        onTap: l.synced ? () => engine.seek(time) : null,
                        hover: Colors.transparent,
                        pressed: Colors.transparent,
                        radius: R.small,
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: AnimatedDefaultTextStyle(
                            duration: Motion.normal,
                            curve: Motion.curve,
                            style: l.synced
                                ? T.lyric.copyWith(color: current ? C.text : C.text.withValues(alpha: i < _line ? 0.22 : 0.38))
                                : T.lyric.copyWith(fontSize: 24, color: C.text.withValues(alpha: 0.85)),
                            child: Text(words.isEmpty ? '♪' : words),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            if (l != null)
              Positioned(
                right: S.x5,
                bottom: S.x5,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: S.x3, vertical: S.x1 + 2),
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
