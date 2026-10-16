#include "flutter_window.h"

#include <optional>

#include <flutter/standard_method_codec.h>

#include "flutter/generated_plugin_registrant.h"
#include "media_controls.h"

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  media_controls_ = std::make_unique<MediaControls>(GetHandle(), flutter_controller_->engine()->messenger());
  title_bar_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      flutter_controller_->engine()->messenger(), "gleo/titlebar",
      &flutter::StandardMethodCodec::GetInstance());
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnMaxButtonHover(bool hover) {
  if (title_bar_) {
    title_bar_->InvokeMethod(
        "maxHover", std::make_unique<flutter::EncodableValue>(hover));
  }
}

void FlutterWindow::OnDestroy() {
  title_bar_ = nullptr;
  media_controls_ = nullptr;
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  static const UINT taskbar_created = RegisterWindowMessage(L"TaskbarButtonCreated");
  if (message == taskbar_created && media_controls_) {
    media_controls_->OnTaskbarCreated();
    return 0;
  }
  switch (message) {
    case WM_COMMAND:  // the taskbar thumbnail buttons
      if (HIWORD(wparam) == THBN_CLICKED && media_controls_ && media_controls_->OnThumbButton(LOWORD(wparam))) return 0;
      break;
    case MediaControls::kButtonMessage:
      if (media_controls_) media_controls_->OnButton(static_cast<int>(wparam));
      return 0;
    case MediaControls::kThumbnailMessage:
      if (media_controls_) media_controls_->OnThumbnail();
      return 0;
    case MediaControls::kSeekMessage:
      if (media_controls_) media_controls_->OnSeek(static_cast<int64_t>(lparam));
      return 0;
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
