import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

File? _file;
var _size = 0;
const _maxSize = 1 << 20; // past 1 MB the log becomes gleo.log.1 and a new one starts

/// Sends debugPrint, Flutter errors and uncaught async errors to `<data>\gleo.log`.
void startLog(String dataDir) {
  try {
    Directory(dataDir).createSync(recursive: true);
    final f = File(p.join(dataDir, 'gleo.log'));
    _size = f.existsSync() ? f.lengthSync() : 0;
    _file = f;
  } catch (_) {
    _file = null; // e.g. a read-only folder: the start-up screen says what is wrong
  }
  final console = debugPrint;
  debugPrint = (m, {wrapWidth}) {
    console(m, wrapWidth: wrapWidth);
    log(m ?? '');
  };
  FlutterError.onError = (d) {
    if (!kDebugMode) log('${d.exceptionAsString()}\n${d.stack ?? ''}');
    FlutterError.presentError(d); // in debug builds this reaches the log through debugPrint
  };
  PlatformDispatcher.instance.onError = (e, s) {
    log('Uncaught: $e\n$s');
    return true;
  };
}

String? get logPath => _file?.path;

/// One timestamped line (or block) in the log. Never throws.
void log(String text) {
  final f = _file;
  if (f == null) return;
  try {
    if (_size > _maxSize) {
      f.renameSync('${f.path}.1'); // replaces the previous gleo.log.1
      _size = 0;
    }
    final line = '${DateTime.now().toIso8601String()}  $text\n';
    f.writeAsStringSync(line, mode: FileMode.append, flush: true);
    _size += line.length;
  } catch (_) {}
}

/// Opens a folder, a file (with its default app) or a web address. Android: web addresses only.
void openPath(String target) => Platform.isAndroid
    ? const MethodChannel('gleo/android').invokeMethod('open', target).catchError((Object e) => log('open: $e'))
    : Process.run('explorer.exe', [target]);
