#include "media_controls.h"

#include <SystemMediaTransportControlsInterop.h>
#include <flutter/standard_method_codec.h>
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Storage.Streams.h>

#include <string>

using namespace winrt::Windows::Media;
using winrt::Windows::Foundation::AsyncStatus;
using winrt::Windows::Foundation::IAsyncOperation;
using winrt::Windows::Foundation::TimeSpan;
using winrt::Windows::Storage::StorageFile;
using winrt::Windows::Storage::Streams::RandomAccessStreamReference;

namespace {

template <typename T>
T Get(const flutter::EncodableMap& map, const char* key, T fallback) {
  auto it = map.find(flutter::EncodableValue(key));
  if (it == map.end()) return fallback;
  if (auto value = std::get_if<T>(&it->second)) return *value;
  return fallback;
}

int64_t GetInt(const flutter::EncodableMap& map, const char* key) {
  auto it = map.find(flutter::EncodableValue(key));
  if (it == map.end()) return 0;
  if (auto v = std::get_if<int32_t>(&it->second)) return *v;
  if (auto v = std::get_if<int64_t>(&it->second)) return *v;
  return 0;
}

TimeSpan Ms(int64_t ms) { return TimeSpan(ms * 10000); }

}  // namespace

MediaControls::MediaControls(HWND hwnd, flutter::BinaryMessenger* messenger) : hwnd_(hwnd) {
  channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      messenger, "music_player/media_controls", &flutter::StandardMethodCodec::GetInstance());
  try {
    auto interop = winrt::get_activation_factory<SystemMediaTransportControls, ISystemMediaTransportControlsInterop>();
    winrt::check_hresult(interop->GetForWindow(hwnd, winrt::guid_of<SystemMediaTransportControls>(),
                                               winrt::put_abi(smtc_)));
    smtc_.IsPlayEnabled(true);
    smtc_.IsPauseEnabled(true);
    smtc_.IsNextEnabled(true);
    smtc_.IsPreviousEnabled(true);
    smtc_.IsEnabled(false);
    smtc_.ButtonPressed([hwnd](auto&&, SystemMediaTransportControlsButtonPressedEventArgs const& args) {
      ::PostMessage(hwnd, kButtonMessage, static_cast<WPARAM>(args.Button()), 0);
    });
  } catch (...) {
    smtc_ = nullptr;  // No media controls on this system; playback still works.
  }
  channel_->SetMethodCallHandler([this](const auto& call, auto result) {
    if (call.method_name() == "update" && call.arguments()) {
      if (auto args = std::get_if<flutter::EncodableMap>(call.arguments())) Update(*args);
    }
    result->Success();
  });
}

void MediaControls::Update(const flutter::EncodableMap& args) {
  if (!smtc_) return;
  try {
    const bool has_track = Get<bool>(args, "hasTrack", false);
    smtc_.IsEnabled(has_track);
    if (!has_track) return;
    smtc_.PlaybackStatus(Get<bool>(args, "playing", false) ? MediaPlaybackStatus::Playing
                                                           : MediaPlaybackStatus::Paused);
    SystemMediaTransportControlsTimelineProperties timeline;
    const auto duration = Ms(GetInt(args, "durationMs"));
    timeline.StartTime(Ms(0));
    timeline.MinSeekTime(Ms(0));
    timeline.EndTime(duration);
    timeline.MaxSeekTime(duration);
    timeline.Position(Ms(GetInt(args, "positionMs")));
    smtc_.UpdateTimelineProperties(timeline);

    if (!Get<bool>(args, "trackChanged", false)) return;
    auto updater = smtc_.DisplayUpdater();
    updater.Type(MediaPlaybackType::Music);
    auto music = updater.MusicProperties();
    music.Title(winrt::to_hstring(Get<std::string>(args, "title", "")));
    music.Artist(winrt::to_hstring(Get<std::string>(args, "artist", "")));
    music.AlbumTitle(winrt::to_hstring(Get<std::string>(args, "album", "")));
    music.AlbumArtist(winrt::to_hstring(Get<std::string>(args, "albumArtist", "")));
    updater.Thumbnail(nullptr);
    updater.Update();

    const int generation = ++generation_;
    const auto art = Get<std::string>(args, "art", "");
    if (art.empty()) return;
    // Opening a file is async; finish on the platform thread via the window.
    StorageFile::GetFileFromPathAsync(winrt::to_hstring(art))
        .Completed([this, generation](IAsyncOperation<StorageFile> const& op, AsyncStatus status) {
          if (status != AsyncStatus::Completed) return;
          {
            std::lock_guard<std::mutex> lock(mutex_);
            pending_thumbnail_ = op.GetResults();
          }
          ::PostMessage(hwnd_, kThumbnailMessage, static_cast<WPARAM>(generation), 0);
        });
  } catch (...) {
  }
}

void MediaControls::OnThumbnail(int generation) {
  StorageFile file{nullptr};
  {
    std::lock_guard<std::mutex> lock(mutex_);
    file = pending_thumbnail_;
    pending_thumbnail_ = nullptr;
  }
  if (!smtc_ || !file || generation != generation_) return;
  try {
    auto updater = smtc_.DisplayUpdater();
    updater.Thumbnail(RandomAccessStreamReference::CreateFromFile(file));
    updater.Update();
  } catch (...) {
  }
}

void MediaControls::OnButton(int button) {
  const char* name = nullptr;
  switch (static_cast<SystemMediaTransportControlsButton>(button)) {
    case SystemMediaTransportControlsButton::Play: name = "play"; break;
    case SystemMediaTransportControlsButton::Pause: name = "pause"; break;
    case SystemMediaTransportControlsButton::Next: name = "next"; break;
    case SystemMediaTransportControlsButton::Previous: name = "previous"; break;
    case SystemMediaTransportControlsButton::Stop: name = "pause"; break;
    default: return;
  }
  channel_->InvokeMethod("button", std::make_unique<flutter::EncodableValue>(name));
}
