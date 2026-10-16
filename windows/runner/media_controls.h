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
// hardware media keys), driven from Dart over the "gleo/media_controls"
// channel. Button presses arrive on a background thread and are posted back to
// the window so Dart is always called on the platform thread.
class MediaControls {
 public:
  static constexpr UINT kButtonMessage = WM_APP + 0x51;
  static constexpr UINT kThumbnailMessage = WM_APP + 0x52;
  static constexpr UINT kSeekMessage = WM_APP + 0x53;  // lParam = position in ms

  MediaControls(HWND hwnd, flutter::BinaryMessenger* messenger);
  ~MediaControls();
  void OnButton(int button);
  void OnThumbnail();
  void OnSeek(int64_t ms);

 private:
  void Update(const flutter::EncodableMap& args);

  // A cover opened in the background. Shared with the async callback, so it
  // outlives this object if the window closes while the file is opening.
  struct Pending {
    std::mutex mutex;
    std::string path;
    winrt::Windows::Storage::StorageFile file{nullptr};
  };

  HWND hwnd_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
  winrt::Windows::Media::SystemMediaTransportControls smtc_{nullptr};
  winrt::event_token button_token_{}, seek_token_{};
  std::shared_ptr<Pending> pending_ = std::make_shared<Pending>();
  winrt::Windows::Foundation::IAsyncOperation<winrt::Windows::Storage::StorageFile> open_op_{nullptr};
  std::string art_path_;
  winrt::Windows::Storage::StorageFile art_file_{nullptr};
};

#endif  // RUNNER_MEDIA_CONTROLS_H_
