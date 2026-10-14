import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../audio/engine.dart';
import '../audio/queue.dart';
import 'app.dart';
import 'theme.dart';
import 'widgets.dart';

class PlayerBar extends StatefulWidget {
  const PlayerBar({super.key});
  @override
  State<PlayerBar> createState() => _PlayerBarState();
}

class _PlayerBarState extends State<PlayerBar> {
  StreamSubscription<String>? _messages;

  @override
  void initState() {
    super.initState();
    // The engine's messages (a song can't be played, the device is gone, ...) as toasts.
    _messages = engine.messages.listen((m) {
      if (mounted) toast(context, m);
    });
  }

  @override
  void dispose() {
    _messages?.cancel();
    super.dispose();
  }

  String _sleepTip() {
    final at = engine.sleepAt;
    if (at != null) return 'Sleep timer: pauses at ${TimeOfDay.fromDateTime(at).format(context)}';
    return switch (engine.stopAfter) {
      StopAfter.song => 'Stops after this song',
      StopAfter.queue => 'Stops at the end of the queue',
      StopAfter.none => 'Sleep timer',
    };
  }

  Future<void> _sleepMenu(BuildContext b) async {
    final box = b.findRenderObject()! as RenderBox;
    final at = box.localToGlobal(Offset.zero);
    final on = engine.sleepAt != null || engine.stopAfter != StopAfter.none;
    PopupMenuItem<int> item(int v, String label) => PopupMenuItem(value: v, height: 36, child: Text(label, style: T.label));
    final v = await showMenu<int>(
      context: context,
      position: RelativeRect.fromLTRB(at.dx, at.dy - 8, at.dx + box.size.width, at.dy),
      items: [
        for (final m in [15, 30, 45, 60]) item(m, '$m minutes'),
        item(-1, 'End of this song'),
        item(-2, 'End of the queue'),
        if (on) ...[const PopupMenuDivider(height: 8), item(0, 'Turn off')],
      ],
    );
    if (v == null) return;
    engine.sleepIn(v > 0 ? Duration(minutes: v) : null);
    engine.setStopAfter(switch (v) {
      -1 => StopAfter.song,
      -2 => StopAfter.queue,
      _ => StopAfter.none,
    });
  }

  @override
  Widget build(BuildContext context) => Panel(
    padding: const EdgeInsets.symmetric(horizontal: S.x4, vertical: S.x3),
    child: ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 72),
      child: ListenableBuilder(
        listenable: Listenable.merge([engine, lib, nav]),
        builder: (context, _) => LayoutBuilder(
          builder: (context, c) {
            // The sides share what the transport leaves, up to 300 px each.
            final side = ((c.maxWidth - 380) / 2).clamp(150.0, 300.0);
            return Row(
              children: [
                SizedBox(width: side, child: const _NowPlayingInfo()),
                Expanded(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 620),
                      child: const Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Transport(),
                          SizedBox(height: S.x1),
                          SeekBar(),
                        ],
                      ),
                    ),
                  ),
                ),
                SizedBox(
                  width: side,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      IconBtn(LucideIcons.micVocal, size: 18, active: nav.lyrics, tooltip: 'Lyrics  (Ctrl+L)', onTap: nav.toggleLyrics),
                      IconBtn(LucideIcons.listMusic, size: 18, active: nav.queue, tooltip: 'Queue', onTap: nav.toggleQueue),
                      Builder(
                        builder: (b) => IconBtn(
                          LucideIcons.moon,
                          size: 18,
                          active: engine.sleepAt != null || engine.stopAfter != StopAfter.none,
                          tooltip: _sleepTip(),
                          onTap: () => _sleepMenu(b),
                        ),
                      ),
                      const SizedBox(width: S.x1),
                      const Flexible(child: VolumeControl()),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    ),
  );
}

/// Cover (opens Now Playing), title (goes to the album) and artist.
class _NowPlayingInfo extends StatefulWidget {
  const _NowPlayingInfo();
  @override
  State<_NowPlayingInfo> createState() => _NowPlayingInfoState();
}

class _NowPlayingInfoState extends State<_NowPlayingInfo> {
  bool _hover = false;
  @override
  Widget build(BuildContext context) => ListenableBuilder(listenable: Listenable.merge([engine, lib]), builder: (context, _) => _build());

  Widget _build() {
    final t = engine.current;
    if (t == null) {
      return Row(
        children: [
          const CoverArt(null, size: 56),
          const SizedBox(width: S.x3),
          Flexible(
            child: Text('Nothing playing', style: T.small.copyWith(color: C.faint), maxLines: 1),
          ),
        ],
      );
    }
    final fav = lib.isFavourite(t.id);
    return Row(
      children: [
        Clickable(
          onTap: () => nav.setNowPlaying(true),
          onHover: (v) => setState(() => _hover = v),
          tooltip: 'Now Playing',
          radius: R.cover,
          child: Stack(
            alignment: Alignment.center,
            children: [
              CoverArt.track(t, size: 56),
              AnimatedOpacity(
                opacity: _hover ? 1 : 0,
                duration: Motion.fast,
                child: Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(color: C.scrim, borderRadius: BorderRadius.circular(R.cover)),
                  child: const Icon(LucideIcons.chevronUp, size: 20, color: C.text),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: S.x3),
        Expanded(
          child: Tooltip(
            message: '${t.title}\n${t.artist} · ${t.album}',
            waitDuration: const Duration(milliseconds: 700),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Link(t.title, T.label, () => nav.push('album', t.albumKey)),
                _Link(t.artist, T.small, () => nav.push('artist', t.artist)),
                const SizedBox(height: S.x1),
                Tooltip(
                  message: engine.outputFormat.isEmpty
                      ? 'File format'
                      : 'Output: ${engine.outputFormat}${engine.exclusive ? ' · exclusive' : ''}'
                            '${engine.exclusive && (engine.muted || engine.volume < 100) ? ' · not bit-perfect below 100 % volume' : ''}',
                  child: FormatBadge(t.badge),
                ),
              ],
            ),
          ),
        ),
        IconBtn(
          fav ? Icons.favorite_rounded : LucideIcons.heart,
          color: fav ? C.accent : C.dim,
          tooltip: fav ? 'Remove from Favourites' : 'Add to Favourites',
          onTap: () => lib.toggleFavourite(t.id),
        ),
      ],
    );
  }
}

/// Text that underlines on hover and navigates on click.
class _Link extends StatefulWidget {
  const _Link(this.text, this.style, this.onTap);
  final String text;
  final TextStyle style;
  final VoidCallback onTap;
  @override
  State<_Link> createState() => _LinkState();
}

class _LinkState extends State<_Link> {
  bool _hover = false;
  @override
  Widget build(BuildContext context) => MouseRegion(
    cursor: SystemMouseCursors.click,
    onEnter: (_) => setState(() => _hover = true),
    onExit: (_) => setState(() => _hover = false),
    child: GestureDetector(
      onTap: widget.onTap,
      child: Text(
        widget.text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: widget.style.copyWith(decoration: _hover ? TextDecoration.underline : null, decorationColor: widget.style.color),
      ),
    ),
  );
}

/// Shuffle, previous, play/pause, next, repeat.
class Transport extends StatelessWidget {
  const Transport({super.key, this.big = false});
  final bool big;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: engine,
    builder: (context, _) {
      final has = engine.current != null;
      final q = engine.queue;
      final gap = SizedBox(width: big ? S.x4 : S.x2);
      return Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          IconBtn(
            LucideIcons.shuffle,
            size: big ? 18 : 16,
            box: big ? 44 : 36,
            active: q.shuffle,
            color: big ? C.text : C.dim,
            tooltip: q.shuffle ? 'Shuffle on' : 'Shuffle',
            onTap: has ? () => engine.setShuffle(!q.shuffle) : null,
          ),
          gap,
          IconBtn(
            LucideIcons.skipBack,
            size: big ? 22 : 18,
            box: big ? 44 : 36,
            color: big ? C.text : C.dim,
            tooltip: 'Previous  (Ctrl+←)',
            onTap: has ? engine.previous : null,
          ),
          gap,
          _PlayButton(playing: engine.playing, size: big ? 64 : 40, onTap: has ? engine.togglePlay : null),
          gap,
          IconBtn(
            LucideIcons.skipForward,
            size: big ? 22 : 18,
            box: big ? 44 : 36,
            color: big ? C.text : C.dim,
            tooltip: 'Next  (Ctrl+→)',
            onTap: has ? engine.next : null,
          ),
          gap,
          IconBtn(
            q.repeat == Repeat.one ? LucideIcons.repeat1 : LucideIcons.repeat,
            size: big ? 18 : 16,
            box: big ? 44 : 36,
            color: big ? C.text : C.dim,
            active: q.repeat != Repeat.off,
            tooltip: switch (q.repeat) {
              Repeat.off => 'Repeat off',
              Repeat.all => 'Repeat all',
              Repeat.one => 'Repeat one',
            },
            onTap: has ? engine.cycleRepeat : null,
          ),
        ],
      );
    },
  );
}

/// Mute + volume slider. The mouse wheel changes the volume anywhere over it.
class VolumeControl extends StatelessWidget {
  const VolumeControl({super.key});

  void _wheel(PointerSignalEvent e) {
    if (e is! PointerScrollEvent || e.scrollDelta.dy == 0) return;
    if (engine.muted) engine.toggleMute();
    engine.setVolume(engine.volume + (e.scrollDelta.dy < 0 ? 5 : -5));
    engine.saveVolume();
  }

  @override
  Widget build(BuildContext context) => Listener(
    onPointerSignal: _wheel,
    child: ListenableBuilder(
      listenable: engine,
      builder: (context, _) => Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          IconBtn(
            engine.muted || engine.volume == 0 ? LucideIcons.volumeX : (engine.volume < 50 ? LucideIcons.volume1 : LucideIcons.volume2),
            size: 18,
            tooltip: engine.muted ? 'Unmute' : 'Mute',
            onTap: engine.toggleMute,
          ),
          Flexible(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 104),
              child: Semantics(
                label: 'Volume',
                child: Slider(
                  value: engine.muted ? 0 : engine.volume,
                  max: 100,
                  onChanged: (v) {
                    if (engine.muted) engine.toggleMute();
                    engine.setVolume(v);
                  },
                  onChangeEnd: (_) => engine.saveVolume(),
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _PlayButton extends StatelessWidget {
  const _PlayButton({required this.playing, this.onTap, this.size = 40});
  final bool playing;
  final double size;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(color: onTap == null ? C.raised3 : C.text, shape: BoxShape.circle),
    child: Clickable(
      onTap: onTap,
      tooltip: playing ? 'Pause  (Space)' : 'Play  (Space)',
      semanticLabel: playing ? 'Pause' : 'Play',
      radius: R.pill,
      hover: const Color(0x22000000),
      pressed: const Color(0x44000000),
      child: SizedBox(
        width: size,
        height: size,
        child: AnimatedSwitcher(
          duration: Motion.fast,
          child: Icon(
            playing ? LucideIcons.pause : LucideIcons.play,
            key: ValueKey(playing),
            size: size * 0.45,
            color: onTap == null ? C.faint : C.onLight,
          ),
        ),
      ),
    ),
  );
}

/// Times + a seek slider. Hovering shows the time under the pointer. Only this
/// rebuilds as the position moves.
class SeekBar extends StatefulWidget {
  const SeekBar({super.key, this.big = false});

  /// Now Playing: a thicker bar with the times underneath.
  final bool big;
  @override
  State<SeekBar> createState() => _SeekBarState();
}

class _SeekBarState extends State<SeekBar> {
  double? _drag, _hoverX;
  static const _pad = 10.0; // the slider's track inset (its overlay radius)

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: engine.position,
    builder: (context, pos, _) {
      final total = engine.duration.inMilliseconds.toDouble();
      final value = (_drag ?? pos.inMilliseconds.toDouble()).clamp(0.0, total <= 0 ? 0.0 : total);
      final style = (widget.big ? T.small : T.caption).copyWith(color: C.dim, fontFeatures: T.tabular);
      final active = _hoverX != null || _drag != null;
      final slider = LayoutBuilder(
        builder: (context, c) {
          final w = c.maxWidth;
          Duration at(double x) => Duration(milliseconds: (((x - _pad) / (w - _pad * 2)).clamp(0.0, 1.0) * total).round());
          return MouseRegion(
            onHover: (e) => setState(() => _hoverX = e.localPosition.dx),
            onExit: (_) => setState(() => _hoverX = null),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: widget.big ? 6 : 4,
                    activeTrackColor: active ? C.accent : C.text,
                    thumbShape: RoundSliderThumbShape(
                      enabledThumbRadius: active ? (widget.big ? 8 : 6) : 0,
                      elevation: 0,
                      pressedElevation: 0,
                    ),
                  ),
                  child: Semantics(
                    label: 'Seek',
                    child: Slider(
                      value: value,
                      max: total <= 0 ? 1 : total,
                      onChanged: total <= 0 ? null : (v) => setState(() => _drag = v),
                      onChangeEnd: (v) {
                        engine.seek(Duration(milliseconds: v.round()));
                        setState(() => _drag = null);
                      },
                    ),
                  ),
                ),
                if (_hoverX != null && total > 0)
                  Positioned(
                    left: (_hoverX! - 28).clamp(0.0, w - 56),
                    top: -S.x6,
                    width: 56,
                    child: IgnorePointer(
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        decoration: BoxDecoration(
                          color: C.raised3,
                          borderRadius: BorderRadius.circular(R.tiny),
                          border: Border.all(color: C.borderStrong),
                        ),
                        child: Text(
                          fmtTime(at(_hoverX!)),
                          textAlign: TextAlign.center,
                          style: T.caption.copyWith(color: C.text, fontFeatures: T.tabular),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      );
      final now = Text(fmtTime(Duration(milliseconds: value.round())), style: style);
      final end = Text(fmtTime(engine.duration), style: style);
      if (widget.big) {
        return Column(
          children: [
            slider,
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: _pad),
              child: Row(children: [now, const Spacer(), end]),
            ),
          ],
        );
      }
      return Row(
        children: [
          SizedBox(
            width: 48,
            child: Align(alignment: Alignment.centerRight, child: now),
          ),
          Expanded(child: slider),
          SizedBox(width: 48, child: end),
        ],
      );
    },
  );
}
