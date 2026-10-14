#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include <cwctype>
#include <functional>
#include <string>

#include "flutter_window.h"
#include "utils.h"

namespace {

std::wstring ExePath(HANDLE process) {
  wchar_t path[4096];
  DWORD size = ARRAYSIZE(path);
  return ::QueryFullProcessImageNameW(process, 0, path, &size) ? std::wstring(path, size) : std::wstring();
}

// Brings the window of the Lumen already running from this same lumen.exe to the front.
BOOL CALLBACK FocusRunning(HWND hwnd, LPARAM exe) {
  wchar_t cls[64];
  if (!::GetClassNameW(hwnd, cls, ARRAYSIZE(cls)) || wcscmp(cls, L"FLUTTER_RUNNER_WIN32_WINDOW") != 0) return TRUE;
  DWORD pid = 0;
  ::GetWindowThreadProcessId(hwnd, &pid);
  HANDLE process = ::OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, pid);
  if (!process) return TRUE;
  const bool same = _wcsicmp(ExePath(process).c_str(), reinterpret_cast<const std::wstring*>(exe)->c_str()) == 0;
  ::CloseHandle(process);
  if (!same) return TRUE;
  if (!::IsWindowVisible(hwnd)) ::ShowWindow(hwnd, SW_SHOW);  // closed to the tray
  if (::IsIconic(hwnd)) ::ShowWindow(hwnd, SW_RESTORE);
  ::SetForegroundWindow(hwnd);
  return FALSE;
}

}  // namespace

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // One Lumen per lumen.exe: a second launch brings the first window forward and quits, so two copies
  // never share one library. Copies in other folders (portable, test builds) run on their own.
  // ponytail: a file path given to the second launch is not handed over yet ("Open with Lumen" later).
  const std::wstring exe = ExePath(::GetCurrentProcess());
  std::wstring key = exe;
  for (auto &c : key) c = static_cast<wchar_t>(std::towlower(c));
  ::CreateMutexW(nullptr, FALSE, (L"Lumen.SingleInstance." + std::to_wstring(std::hash<std::wstring>{}(key))).c_str());
  if (::GetLastError() == ERROR_ALREADY_EXISTS) {
    ::EnumWindows(FocusRunning, reinterpret_cast<LPARAM>(&exe));
    return EXIT_SUCCESS;
  }
  // The installer and uninstaller wait while any Lumen runs (AppMutex in installer\lumen.iss).
  ::CreateMutexW(nullptr, FALSE, L"Lumen.SingleInstance");

  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();
#ifdef FLUTTER_VERSION
  // The version from pubspec.yaml, shown in Settings > About.
  command_line_arguments.insert(command_line_arguments.begin(), "--app-version=" FLUTTER_VERSION);
#endif

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(L"Lumen", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
