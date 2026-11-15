// ROOSTER: the frames of a video track, handed to Rooster's face tracker.
//
// Cock-a-Doodle-Who? pins a plaque to each player's forehead, worked out
// from the very picture the app draws (docs/adr/0006-face-tracking.md).
// Dart asks the plugin to tap a track (`roosterTapVideoTrack`) with a
// tracker's handle and the address of `rooster_face_frame`
// (rust/face_tracking/src/ffi.rs); every FlutterVideoRenderer showing that
// track then hands each frame it gets, from OnFrame, before drawing it. A
// track nobody shows is not tracked. Camera, remote and file-fed tracks all
// come through the same OnFrame.
//
// The function only copies the frame. Remove() returns once no call with
// that handle is running, and none follows: then the handle may be freed.
#ifndef ROOSTER_FACE_TAP_H_
#define ROOSTER_FACE_TAP_H_

#include <atomic>
#include <cstdint>
#include <map>
#include <mutex>
#include <string>

#include "rtc_types.h"
#include "rtc_video_frame.h"

namespace flutter_webrtc_plugin {

using namespace libwebrtc;

class RoosterFaceTaps {
 public:
  // Matches `rooster_face_frame` in rust/face_tracking/src/ffi.rs.
  typedef void (*FrameFn)(void* ctx, int32_t width, int32_t height,
                          int32_t rotation, const uint8_t* y,
                          int32_t stride_y, const uint8_t* u,
                          int32_t stride_u, const uint8_t* v,
                          int32_t stride_v);

  // One registry per process: the renderers and the method channel both
  // reach it without holding each other.
  static RoosterFaceTaps& Instance() {
    static RoosterFaceTaps taps;
    return taps;
  }

  void Add(const std::string& track_id, void* ctx, FrameFn fn) {
    std::lock_guard<std::mutex> lock(mutex_);
    taps_[ctx] = Tap{track_id, fn};
    count_.store(taps_.size());
  }

  // False when there was no such tap.
  bool Remove(void* ctx) {
    std::lock_guard<std::mutex> lock(mutex_);
    const bool removed = taps_.erase(ctx) > 0;
    count_.store(taps_.size());
    return removed;
  }

  // Whether anything is tapped at all: a renderer asks before every frame.
  bool Any() const { return count_.load() > 0; }

  void Deliver(const std::string& track_id,
               const scoped_refptr<RTCVideoFrame>& frame) {
    if (track_id.empty() || !frame.get()) return;
    std::lock_guard<std::mutex> lock(mutex_);
    for (const auto& entry : taps_) {
      if (entry.second.track_id != track_id) continue;
      entry.second.fn(entry.first, frame->width(), frame->height(),
                      static_cast<int32_t>(frame->rotation()),
                      frame->DataY(), frame->StrideY(), frame->DataU(),
                      frame->StrideU(), frame->DataV(), frame->StrideV());
    }
  }

 private:
  struct Tap {
    std::string track_id;
    FrameFn fn;
  };

  RoosterFaceTaps() = default;

  std::mutex mutex_;
  std::map<void*, Tap> taps_;
  std::atomic<size_t> count_{0};
};

}  // namespace flutter_webrtc_plugin

#endif  // ROOSTER_FACE_TAP_H_
