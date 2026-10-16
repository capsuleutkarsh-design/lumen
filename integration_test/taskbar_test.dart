// The taskbar thumbnail buttons (windows/runner/media_controls.cpp): Windows sends WM_COMMAND with THBN_CLICKED
// when one is clicked; this test sends the same message to Gleo's window and checks the music follows.
// Run (silent, never the real library):
//   flutter test integration_test/taskbar_test.dart -d windows --dart-define=MP_DATA=<scratch>\appdata
//     --dart-define=MP_MUSIC=<folder holding testlib>
import 'dart:async';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gleo/main.dart';
import 'package:gleo/ui/app.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;

final _user32 = DynamicLibrary.open('user32.dll');
final _findWindowEx = _user32
    .lookupFunction<IntPtr Function(IntPtr, IntPtr, Pointer<Utf16>, Pointer<Utf16>), int Function(int, int, Pointer<Utf16>, Pointer<Utf16>)>(
      'FindWindowExW',
    );
final _threadProcessId = _user32
    .lookupFunction<Uint32 Function(IntPtr, Pointer<Uint32>), int Function(int, Pointer<Uint32>)>('GetWindowThreadProcessId');
final _postMessage = _user32
    .lookupFunction<Int32 Function(IntPtr, Uint32, IntPtr, IntPtr), int Function(int, int, int, int)>('PostMessageW');

/// This process's Gleo window (another Gleo may be open).
int ownWindow() {
  final cls = 'FLUTTER_RUNNER_WIN32_WINDOW'.toNativeUtf16();
  final owner = calloc<Uint32>();
  try {
    for (var h = _findWindowEx(0, 0, cls, nullptr); h != 0; h = _findWindowEx(0, h, cls, nullptr)) {
      _threadProcessId(h, owner);
      if (owner.value == pid) return h;
    }
    return 0;
  } finally {
    calloc.free(cls);
    calloc.free(owner);
  }
}

/// A click on thumbnail button [id] (1 previous, 2 play / pause, 3 next).
void click(int id) => _postMessage(ownWindow(), 0x0111 /* WM_COMMAND */, (0x1800 /* THBN_CLICKED */ << 16) | id, 0);

Future<void> waitFor(bool Function() ok, {String what = ''}) async {
  final sw = Stopwatch()..start();
  while (!ok()) {
    if (sw.elapsed > const Duration(minutes: 2)) throw TimeoutException('waiting for $what');
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
}

void main() {
  final testlib = p.join(const String.fromEnvironment('MP_MUSIC'), 'testlib');
  if (!Platform.isWindows || !Directory(testlib).existsSync()) {
    test('taskbar buttons', () {}, skip: 'Windows, with --dart-define=MP_MUSIC=<folder holding testlib>');
    return;
  }
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('the taskbar thumbnail buttons play, pause, skip and go back', (tester) async {
    final data = Directory(const String.fromEnvironment('MP_DATA'));
    if (data.existsSync()) data.deleteSync(recursive: true);
    await boot(silent: true);
    lib.folders = [testlib];
    await waitFor(() => lib.scan.value == null && lib.albums.any((a) => a.title == 'Deep Water'), what: 'scan');
    await tester.pumpWidget(const App());
    expect(ownWindow(), isNot(0));

    final deep = lib.albums.firstWhere((a) => a.title == 'Deep Water').tracks;
    await engine.playTracks(deep);
    await waitFor(() => engine.playing, what: 'playing');
    click(2);
    await waitFor(() => !engine.playing, what: 'pause');
    click(2);
    await waitFor(() => engine.playing, what: 'play');
    click(3);
    await waitFor(() => engine.current?.id == deep[1].id, what: 'next');
    click(1);
    await waitFor(() => engine.current?.id == deep[0].id, what: 'previous');
    await engine.shutdown();
  });
}
