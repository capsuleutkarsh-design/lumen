import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:window_manager/window_manager.dart';

import '../library/library.dart';

bool get isDesktop => Platform.isWindows || Platform.isLinux || Platform.isMacOS;

/// Frameless window that remembers its size and position.
/// [onClose] runs before the window closes (to save the queue and stop audio).
Future<void> setupWindow(Library lib, Future<void> Function() onClose) async {
  if (!isDesktop) return;
  await windowManager.ensureInitialized();
  final saved = lib.setting('window');
  final b = saved == null ? null : (jsonDecode(saved) as List).cast<num>();
  await windowManager.waitUntilReadyToShow(
    WindowOptions(
      size: b == null ? const Size(1360, 860) : Size(b[2].toDouble(), b[3].toDouble()),
      minimumSize: const Size(960, 640),
      center: b == null,
      backgroundColor: const Color(0xFF000000),
      titleBarStyle: TitleBarStyle.hidden,
      title: 'Music Player',
    ),
    () async {
      if (b != null) await windowManager.setPosition(Offset(b[0].toDouble(), b[1].toDouble()));
      if (b != null && b.length > 4 && b[4] == 1) await windowManager.maximize();
      await windowManager.show();
      await windowManager.focus();
    },
  );
  await windowManager.setPreventClose(true);
  windowManager.addListener(_Saver(lib, onClose));
}

Future<void> minimizeWindow() => windowManager.minimize();
Future<void> toggleMaximize() async => await windowManager.isMaximized() ? windowManager.unmaximize() : windowManager.maximize();
Future<void> closeWindow() => windowManager.close();
Widget dragArea(Widget child) => isDesktop ? DragToMoveArea(child: child) : child;

class _Saver with WindowListener {
  _Saver(this.lib, this.onClose);
  final Library lib;
  final Future<void> Function() onClose;
  Timer? _t;
  void _save() {
    _t?.cancel();
    _t = Timer(const Duration(milliseconds: 400), () async {
      final max = await windowManager.isMaximized();
      final current = lib.setting('window');
      if (max && current != null) {
        // Keep the normal size for when the window is restored.
        final b = (jsonDecode(current) as List).cast<num>();
        lib.setSetting('window', jsonEncode([...b.take(4), 1]));
        return;
      }
      final r = await windowManager.getBounds();
      lib.setSetting('window', jsonEncode([r.left, r.top, r.width, r.height, 0]));
    });
  }

  @override
  Future<void> onWindowClose() async {
    await onClose();
    await windowManager.destroy();
  }

  @override
  void onWindowResized() => _save();
  @override
  void onWindowMoved() => _save();
  @override
  void onWindowMaximize() => _save();
  @override
  void onWindowUnmaximize() => _save();
}
