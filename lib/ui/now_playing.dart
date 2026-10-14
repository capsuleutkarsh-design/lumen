import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:window_manager/window_manager.dart';

import '../library/models.dart';
import '../platform/window.dart';
import 'app.dart';
import 'art_accent.dart';
import 'cover_picker.dart';
import 'disc.dart';
import 'lyrics_view.dart';
import 'player_bar.dart';
import 'theme.dart';
import 'tracks.dart';
import 'widgets.dart';

/// Right-click on the big cover: Change cover, Disc mode, Go to album.
Future<void> nowPlayingCoverMenu(BuildContext context, Offset at, Track t) async {
  final album = lib.albumByKey[t.albumKey];
  final v = await popMenu(context, at, [
    if (album != null) menuItem('cover', LucideIcons.image, 'Change cover…'),
    if (!nav.disc) menuItem('disc', LucideIcons.disc3, 'Disc mode', hint: 'D'),
    if (album != null) menuItem('album', LucideIcons.disc, 'Go to album'),
  ]);
  if (!context.mounted) return;
  switch (v) {
    case 'cover':
      await showCoverPicker(context, album!);
    case 'disc':
      nav.setDisc(true);
    case 'album':
      nav.push('album', t.albumKey);
  }
}

/// Full-window Now Playing (click the cover in the bar; Esc closes): the cover with
/// its spinning disc, glowing over its own blurred colours, the song, a large seek bar,
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
    listenable: Listenable.merge([engine, lib, discStyle]),
    builder: (context, _) {
      final t = engine.current;
      return Material(
        color: C.bg,
        child: Stack(
          children: [
            // The cover's colours, blurred across the whole window, then darkened.
            CoverGlow(t == null ? null : lib.artFor(t.albumKey, t.cover), opacity: 0.75, blur: 100),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(center: Alignment(-0.35, -0.2), radius: 1.25, colors: [C.veil(0.4), C.veil(0.9)]),
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
                        _GlassBtn(LucideIcons.disc3, 'Disc mode  (D)', () => nav.setDisc(true)),
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

/// Cover and disc, title, artist · album, seek bar and the transport, one column.
class _Player extends StatelessWidget {
  const _Player({required this.maxW, required this.maxH});
  final double maxW, maxH;
  @override
  Widget build(BuildContext context) {
    final t = engine.current!;
    final fav = lib.isFavourite(t.id);
    final style = discStyle.value;
    final wide = DiscView.widthFor(1, style);
    // Leave room under the cover for the text, seek bar and transport.
    final below = textHeight(context, [T.title, T.body, T.small, T.caption]) + 250;
    final size = min(min((maxW - S.x8) / wide, maxH - below), 560.0).clamp(160.0, 560.0);
    // The column is at least wide enough for the controls; the cover keeps its left edge.
    final width = min(max(size * wide, 360.0), maxW);
    return SingleChildScrollView(
      child: SizedBox(
        width: width,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // The glow under the cover takes the art's colour (coral without one).
            ArtAccentBuilder(
              builder: (context, accent) => DiscView(
                art: lib.artFor(t.albumKey, t.cover),
                id: t.id,
                playing: engine.playing,
                size: size,
                style: style,
                glow: accent,
                onCoverMenu: (d) => nowPlayingCoverMenu(context, d.globalPosition, t),
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

/// Disc mode (D): only the cover and its spinning disc over the art's blurred colours.
/// Moving the mouse shows small controls for 2 s. Esc leaves; F11 fills the screen.
class DiscMode extends StatefulWidget {
  const DiscMode({super.key});
  @override
  State<DiscMode> createState() => _DiscModeState();
}

class _DiscModeState extends State<DiscMode> {
  bool _controls = false;
  Timer? _hide;

  void _poke() {
    _hide?.cancel();
    _hide = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _controls = false);
    });
    if (!_controls) setState(() => _controls = true);
  }

  @override
  void dispose() {
    _hide?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([engine, lib, discStyle]),
    builder: (context, _) {
      final t = engine.current;
      final art = t == null ? null : lib.artFor(t.albumKey, t.cover);
      return MouseRegion(
        onHover: (_) => _poke(),
        cursor: _controls ? MouseCursor.defer : SystemMouseCursors.none,
        child: Material(
          color: C.bg,
          child: Stack(
            children: [
              CoverGlow(art, opacity: 0.7, blur: 120),
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(gradient: RadialGradient(radius: 1.2, colors: [C.veil(0.35), C.veil(0.85)])),
                ),
              ),
              Positioned.fill(child: dragArea(const SizedBox.expand())),
              if (art != null)
                Center(
                  child: LayoutBuilder(
                    builder: (context, c) {
                      final wide = DiscView.widthFor(1, discStyle.value);
                      final size = min(c.maxHeight * 0.62, c.maxWidth * 0.8 / wide);
                      return Padding(
                        // Optically centred: the disc side carries less weight than the cover.
                        padding: EdgeInsets.only(left: size * (wide - 1) * 0.15),
                        child: DiscView(
                          art: art,
                          id: t!.id,
                          playing: engine.playing,
                          size: size,
                          style: discStyle.value,
                          onCoverMenu: (d) => nowPlayingCoverMenu(context, d.globalPosition, t),
                        ),
                      );
                    },
                  ),
                ),
              Positioned(
                left: 0,
                right: 0,
                bottom: S.x8,
                child: IgnorePointer(
                  ignoring: !_controls,
                  child: AnimatedOpacity(
                    opacity: _controls ? 1 : 0,
                    duration: Motion.slow,
                    child: Center(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: C.glass,
                          borderRadius: BorderRadius.circular(R.pill),
                          border: Border.all(color: C.glassBorder),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(S.x1),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconBtn(LucideIcons.skipBack, color: C.text, tooltip: 'Previous', onTap: t == null ? null : engine.previous),
                              IconBtn(
                                engine.playing ? LucideIcons.pause : LucideIcons.play,
                                color: C.text,
                                tooltip: engine.playing ? 'Pause  (Space)' : 'Play  (Space)',
                                onTap: t == null ? null : engine.togglePlay,
                              ),
                              IconBtn(LucideIcons.skipForward, color: C.text, tooltip: 'Next', onTap: t == null ? null : engine.next),
                              if (isDesktop)
                                IconBtn(LucideIcons.expand, color: C.text, tooltip: 'Full screen  (F11)', onTap: toggleFullScreen),
                              IconBtn(LucideIcons.x, color: C.text, tooltip: 'Leave disc mode  (Esc)', onTap: () => nav.setDisc(false)),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

Future<void> toggleFullScreen() async => windowManager.setFullScreen(!await windowManager.isFullScreen());
