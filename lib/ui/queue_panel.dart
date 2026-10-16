import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../audio/queue.dart';
import '../platform/window.dart' show isTouch;
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
                  Text([if (q.items.isNotEmpty) plural(q.items.length, 'song'), if (q.shuffle) 'shuffled'].join(' · '), style: T.caption),
                  if (upcoming.isNotEmpty) ...[
                    const SizedBox(width: S.x2),
                    PillButton('Clear', dense: true, onTap: () => _clear(context, upcoming.length)),
                  ],
                  if (cur != null) IconBtn(LucideIcons.listPlus, size: 16, tooltip: 'Save as playlist', onTap: () => _save(context)),
                  IconBtn(LucideIcons.x, size: 16, tooltip: 'Close', onTap: nav.toggleQueue),
                ],
              ),
            ),
            if (cur == null)
              Expanded(
                child: EmptyState(
                  icon: LucideIcons.listMusic,
                  title: 'The queue is empty',
                  body: '$tapWord a song, or $menuWord it and choose Play next or Add to queue.',
                ),
              )
            else ...[
              _label('Now playing'),
              _entry(context, cur, current: true),
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
                  // Positions are looked up at drop time: the queue may have moved on since this was drawn.
                  onReorderItem: (from, to) {
                    final i = q.items.indexOf(upcoming[from]);
                    final j = q.items.indexOf(upcoming[to]);
                    if (i > q.index && j > q.index) engine.moveInQueue(i, j);
                  },
                  itemBuilder: (_, i) => isTouch
                      // Touch: swipe a song away to take it out of the queue.
                      ? Dismissible(
                          key: ValueKey(upcoming[i].uid),
                          direction: DismissDirection.endToStart,
                          background: Container(
                            alignment: Alignment.centerRight,
                            padding: const EdgeInsets.only(right: S.x5),
                            child: Icon(LucideIcons.trash2, size: 18, color: C.accent),
                          ),
                          onDismissed: (_) => _remove(context, upcoming[i]),
                          child: _entry(context, upcoming[i], dragIndex: i),
                        )
                      : KeyedSubtree(
                          key: ValueKey(upcoming[i].uid),
                          child: _entry(context, upcoming[i], dragIndex: i),
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

  Future<void> _clear(BuildContext context, int n) async {
    await engine.clearQueue();
    if (context.mounted) toast(context, 'Cleared ${plural(n, 'song')}', action: 'Undo', onAction: engine.undoClearQueue);
  }

  Future<void> _save(BuildContext context) async {
    final name = await askText(context, 'Save the queue as a playlist', action: 'Save');
    if (name == null || !context.mounted) return;
    engine.saveQueueAsPlaylist(name);
    toast(context, 'Saved the queue as “$name”');
  }

  void _remove(BuildContext context, Entry e) {
    final t = lib.byId[e.trackId];
    engine.removeFromQueue(engine.queue.items.indexOf(e));
    toast(context, 'Removed “${t?.title ?? 'the song'}”', action: 'Undo', onAction: engine.undoRemove);
  }

  Widget _entry(BuildContext context, Entry e, {bool current = false, int? dragIndex}) {
    final t = lib.byId[e.trackId] ?? (current ? engine.current : null);
    if (t == null) return const SizedBox.shrink();
    final row = Clickable(
      onDoubleTap: current ? null : () => engine.jump(engine.queue.items.indexOf(e)),
      onTap: () {},
      selected: current,
      radius: R.small + 2,
      padding: const EdgeInsets.symmetric(horizontal: S.x2),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 52),
        child: Row(
          children: [
            if (dragIndex != null)
              ReorderableDragStartListener(
                index: dragIndex,
                child: MouseRegion(
                  cursor: SystemMouseCursors.grab,
                  child: Padding(
                    padding: EdgeInsets.only(right: S.x1),
                    child: Icon(LucideIcons.gripVertical, size: 14, color: C.faint),
                  ),
                ),
              ),
            CoverArt.track(t, size: 36, radius: R.tiny + 2),
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
              IconBtn(LucideIcons.x, size: 14, box: 28, color: C.faint, tooltip: 'Remove from queue', onTap: () => _remove(context, e)),
          ],
        ),
      ),
    );
    return current
        ? Padding(
            padding: const EdgeInsets.symmetric(horizontal: S.x2),
            child: row,
          )
        : Tooltip(message: '$tapWord to play now', waitDuration: const Duration(seconds: 1), child: row);
  }
}
