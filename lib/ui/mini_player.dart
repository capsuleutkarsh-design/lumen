// The mini player: the main window made small and always on top (not a second
// window or process, so single-instance keeps working).
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:window_manager/window_manager.dart';

import '../platform/window.dart';
import 'app.dart';
import 'disc.dart';
import 'player_bar.dart' show PlayButton;
import 'theme.dart';
import 'widgets.dart';

const _compact = Size(320, 120), _expanded = Size(320, 360);
bool _wasMaximised = false;

/// Turns the window into the mini player and back.
Future<void> setMini(bool on) async {
  if (on == nav.mini) return;
  if (!isDesktop) return nav.setMini(on);
  if (on) {
    if (await windowManager.isFullScreen()) await windowManager.setFullScreen(false);
    _wasMaximised = await windowManager.isMaximized();
    if (_wasMaximised) await windowManager.unmaximize();
    miniWindow = true;
    nav.setMini(true);
    await windowManager.setMinimumSize(const Size(200, 80));
    await windowManager.setResizable(false);
    await windowManager.setAlwaysOnTop(true);
    await _setClientSize(nav.miniExpanded ? _expanded : _compact);
    // Where it was last time, if that is still on a display; else the bottom right corner.
    final saved = (jsonDecode(lib.setting('mini') ?? 'null') as List?)?.cast<num>();
    final size = (await windowManager.getSize()) * windowRatio;
    final areas = await workAreas();
    final back = saved == null ? null : restorableBounds([...saved.take(2), size.width, size.height], areas, minWidth: 0, minHeight: 0);
    if (back != null) {
      await windowManager.setPosition(back.topLeft / windowRatio);
    } else {
      await _fit(corner: true);
    }
  } else {
    if (!await windowManager.isMinimized()) {
      final at = await windowManager.getPosition() * windowRatio;
      lib.setSetting('mini', jsonEncode([at.dx.round(), at.dy.round()]));
    }
    await windowManager.setAlwaysOnTop(false);
    await windowManager.setResizable(true);
    await windowManager.setMinimumSize(const Size(960, 640));
    miniWindow = false;
    final saved = (jsonDecode(lib.setting('window') ?? 'null') as List?)?.cast<num>();
    final b = saved == null ? null : restorableBounds(saved, await workAreas());
    if (b != null) {
      await windowManager.setBounds(
        Rect.fromLTWH(b.left / windowRatio, b.top / windowRatio, b.width / windowRatio, b.height / windowRatio),
      );
    } else {
      await windowManager.setSize(const Size(1360, 860));
      await windowManager.center();
    }
    if (_wasMaximised) await windowManager.maximize();
    nav.setMini(false);
  }
}

/// The compact strip or the bigger square.
Future<void> setMiniExpanded(bool v) async {
  nav.setMini(true, expanded: v);
  if (!isDesktop) return;
  await _setClientSize(v ? _expanded : _compact);
  await _fit();
}

/// Sizes the window so its inside is [size] (the frameless window still has resize borders).
Future<void> _setClientSize(Size size) async {
  final view = WidgetsBinding.instance.platformDispatcher.views.first;
  final inside = view.physicalSize / view.devicePixelRatio;
  final outside = await windowManager.getSize();
  await windowManager.setSize(size + Offset(outside.width - inside.width, outside.height - inside.height));
}

/// Keeps the window inside the work area of the display it is on ([corner]: its bottom right).
Future<void> _fit({bool corner = false}) async {
  final r = windowRatio;
  final b = await windowManager.getBounds();
  final px = Rect.fromLTWH(b.left * r, b.top * r, b.width * r, b.height * r);
  final areas = await workAreas();
  if (areas.isEmpty) return;
  final area = areas.firstWhere((a) => a.contains(px.center), orElse: () => areas.first);
  final margin = 24 * r;
  final x = corner ? area.right - px.width - margin : px.left.clamp(area.left, area.right - px.width);
  final y = corner ? area.bottom - px.height - margin : px.top.clamp(area.top, area.bottom - px.height);
  await windowManager.setPosition(Offset(x / r, y / r));
}

/// Cover, spinning disc, title, play/pause/next and a seek line. Drag anywhere to move it;
/// click the cover to go back to the full window.
class MiniPlayer extends StatelessWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context) => Material(
    color: C.raised1,
    child: ListenableBuilder(
      listenable: Listenable.merge([engine, lib, nav, discStyle]),
      builder: (context, _) {
        final t = engine.current;
        final big = nav.miniExpanded;
        final art = t == null ? null : lib.artFor(t.albumKey, t.cover);
        final hero = art == null
            ? CoverArt(null, size: big ? 168 : 88)
            : DiscView(art: art, playing: engine.playing, size: big ? 168 : 88, style: discStyle.value, onCoverTap: () => setMini(false));
        final title = Text(t?.title ?? 'Nothing playing', maxLines: 1, overflow: TextOverflow.ellipsis, style: T.label);
        final artist = Text(t?.artist ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: T.caption);
        final buttons = [
          IconBtn(
            big ? LucideIcons.minimize2 : LucideIcons.maximize2,
            size: 14,
            box: 28,
            tooltip: big ? 'Smaller' : 'Bigger',
            onTap: () => setMiniExpanded(!big),
          ),
          IconBtn(LucideIcons.appWindow, size: 14, box: 28, tooltip: 'Full window', onTap: () => setMini(false)),
        ];
        final transport = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconBtn(LucideIcons.skipBack, size: 16, box: 32, color: C.text, tooltip: 'Previous', onTap: t == null ? null : engine.previous),
            const SizedBox(width: S.x1),
            PlayButton(playing: engine.playing, size: 32, onTap: t == null ? null : engine.togglePlay),
            const SizedBox(width: S.x1),
            IconBtn(LucideIcons.skipForward, size: 16, box: 32, color: C.text, tooltip: 'Next', onTap: t == null ? null : engine.next),
          ],
        );
        final body = big
            ? Column(
                children: [
                  Row(mainAxisAlignment: MainAxisAlignment.end, children: buttons),
                  Expanded(child: Center(child: hero)),
                  const SizedBox(height: S.x3),
                  title,
                  artist,
                  const SizedBox(height: S.x2),
                  transport,
                ],
              )
            : Row(
                children: [
                  hero,
                  const SizedBox(width: S.x3),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(child: title),
                            ...buttons,
                          ],
                        ),
                        artist,
                        const Spacer(),
                        transport,
                      ],
                    ),
                  ),
                ],
              );
        return Stack(
          children: [
            Positioned.fill(
              child: dragArea(Padding(padding: EdgeInsets.fromLTRB(S.x3, S.x2, S.x2, S.x3 + (big ? S.x2 : 0)), child: body)),
            ),
            const Positioned(left: 0, right: 0, bottom: 0, child: _SeekLine()),
          ],
        );
      },
    ),
  );
}

/// A thin progress line; click it to seek.
class _SeekLine extends StatelessWidget {
  const _SeekLine();
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, c) => GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapUp: (d) {
        final total = engine.duration;
        if (total > Duration.zero) engine.seek(total * (d.localPosition.dx / c.maxWidth).clamp(0.0, 1.0));
      },
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: SizedBox(
          height: 8,
          child: Align(
            alignment: Alignment.bottomLeft,
            child: ValueListenableBuilder(
              valueListenable: engine.position,
              builder: (_, pos, _) {
                final total = engine.duration.inMilliseconds;
                return FractionallySizedBox(
                  widthFactor: total <= 0 ? 0 : (pos.inMilliseconds / total).clamp(0.0, 1.0),
                  child: Container(height: 2, color: C.text.withValues(alpha: 0.6)),
                );
              },
            ),
          ),
        ),
      ),
    ),
  );
}
