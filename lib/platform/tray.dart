import 'package:flutter/foundation.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import '../audio/engine.dart';
import '../library/library.dart';
import 'window.dart';

/// Extra tray menu entries from other features (e.g. "Mini player" / "Full window"), shown
/// above Show / Quit. Add them before [setupTray] runs; call [trayMenu] again when a label changes.
final trayItems = <(String Function() label, VoidCallback onClick)>[];

/// Settings → Window: closing the window hides it to the tray instead of quitting. Off by default.
bool closeToTray(Library lib) => lib.setting('closeToTray') == '1';

bool _quitting = false;
late Engine _engine;

/// The tray icon: click shows Gleo; right-click has Previous, Play/Pause, Next, Show and Quit.
/// Its tooltip is the song playing.
Future<void> setupTray(Library lib, Engine engine) async {
  if (!isDesktop) return;
  _engine = engine;
  hideOnClose = () => !_quitting && closeToTray(lib);
  await trayManager.setIcon('assets/brand/gleo.ico');
  trayManager.addListener(_Tray());
  String? tip;
  bool? playing;
  Future<void> update() async {
    final t = engine.current;
    final next = t == null ? 'Gleo' : '${t.title} · ${t.artist}';
    // Windows cuts tray tooltips at 127 characters.
    if (next != tip) await trayManager.setToolTip((tip = next).length > 127 ? '${next.substring(0, 126)}…' : next);
    if (engine.playing != playing) {
      playing = engine.playing;
      await trayMenu();
    }
  }

  engine.addListener(update);
  await update();
}

/// (Re)builds the tray menu.
Future<void> trayMenu() => trayManager.setContextMenu(
  Menu(
    items: [
      MenuItem(key: 'previous', label: 'Previous'),
      MenuItem(key: 'play', label: _engine.playing ? 'Pause' : 'Play'),
      MenuItem(key: 'next', label: 'Next'),
      MenuItem.separator(),
      for (final (i, (label, _)) in trayItems.indexed) MenuItem(key: 'extra$i', label: label()),
      MenuItem(key: 'show', label: 'Show Gleo'),
      MenuItem(key: 'quit', label: 'Quit'),
    ],
  ),
);

/// What a tray menu entry does (also called by the integration test).
Future<void> trayAction(String key) async {
  switch (key) {
    case 'play':
      await _engine.togglePlay();
    case 'next':
      await _engine.next();
    case 'previous':
      await _engine.previous();
    case 'show':
      await showWindow();
    case 'quit':
      _quitting = true;
      await windowManager.close(); // saves the queue and stops audio as usual
    default:
      if (key.startsWith('extra')) trayItems[int.parse(key.substring(5))].$2();
  }
}

Future<void> showWindow() async {
  await windowManager.show();
  if (await windowManager.isMinimized()) await windowManager.restore();
  await windowManager.focus();
}

class _Tray with TrayListener {
  @override
  void onTrayIconMouseDown() => showWindow();
  @override
  void onTrayIconRightMouseDown() => trayManager.popUpContextMenu();
  @override
  void onTrayMenuItemClick(MenuItem item) => trayAction(item.key ?? '');
}
