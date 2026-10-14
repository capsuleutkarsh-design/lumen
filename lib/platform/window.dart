import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:window_manager/window_manager.dart';

import '../library/library.dart';

bool get isDesktop => Platform.isWindows || Platform.isLinux || Platform.isMacOS;

/// A touch screen (Android): a tap plays a song, a long press opens its menu, and buttons are finger-sized.
bool get isTouch => Platform.isAndroid || Platform.isIOS;

// The window's normal bounds are saved as [x, y, width, height, maximised] in physical pixels.
// window_manager turns logical into physical pixels with the current devicePixelRatio, so dividing by
// that same ratio right before each call gives exact physical pixels on monitors of any scale.
double get _ratio => windowManager.getDevicePixelRatio();

/// The saved bounds when they still make sense: not tiny, and the centre on a display that is
/// connected now. Otherwise null, and the window opens centred.
Rect? restorableBounds(List<num> b, List<Rect> workAreas, {double minWidth = 400, double minHeight = 300}) {
  if (b.length < 4 || b[2] < minWidth || b[3] < minHeight) return null; // e.g. a minimised window saved as 160 x 28 at -32000
  final r = Rect.fromLTWH(b[0].toDouble(), b[1].toDouble(), b[2].toDouble(), b[3].toDouble());
  return workAreas.any((a) => a.contains(r.center)) ? r : null;
}

/// The work area of every display, in physical pixels.
Future<List<Rect>> workAreas() async => [
  for (final d in await screenRetriever.getAllDisplays())
    (d.visiblePosition ?? Offset.zero) * (d.scaleFactor ?? 1).toDouble() & (d.visibleSize ?? d.size) * (d.scaleFactor ?? 1).toDouble(),
];

/// When this says so, closing the window only hides it (Settings → Window → Close to tray).
bool Function() hideOnClose = () => false;

/// Frameless window that remembers its size and position.
/// [onClose] runs before the window closes (to save the queue and stop audio).
Future<void> setupWindow(Library lib, Future<void> Function() onClose, {Color background = const Color(0xFF000000)}) async {
  if (!isDesktop) return;
  await windowManager.ensureInitialized();
  List<num>? saved;
  Rect? bounds;
  try {
    saved = (jsonDecode(lib.setting('window') ?? 'null') as List?)?.cast<num>();
    if (saved != null) bounds = restorableBounds(saved, await workAreas());
  } catch (_) {} // a broken setting or no display info: open centred
  await windowManager.waitUntilReadyToShow(
    WindowOptions(
      size: const Size(1360, 860),
      minimumSize: const Size(960, 640),
      center: bounds == null,
      backgroundColor: background,
      titleBarStyle: TitleBarStyle.hidden,
      title: 'Lumen',
    ),
    () async {
      final (b, max) = (bounds, saved != null && saved.length > 4 && saved[4] == 1);
      if (b != null) {
        // Twice: moving onto a monitor with another scale makes Windows rescale the size once.
        await windowManager.setBounds(b / _ratio);
        await windowManager.setBounds(b / _ratio);
        if (max) await windowManager.maximize();
      }
      await windowManager.show();
      await windowManager.focus();
    },
  );
  await windowManager.setPreventClose(true);
  windowManager.addListener(_Saver(lib, onClose));
}

/// The window is the mini player: its moves are saved as the mini player's place, not the window's.
bool miniWindow = false;

/// Physical pixels per logical pixel for window_manager calls (see above).
double get windowRatio => _ratio;

Future<void> minimizeWindow() => windowManager.minimize();
Future<void> leaveFullScreen() async {
  try {
    if (isDesktop && await windowManager.isFullScreen()) await windowManager.setFullScreen(false);
  } catch (_) {} // no window (tests)
}

Future<void> toggleMaximize() async => await windowManager.isMaximized() ? windowManager.unmaximize() : windowManager.maximize();
Future<void> closeWindow() => windowManager.close();
Widget dragArea(Widget child) => isDesktop ? DragToMoveArea(child: child) : child;

extension on Rect {
  Rect operator /(double r) => Rect.fromLTWH(left / r, top / r, width / r, height / r);
}

class _Saver with WindowListener {
  _Saver(this.lib, this.onClose);
  final Library lib;
  final Future<void> Function() onClose;
  Timer? _t;
  void _save() {
    _t?.cancel();
    _t = Timer(const Duration(milliseconds: 400), _store);
  }

  Future<void> _store() async {
    // Minimised, the window sits at -32000: keep the last normal bounds.
    if (await windowManager.isMinimized()) return;
    if (miniWindow) {
      final at = await windowManager.getPosition() * _ratio;
      lib.setSetting('mini', jsonEncode([at.dx.round(), at.dy.round()]));
      return;
    }
    final max = await windowManager.isMaximized();
    final current = lib.setting('window');
    if (max && current != null) {
      // Keep the normal size for when the window is restored.
      final b = (jsonDecode(current) as List).cast<num>();
      lib.setSetting('window', jsonEncode([...b.take(4), 1]));
      return;
    }
    final ratio = _ratio;
    final r = await windowManager.getBounds();
    lib.setSetting(
      'window',
      jsonEncode([
        for (final v in [r.left, r.top, r.width, r.height]) (v * ratio).round(),
        max ? 1 : 0,
      ]),
    );
  }

  @override
  Future<void> onWindowClose() async {
    if (hideOnClose()) {
      await windowManager.hide();
      return;
    }
    try {
      _t?.cancel();
      await _store();
      await onClose();
    } finally {
      await windowManager.destroy();
    }
  }

  @override
  void onWindowResize() => _save();
  @override
  void onWindowMove() => _save();
  @override
  void onWindowMaximize() => _save();
  @override
  void onWindowUnmaximize() => _save();
}
