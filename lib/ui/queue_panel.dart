import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../audio/queue.dart';
import 'app.dart';
import 'theme.dart';
import 'widgets.dart';

/// The play queue: now playing, then what comes next (drag to reorder).
class QueuePanel extends StatelessWidget {
  const QueuePanel({super.key});
  @override
  Widget build(BuildContext context) => Panel(
    child: ListenableBuilder(
      listenable: Listenable.merge([engine, lib]),
      builder: (context, _) {
        final q = engine.queue;
        final cur = q.current;
        final upcoming = q.upcoming;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(S.x5, S.x4, S.x2, S.x2),
              child: Row(
                children: [
                  Expanded(child: Text('Queue', style: T.heading)),
                  Text(q.shuffle ? 'Shuffled' : '', style: T.caption),
                  IconBtn(LucideIcons.x, size: 16, tooltip: 'Close', onTap: nav.toggleQueue),
                ],
              ),
            ),
            if (cur == null)
              const Expanded(
                child: EmptyState(
                  icon: LucideIcons.listMusic,
                  title: 'The queue is empty',
                  body: 'Double-click a song, or right-click it and choose Play next or Add to queue.',
                ),
              )
            else ...[
              _label('Now playing'),
              _entry(context, cur, q.index, current: true),
              _label(upcoming.isEmpty ? 'Nothing after this' : 'Next up · ${plural(upcoming.length, 'song')}'),
              Expanded(
                child: ReorderableListView.builder(
                  buildDefaultDragHandles: false,
                  padding: const EdgeInsets.fromLTRB(S.x2, 0, S.x2, S.x2),
                  itemCount: upcoming.length,
                  proxyDecorator: (child, _, _) => Material(
                    color: Colors.transparent,
                    child: Container(
                      decoration: BoxDecoration(color: C.raised3, borderRadius: BorderRadius.circular(R.small + 2)),
                      child: child,
                    ),
                  ),
                  onReorderItem: (from, to) {
                    engine.moveInQueue(q.index + 1 + from, q.index + 1 + to);
                  },
                  itemBuilder: (_, i) => KeyedSubtree(
                    key: ValueKey(upcoming[i].uid),
                    child: _entry(context, upcoming[i], q.index + 1 + i, dragIndex: i),
                  ),
                ),
              ),
            ],
          ],
        );
      },
    ),
  );

  Widget _label(String s) => Padding(
    padding: const EdgeInsets.fromLTRB(S.x5, S.x3, S.x5, S.x2),
    child: Text(s, style: T.caption),
  );

  Widget _entry(BuildContext context, Entry e, int index, {bool current = false, int? dragIndex}) {
    final t = lib.byId[e.trackId];
    if (t == null) return const SizedBox.shrink();
    final row = Clickable(
      onDoubleTap: current ? null : () => engine.jump(index),
      onTap: () {},
      selected: current,
      radius: R.small + 2,
      padding: const EdgeInsets.symmetric(horizontal: S.x2),
      child: SizedBox(
        height: 52,
        child: Row(
          children: [
            if (dragIndex != null)
              ReorderableDragStartListener(
                index: dragIndex,
                child: const MouseRegion(
                  cursor: SystemMouseCursors.grab,
                  child: Padding(
                    padding: EdgeInsets.only(right: S.x1),
                    child: Icon(LucideIcons.gripVertical, size: 14, color: C.faint),
                  ),
                ),
              ),
            CoverArt(t.cover, size: 36, radius: R.small - 2),
            const SizedBox(width: S.x3),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    t.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: T.label.copyWith(color: current ? C.accent : C.text),
                  ),
                  Text(t.artist, maxLines: 1, overflow: TextOverflow.ellipsis, style: T.small),
                ],
              ),
            ),
            if (current)
              Padding(
                padding: const EdgeInsets.only(right: S.x2),
                child: PlayingBars(playing: engine.playing),
              )
            else
              IconBtn(
                LucideIcons.x,
                size: 14,
                box: 28,
                color: C.faint,
                tooltip: 'Remove from queue',
                onTap: () => engine.removeFromQueue(index),
              ),
          ],
        ),
      ),
    );
    return current
        ? Padding(
            padding: const EdgeInsets.symmetric(horizontal: S.x2),
            child: row,
          )
        : Tooltip(message: 'Double-click to play now', waitDuration: const Duration(seconds: 1), child: row);
  }
}
