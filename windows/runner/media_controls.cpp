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
    smtc_.IsStopEnabled(true);
    smtc_.IsEnabled(false);
    button_token_ = smtc_.ButtonPressed([hwnd](auto&&, SystemMediaTransportControlsButtonPressedEventArgs const& args) {
      ::PostMessage(hwnd, kButtonMessage, static_cast<WPARAM>(args.Button()), 0);
    });
    seek_token_ = smtc_.PlaybackPositionChangeRequested(
        [hwnd](auto&&, PlaybackPositionChangeRequestedEventArgs const& args) {
          const int64_t ms = args.RequestedPlaybackPosition().count() / 10000;
          ::PostMessage(hwnd, kSeekMessage, 0, static_cast<LPARAM>(ms));
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

MediaControls::~MediaControls() {
  try {
    if (open_op_) open_op_.Cancel();
    if (smtc_) {
      smtc_.ButtonPressed(button_token_);
      smtc_.PlaybackPositionChangeRequested(seek_token_);
    }
  } catch (...) {
  }
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
    // The cover: reuse the open file for the same song, otherwise open it
    // (async) and finish on the platform thread via the window.
    const auto art = Get<std::string>(args, "art", "");
    if (art == art_path_) {
      if (art_file_) updater.Thumbnail(RandomAccessStreamReference::CreateFromFile(art_file_));
      updater.Update();
      return;
    }
    art_path_ = art;
    art_file_ = nullptr;
    updater.Thumbnail(nullptr);
    updater.Update();
    if (art.empty()) return;
    if (open_op_) open_op_.Cancel();
    open_op_ = StorageFile::GetFileFromPathAsync(winrt::to_hstring(art));
    // Captures copies only (never `this`): it may finish after the window is gone.
    open_op_.Completed([pending = pending_, hwnd = hwnd_, art](IAsyncOperation<StorageFile> const& op,
                                                               AsyncStatus status) {
      if (status != AsyncStatus::Completed) return;
      {
        std::lock_guard<std::mutex> lock(pending->mutex);
        pending->path = art;
        pending->file = op.GetResults();
      }
      ::PostMessage(hwnd, kThumbnailMessage, 0, 0);
    });
  } catch (...) {
  }
}

void MediaControls::OnThumbnail() {
  {
    std::lock_guard<std::mutex> lock(pending_->mutex);
    if (pending_->path != art_path_) return;  // an older song's cover
    art_file_ = pending_->file;
  }
  if (!smtc_ || !art_file_) return;
  try {
    auto updater = smtc_.DisplayUpdater();
    updater.Thumbnail(RandomAccessStreamReference::CreateFromFile(art_file_));
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
    case SystemMediaTransportControlsButton::Stop: name = "stop"; break;
    default: return;
  }
  channel_->InvokeMethod("button", std::make_unique<flutter::EncodableValue>(name));
}

void MediaControls::OnSeek(int64_t ms) {
  channel_->InvokeMethod("seek", std::make_unique<flutter::EncodableValue>(ms));
}
