import 'dart:math';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'app.dart';
import 'lyrics_view.dart';
import 'player_bar.dart';
import 'theme.dart';
import 'widgets.dart';

/// Full-window Now Playing (click the cover in the bar; Esc closes): a big
/// cover glowing over its own blurred colours, the song, a large seek bar,
/// and the lyrics beside it when the song has any.
class NowPlaying extends StatefulWidget {
  const NowPlaying({super.key});
  @override
  State<NowPlaying> createState() => _NowPlayingState();
}

class _NowPlayingState extends State<NowPlaying> {
  int? _id;
  bool _hasLyrics = false;

  bool get _showLyrics => nav.memo['np.lyrics'] != false;

  @override
  void initState() {
    super.initState();
    engine.addListener(_check);
    _check();
  }

  @override
  void dispose() {
    engine.removeListener(_check);
    super.dispose();
  }

  void _check() {
    final t = engine.current;
    if (t?.id == _id) return;
    setState(() {
      _id = t?.id;
      _hasLyrics = lyricsFor(t) != null;
    });
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([engine, lib]),
    builder: (context, _) {
      final t = engine.current;
      final seed = t == null ? null : '${t.album}\u0000${t.albumArtist}';
      return Material(
        color: C.bg,
        child: Stack(
          children: [
            // The cover's colours, blurred across the whole window, then darkened.
            CoverGlow(t?.cover, seed: seed, opacity: 0.75, blur: 100),
            const Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(center: Alignment(-0.35, -0.2), radius: 1.25, colors: [Color(0x66000000), Color(0xE6000000)]),
                ),
              ),
            ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(S.x6, S.x2, S.x6, S.x6),
                child: Column(
                  children: [
                    Row(
                      children: [
                        _GlassBtn(LucideIcons.chevronDown, 'Close  (Esc)', () => nav.setNowPlaying(false)),
                        const Spacer(),
                        if (_hasLyrics)
                          _GlassBtn(
                            LucideIcons.micVocal,
                            _showLyrics ? 'Hide lyrics' : 'Show lyrics',
                            () => setState(() => nav.memo['np.lyrics'] = !_showLyrics),
                            active: _showLyrics,
                          ),
                        const SizedBox(width: S.x2),
                        _GlassBtn(LucideIcons.listMusic, 'Queue', () {
                          nav.setNowPlaying(false);
                          if (!nav.queue) nav.toggleQueue();
                        }),
                      ],
                    ),
                    Expanded(
                      child: t == null
                          ? const EmptyState(icon: LucideIcons.music, title: 'Nothing playing', body: 'Double-click any song to play it.')
                          : LayoutBuilder(
                              builder: (context, c) {
                                final side = _hasLyrics && _showLyrics && c.maxWidth >= 880;
                                final player = _Player(maxW: side ? c.maxWidth * 0.5 : c.maxWidth, maxH: c.maxHeight);
                                if (!side) return Center(child: player);
                                return Row(
                                  children: [
                                    Expanded(flex: 11, child: Center(child: player)),
                                    const SizedBox(width: S.x8),
                                    const Expanded(flex: 9, child: LyricsView(embedded: true)),
                                  ],
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    },
  );
}

/// Cover, title, artist · album, seek bar and the transport, one column.
class _Player extends StatelessWidget {
  const _Player({required this.maxW, required this.maxH});
  final double maxW, maxH;
  @override
  Widget build(BuildContext context) {
    final t = engine.current!;
    final fav = lib.isFavourite(t.id);
    // Leave room under the cover for the text, seek bar and transport.
    final below = textHeight(context, [T.title, T.body, T.small, T.caption]) + 250;
    final size = min(min(maxW - S.x8, maxH - below), 560.0).clamp(160.0, 560.0);
    // The column is at least wide enough for the controls; the cover keeps its left edge.
    final width = min(max(size, 360.0), maxW);
    return SingleChildScrollView(
      child: SizedBox(
        width: width,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(R.card),
                boxShadow: const [BoxShadow(color: C.shadow, blurRadius: 64, offset: Offset(0, 24))],
              ),
              child: AnimatedSwitcher(
                duration: Motion.slow,
                child: CoverArt.track(t, key: ValueKey(t.id), size: size, radius: R.card),
              ),
            ),
            const SizedBox(height: S.x6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(t.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: T.title),
                      const SizedBox(height: S.x1),
                      Text(
                        [t.artist, if (t.album.isNotEmpty) t.album].join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: T.body.copyWith(color: C.dim),
                      ),
                    ],
                  ),
                ),
                IconBtn(
                  fav ? Icons.favorite_rounded : LucideIcons.heart,
                  size: 20,
                  box: 44,
                  color: fav ? C.accent : C.text,
                  tooltip: fav ? 'Remove from Favourites' : 'Add to Favourites',
                  onTap: () => lib.toggleFavourite(t.id),
                ),
              ],
            ),
            const SizedBox(height: S.x4),
            const SeekBar(big: true),
            const SizedBox(height: S.x2),
            const Center(
              child: FittedBox(fit: BoxFit.scaleDown, child: Transport(big: true)),
            ),
            const SizedBox(height: S.x3),
            Row(
              children: [
                Flexible(child: FormatBadge(t.badge)),
                const Spacer(),
                const SizedBox(width: 168, child: VolumeControl()),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _GlassBtn extends StatelessWidget {
  const _GlassBtn(this.icon, this.tooltip, this.onTap, {this.active = false});
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool active;
  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: active ? C.glassBorder : C.glass,
      shape: BoxShape.circle,
      border: Border.all(color: C.glassBorder),
    ),
    child: IconBtn(icon, color: C.text, tooltip: tooltip, onTap: onTap),
  );
}
