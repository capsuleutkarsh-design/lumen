import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:window_manager/window_manager.dart';

import '../library/models.dart';
import '../platform/window.dart';
import 'app.dart';
import 'art_accent.dart';
import 'cover_picker.dart';
import 'disc.dart';
import 'lyrics_view.dart';
import 'phone.dart' show phoneLayout, phoneSheet, sheetHeader;
import 'player_bar.dart';
import 'theme.dart';
import 'tracks.dart';
import 'widgets.dart';

/// Right-click on the big cover: Change cover, Disc mode, Go to album.
/// The phone (its ⋮ and a long press on the cover) gets one sheet with everything for the song.
Future<void> nowPlayingCoverMenu(BuildContext context, Offset at, Track t) async {
  final album = lib.albumByKey[t.albumKey];
  if (phoneLayout(context)) {
    final v = await phoneSheet(context, header: sheetHeader(CoverArt.track(t, size: 48), t.title, t.artist), [
      ('playlist', LucideIcons.listPlus, 'Add to playlist…'),
      if (album != null) ('album', LucideIcons.disc, 'Go to album'),
      ('artist', LucideIcons.micVocal, 'Go to artist'),
      if (album != null) ('cover', LucideIcons.image, 'Change cover…'),
      ('sound', LucideIcons.slidersVertical, 'Sound'),
      if (!nav.disc) ('disc', LucideIcons.disc3, 'Disc mode'),
    ]);
    if (!context.mounted) return;
    switch (v) {
      case 'playlist':
        await addToPlaylistDialog(context, [t]);
      case 'album':
        nav.push('album', t.albumKey);
      case 'artist':
        nav.push('artist', t.artist);
      case 'cover':
        await showCoverPicker(context, album!);
      case 'sound':
        nav.push('sound', '');
      case 'disc':
        nav.setDisc(true);
    }
    return;
  }
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

  /// The phone: the lyrics in place of the cover.
  bool _phoneLyrics = false;

  /// The phone: where the song's text starts, so a scrim can sit behind it whatever the cover.
  final _infoKey = GlobalKey();
  final _infoTop = ValueNotifier<double?>(null);

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
    _infoTop.dispose();
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

  void _measure(Duration _) {
    if (!mounted) return;
    final box = _infoKey.currentContext?.findRenderObject() as RenderBox?;
    final me = context.findRenderObject() as RenderBox?;
    if (box == null || me == null || !box.hasSize) return;
    _infoTop.value = me.globalToLocal(box.localToGlobal(Offset.zero)).dy;
  }

  /// Over a bright cover the glow alone can't keep text readable (1.3:1 on a cyan cover on Android 11):
  /// the page colour under the top buttons, and from just above the title down.
  Widget _scrims() => ValueListenableBuilder(
    valueListenable: _infoTop,
    builder: (context, top, _) => Stack(
      children: [
        Positioned(
          left: 0,
          right: 0,
          top: 0,
          height: 120 + MediaQuery.paddingOf(context).top,
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [C.veil(0.6), C.veil(0.6), C.veil(0)],
                stops: const [0, 0.6, 1],
              ),
            ),
          ),
        ),
        if (top != null)
          Positioned(
            left: 0,
            right: 0,
            top: top - S.x10,
            bottom: 0,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [C.veil(0), C.veil(0.85), C.veil(0.85)],
                    stops: [0, (S.x10 / max(S.x10, MediaQuery.sizeOf(context).height - top + S.x10)).clamp(0.0, 1.0), 1],
                  ),
                ),
              ),
            ),
          ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([engine, lib, discStyle]),
    builder: (context, _) {
      final t = engine.current;
      final phone = phoneLayout(context); // the phone has no player bar: the sleep timer lives here
      if (phone) WidgetsBinding.instance.addPostFrameCallback(_measure);
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
            if (phone) Positioned.fill(child: _scrims()),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(S.x6, S.x2, S.x6, S.x6),
                child: Column(
                  children: [
                    if (phone)
                      // Close and one menu: the rest is in thumb reach under the controls.
                      Row(
                        children: [
                          _GlassBtn(LucideIcons.chevronDown, 'Close', () => nav.setNowPlaying(false)),
                          const Spacer(),
                          if (t != null)
                            Builder(
                              builder: (b) => _GlassBtn(
                                LucideIcons.ellipsisVertical,
                                'More',
                                () => nowPlayingCoverMenu(b, Offset.zero, t),
                                key: const ValueKey('np.more'),
                              ),
                            ),
                        ],
                      )
                    else
                      Row(
                        children: [
                          _GlassBtn(LucideIcons.chevronDown, 'Close  (Esc)', () => nav.setNowPlaying(false)),
                          const Spacer(),
                          if (_hasLyrics)
                            _GlassBtn(
                              LucideIcons.micVocal,
                              _showLyrics ? 'Hide lyrics' : 'Show lyrics',
                              () => MediaQuery.sizeOf(context).width < 880
                                  ? nav.toggleLyrics()
                                  : setState(() => nav.memo['np.lyrics'] = !_showLyrics),
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
                    if (phone && sleepOn)
                      Padding(
                        padding: const EdgeInsets.only(top: S.x2),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(LucideIcons.moon, size: 14, color: C.text),
                            const SizedBox(width: S.x1),
                            Text(sleepTip(context), style: T.caption.copyWith(color: C.text)),
                          ],
                        ),
                      ),
                    Expanded(
                      child: t == null
                          ? EmptyState(icon: LucideIcons.music, title: 'Nothing playing', body: '$tapWord any song to play it.')
                          : LayoutBuilder(
                              builder: (context, c) {
                                final side = !phone && _hasLyrics && _showLyrics && c.maxWidth >= 880;
                                final player = _Player(
                                  maxW: side ? c.maxWidth * 0.5 : c.maxWidth,
                                  maxH: c.maxHeight,
                                  phone: phone,
                                  infoKey: _infoKey,
                                  lyrics: _phoneLyrics,
                                  onLyrics: () => setState(() => _phoneLyrics = !_phoneLyrics),
                                );
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
/// The phone: Lyrics · Sleep · Queue under the transport, the lyrics in place of the cover, and no
/// app volume (the phone's own buttons set it).
class _Player extends StatelessWidget {
  const _Player({required this.maxW, required this.maxH, this.phone = false, this.infoKey, this.lyrics = false, this.onLyrics});
  final double maxW, maxH;
  final bool phone, lyrics;
  final Key? infoKey;
  final VoidCallback? onLyrics;

  @override
  Widget build(BuildContext context) {
    final t = engine.current!;
    final fav = lib.isFavourite(t.id);
    final style = discStyle.value;
    final wide = DiscView.widthFor(1, style);
    // Leave room under the cover for the text, seek bar and transport (and the phone's button row).
    final below = textHeight(context, [T.title, T.body, T.small, T.caption]) + 250 + (phone ? 40 : 0);
    final size = min(min((maxW - S.x8) / wide, maxH - below), 560.0).clamp(160.0, 560.0);
    // The column is at least wide enough for the controls; the cover keeps its left edge.
    final width = min(max(size * wide, 360.0), maxW);
    // A phone on its side: the disc beside the song and the controls, so nothing needs scrolling.
    final sideways = maxH < 480 && maxW > maxH * 1.5;
    final discSize = sideways ? min(maxH - S.x8, (maxW * 0.45) / wide) : size;
    // Secondary text over the cover's colours: the text colour, a little quieter (dim sinks into a bright glow).
    final quiet = phone ? C.text.withValues(alpha: 0.75) : C.dim;
    final Widget cover = phone && lyrics
        ? SizedBox(width: sideways ? discSize * wide : width, height: discSize, child: const LyricsView(embedded: true))
        : ArtAccentBuilder(
            builder: (context, accent) => DiscView(
              art: lib.artFor(t.albumKey, t.cover),
              id: t.id,
              playing: engine.playing,
              size: discSize,
              style: style,
              glow: accent,
              onCoverMenu: (d) => nowPlayingCoverMenu(context, d.globalPosition, t),
            ),
          );
    final info = <Widget>[
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
                  key: const ValueKey('np.artist'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: T.body.copyWith(color: quiet),
                ),
              ],
            ),
          ),
          // A row, so a star rating can sit beside the heart.
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconBtn(
                fav ? Icons.favorite_rounded : LucideIcons.heart,
                size: 20,
                box: 44,
                color: fav ? C.accent : C.text,
                tooltip: fav ? 'Remove from Favourites' : 'Add to Favourites',
                onTap: () {
                  if (phone) HapticFeedback.selectionClick();
                  lib.toggleFavourite(t.id);
                },
              ),
            ],
          ),
        ],
      ),
      const SizedBox(height: S.x4),
      const SeekBar(big: true),
      const SizedBox(height: S.x2),
      Center(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Transport(big: true, onCover: phone),
        ),
      ),
      const SizedBox(height: S.x3),
      if (phone) ...[
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _RowBtn(LucideIcons.micVocal, 'Lyrics', onLyrics!, active: lyrics),
            _RowBtn(LucideIcons.moon, 'Sleep', () async {
              final v = await phoneSheet(context, sleepChoices(), title: sleepTip(context));
              if (v != null) setSleep(v);
            }, active: sleepOn),
            _RowBtn(LucideIcons.listMusic, 'Queue', () {
              nav.setNowPlaying(false);
              if (!nav.queue) nav.toggleQueue();
            }),
          ],
        ),
        const SizedBox(height: S.x2),
        FormatBadge(t.badge),
      ] else
        Row(
          children: [
            Flexible(child: FormatBadge(t.badge)),
            const Spacer(),
            const SizedBox(width: 168, child: VolumeControl()),
          ],
        ),
    ];
    final infoColumn = Column(key: infoKey, crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: info);
    if (sideways) {
      return Row(
        children: [
          cover,
          const SizedBox(width: S.x8),
          Expanded(child: SingleChildScrollView(child: infoColumn)),
        ],
      );
    }
    return SingleChildScrollView(
      child: SizedBox(
        width: width,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            cover,
            const SizedBox(height: S.x6),
            infoColumn,
          ],
        ),
      ),
    );
  }
}

/// A 48 dp icon-and-word button on the phone's Now Playing (Lyrics · Sleep · Queue); framed when on.
class _RowBtn extends StatelessWidget {
  const _RowBtn(this.icon, this.label, this.onTap, {this.active = false});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool active;
  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: active ? C.glass : Colors.transparent,
      borderRadius: BorderRadius.circular(R.pill),
      border: Border.all(color: active ? C.text.withValues(alpha: 0.4) : Colors.transparent),
    ),
    child: Clickable(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      selected: active,
      selectedColor: Colors.transparent,
      semanticLabel: label,
      radius: R.pill,
      padding: const EdgeInsets.symmetric(horizontal: S.x4),
      child: SizedBox(
        height: 48,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: C.text),
            const SizedBox(width: S.x2),
            Text(label, style: T.label.copyWith(fontWeight: active ? FontWeight.w600 : FontWeight.w500)),
          ],
        ),
      ),
    ),
  );
}

class _GlassBtn extends StatelessWidget {
  const _GlassBtn(this.icon, this.tooltip, this.onTap, {super.key, this.active = false});
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
/// Moving the mouse shows small controls for 2 s (a tap on the phone: 5 s). Esc leaves; F11 fills the screen.
/// The phone centres the disc and names the song under it.
class DiscMode extends StatefulWidget {
  const DiscMode({super.key});
  @override
  State<DiscMode> createState() => _DiscModeState();
}

class _DiscModeState extends State<DiscMode> {
  bool _controls = false;
  Timer? _hide;

  @override
  void initState() {
    super.initState();
    if (isTouch) WidgetsBinding.instance.addPostFrameCallback((_) => _poke()); // shows how to leave
  }

  void _poke() {
    if (!mounted) return;
    _hide?.cancel();
    _hide = Timer(Duration(seconds: isTouch ? 5 : 2), () {
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
      final phone = phoneLayout(context);
      return GestureDetector(
        onTap: _poke,
        child: MouseRegion(
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
                        final size = min(c.maxHeight * (phone ? 0.5 : 0.62), c.maxWidth * (phone ? 0.86 : 0.8) / wide);
                        final disc = DiscView(
                          art: art,
                          id: t!.id,
                          playing: engine.playing,
                          size: size,
                          style: discStyle.value,
                          onCoverMenu: (d) => nowPlayingCoverMenu(context, d.globalPosition, t),
                        );
                        if (phone) {
                          // Centred, with the song under it.
                          return Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              disc,
                              const SizedBox(height: S.x6),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: S.x6),
                                child: Text(
                                  t.title,
                                  maxLines: 2,
                                  textAlign: TextAlign.center,
                                  overflow: TextOverflow.ellipsis,
                                  style: T.heading,
                                ),
                              ),
                              const SizedBox(height: S.x1),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: S.x6),
                                child: Text(
                                  t.artist,
                                  maxLines: 1,
                                  textAlign: TextAlign.center,
                                  overflow: TextOverflow.ellipsis,
                                  style: T.body.copyWith(color: C.text.withValues(alpha: 0.75)),
                                ),
                              ),
                            ],
                          );
                        }
                        return Padding(
                          // Optically centred: the disc side carries less weight than the cover.
                          padding: EdgeInsets.only(left: size * (wide - 1) * 0.15),
                          child: disc,
                        );
                      },
                    ),
                  ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: S.x8 + MediaQuery.paddingOf(context).bottom,
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
                                IconBtn(
                                  LucideIcons.skipBack,
                                  color: C.text,
                                  tooltip: 'Previous',
                                  onTap: t == null ? null : engine.previous,
                                ),
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
        ),
      );
    },
  );
}

Future<void> toggleFullScreen() async => windowManager.setFullScreen(!await windowManager.isFullScreen());
