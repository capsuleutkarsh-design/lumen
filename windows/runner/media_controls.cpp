#include "media_controls.h"

#include <SystemMediaTransportControlsInterop.h>
#include <flutter/standard_method_codec.h>
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Storage.Streams.h>

#include <string>

#include "resource.h"

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
      messenger, "gleo/media_controls", &flutter::StandardMethodCodec::GetInstance());
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
  const bool has_track = Get<bool>(args, "hasTrack", false);
  const bool playing = Get<bool>(args, "playing", false);
  if (has_track != has_track_ || playing != playing_) {
    has_track_ = has_track;
    playing_ = playing;
    UpdateThumbBar(false);
  }
  if (!smtc_) return;
  try {
    smtc_.IsEnabled(has_track);
    if (!has_track) return;
    smtc_.PlaybackStatus(playing ? MediaPlaybackStatus::Playing : MediaPlaybackStatus::Paused);
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

namespace {
constexpr WORD kThumbPrevious = 1, kThumbPlay = 2, kThumbNext = 3;
}

void MediaControls::OnTaskbarCreated() {
  if (!taskbar_) {
    if (FAILED(CoCreateInstance(CLSID_TaskbarList, nullptr, CLSCTX_INPROC_SERVER, IID_PPV_ARGS(taskbar_.put()))) ||
        FAILED(taskbar_->HrInit())) {
      taskbar_ = nullptr;
    }
  }
  UpdateThumbBar(true);
}

// Previous / play-pause / next under the taskbar thumbnail; play-pause follows the state, and with no song all three are greyed.
void MediaControls::UpdateThumbBar(bool add) {
  if (!taskbar_) return;
  const int size = GetSystemMetricsForDpi(SM_CXSMICON, GetDpiForWindow(hwnd_));
  auto icon = [size](int id) {
    return static_cast<HICON>(LoadImage(GetModuleHandle(nullptr), MAKEINTRESOURCE(id), IMAGE_ICON, size, size, 0));
  };
  // ponytail: loaded once, at the first screen's scale; reload them on WM_DPICHANGED if they ever look soft.
  static HICON prev = icon(IDI_THUMB_PREV), play = icon(IDI_THUMB_PLAY), pause = icon(IDI_THUMB_PAUSE), next = icon(IDI_THUMB_NEXT);
  const THUMBBUTTONFLAGS flags = has_track_ ? THBF_ENABLED : THBF_DISABLED;
  THUMBBUTTON buttons[3] = {};
  const struct { WORD id; HICON icon; const wchar_t* tip; } spec[3] = {
      {kThumbPrevious, prev, L"Previous"},
      {kThumbPlay, playing_ ? pause : play, playing_ ? L"Pause" : L"Play"},
      {kThumbNext, next, L"Next"},
  };
  for (int i = 0; i < 3; i++) {
    buttons[i].dwMask = THB_ICON | THB_TOOLTIP | THB_FLAGS;
    buttons[i].iId = spec[i].id;
    buttons[i].hIcon = spec[i].icon;
    buttons[i].dwFlags = flags;
    wcscpy_s(buttons[i].szTip, spec[i].tip);
  }
  if (add) taskbar_->ThumbBarAddButtons(hwnd_, 3, buttons);
  else taskbar_->ThumbBarUpdateButtons(hwnd_, 3, buttons);
}

bool MediaControls::OnThumbButton(WORD id) {
  switch (id) {
    case kThumbPrevious: Send("previous"); return true;
    case kThumbPlay: Send(playing_ ? "pause" : "play"); return true;
    case kThumbNext: Send("next"); return true;
  }
  return false;
}

void MediaControls::Send(const char* button) {
  channel_->InvokeMethod("button", std::make_unique<flutter::EncodableValue>(button));
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
  Send(name);
}

void MediaControls::OnSeek(int64_t ms) {
  channel_->InvokeMethod("seek", std::make_unique<flutter::EncodableValue>(ms));
}
