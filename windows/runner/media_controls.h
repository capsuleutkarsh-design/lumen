#ifndef RUNNER_MEDIA_CONTROLS_H_
#define RUNNER_MEDIA_CONTROLS_H_

#include <flutter/binary_messenger.h>
#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <windows.h>

#include <memory>
#include <mutex>
#include <string>

#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Media.h>
#include <winrt/Windows.Storage.h>

// Windows System Media Transport Controls (the media overlay, lock screen and
// hardware media keys), driven from Dart over the "music_player/media_controls"
// channel. Button presses arrive on a background thread and are posted back to
// the window so Dart is always called on the platform thread.
class MediaControls {
 public:
  static constexpr UINT kButtonMessage = WM_APP + 0x51;
  static constexpr UINT kThumbnailMessage = WM_APP + 0x52;

  MediaControls(HWND hwnd, flutter::BinaryMessenger* messenger);
  void OnButton(int button);
  void OnThumbnail();

 private:
  void Update(const flutter::EncodableMap& args);

  HWND hwnd_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
  winrt::Windows::Media::SystemMediaTransportControls smtc_{nullptr};
  std::mutex mutex_;
  winrt::Windows::Foundation::IAsyncOperation<winrt::Windows::Storage::StorageFile> open_op_{nullptr};
  std::string art_path_, pending_path_;
  winrt::Windows::Storage::StorageFile art_file_{nullptr}, pending_file_{nullptr};
};

#endif  // RUNNER_MEDIA_CONTROLS_H_
