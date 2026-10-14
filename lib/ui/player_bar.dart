import 'dart:async';

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

  @override
  Widget build(BuildContext context) => Panel(
    padding: const EdgeInsets.symmetric(horizontal: S.x4, vertical: S.x3),
    child: SizedBox(
      height: 72,
      child: ListenableBuilder(
        listenable: Listenable.merge([engine, lib, nav]),
        builder: (context, _) {
          final t = engine.current;
          final has = t != null;
          final fav = has && lib.isFavourite(t.id);
          final q = engine.queue;
          return Row(
            children: [
              // Now playing
              SizedBox(
                width: 300,
                child: !has
                    ? Row(
                        children: [
                          const CoverArt(null, size: 56),
                          const SizedBox(width: S.x3),
                          Text('Nothing playing', style: T.small.copyWith(color: C.faint)),
                        ],
                      )
                    : Row(
                        children: [
                          Clickable(
                            onTap: () => nav.push('album', t.albumKey),
                            tooltip: 'Go to album',
                            radius: R.cover,
                            child: CoverArt(t.cover, size: 56),
                          ),
                          const SizedBox(width: S.x3),
                          Expanded(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: T.label),
                                const SizedBox(height: 2),
                                Text(t.artist, maxLines: 1, overflow: TextOverflow.ellipsis, style: T.small),
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
                          IconBtn(
                            fav ? Icons.favorite_rounded : LucideIcons.heart,
                            color: fav ? C.accent : C.dim,
                            tooltip: fav ? 'Remove from Favourites' : 'Add to Favourites',
                            onTap: () => lib.toggleFavourite(t.id),
                          ),
                        ],
                      ),
              ),
              // Transport + seek
              Expanded(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 620),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            IconBtn(
                              LucideIcons.shuffle,
                              size: 16,
                              active: q.shuffle,
                              tooltip: q.shuffle ? 'Shuffle on' : 'Shuffle',
                              onTap: has ? () => engine.setShuffle(!q.shuffle) : null,
                            ),
                            const SizedBox(width: S.x2),
                            IconBtn(LucideIcons.skipBack, tooltip: 'Previous  (Ctrl+←)', onTap: has ? engine.previous : null),
                            const SizedBox(width: S.x2),
                            _PlayButton(playing: engine.playing, onTap: has ? engine.togglePlay : null),
                            const SizedBox(width: S.x2),
                            IconBtn(LucideIcons.skipForward, tooltip: 'Next  (Ctrl+→)', onTap: has ? engine.next : null),
                            const SizedBox(width: S.x2),
                            IconBtn(
                              q.repeat == Repeat.one ? LucideIcons.repeat1 : LucideIcons.repeat,
                              size: 16,
                              active: q.repeat != Repeat.off,
                              tooltip: switch (q.repeat) {
                                Repeat.off => 'Repeat off',
                                Repeat.all => 'Repeat all',
                                Repeat.one => 'Repeat one',
                              },
                              onTap: has ? engine.cycleRepeat : null,
                            ),
                          ],
                        ),
                        const SizedBox(height: S.x1),
                        const SeekBar(),
                      ],
                    ),
                  ),
                ),
              ),
              // Right side
              SizedBox(
                width: 300,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    IconBtn(LucideIcons.micVocal, size: 17, active: nav.lyrics, tooltip: 'Lyrics  (Ctrl+L)', onTap: nav.toggleLyrics),
                    IconBtn(LucideIcons.listMusic, size: 17, active: nav.queue, tooltip: 'Queue', onTap: nav.toggleQueue),
                    Builder(
                      builder: (b) => IconBtn(
                        LucideIcons.moon,
                        size: 17,
                        active: engine.sleepAt != null || engine.stopAfter != StopAfter.none,
                        tooltip: _sleepTip(),
                        onTap: () => _sleepMenu(b),
                      ),
                    ),
                    const SizedBox(width: S.x2),
                    IconBtn(
                      engine.muted || engine.volume == 0
                          ? LucideIcons.volumeX
                          : (engine.volume < 50 ? LucideIcons.volume1 : LucideIcons.volume2),
                      size: 17,
                      tooltip: engine.muted ? 'Unmute' : 'Mute',
                      onTap: engine.toggleMute,
                    ),
                    SizedBox(
                      width: 104,
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
                  ],
                ),
              ),
            ],
          );
        },
      ),
    ),
  );

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
}

class _PlayButton extends StatelessWidget {
  const _PlayButton({required this.playing, this.onTap});
  final bool playing;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(color: onTap == null ? C.raised3 : C.text, shape: BoxShape.circle),
    child: Clickable(
      onTap: onTap,
      tooltip: playing ? 'Pause  (Space)' : 'Play  (Space)',
      radius: R.pill,
      hover: const Color(0x22000000),
      pressed: const Color(0x44000000),
      child: SizedBox(
        width: 40,
        height: 40,
        child: AnimatedSwitcher(
          duration: Motion.fast,
          child: Icon(
            playing ? LucideIcons.pause : LucideIcons.play,
            key: ValueKey(playing),
            size: 18,
            color: onTap == null ? C.faint : Colors.black,
          ),
        ),
      ),
    ),
  );
}

/// Times + a seek slider. Only this rebuilds as the position moves.
class SeekBar extends StatefulWidget {
  const SeekBar({super.key});
  @override
  State<SeekBar> createState() => _SeekBarState();
}

class _SeekBarState extends State<SeekBar> {
  double? _drag;
  bool _hover = false;
  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: engine.position,
    builder: (context, pos, _) {
      final total = engine.duration.inMilliseconds.toDouble();
      final value = (_drag ?? pos.inMilliseconds.toDouble()).clamp(0.0, total <= 0 ? 0.0 : total);
      final style = T.caption.copyWith(color: C.dim, fontFeatures: T.tabular);
      return Row(
        children: [
          SizedBox(
            width: 48,
            child: Text(
              fmtTime(Duration(milliseconds: value.round())),
              textAlign: TextAlign.right,
              style: style,
            ),
          ),
          Expanded(
            child: MouseRegion(
              onEnter: (_) => setState(() => _hover = true),
              onExit: (_) => setState(() => _hover = false),
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  activeTrackColor: _hover || _drag != null ? C.accent : C.text,
                  thumbShape: RoundSliderThumbShape(enabledThumbRadius: _hover || _drag != null ? 6 : 0, elevation: 0, pressedElevation: 0),
                ),
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
          ),
          SizedBox(width: 48, child: Text(fmtTime(engine.duration), style: style)),
        ],
      );
    },
  );
}
