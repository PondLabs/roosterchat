// ROOSTER: a local WebRTC video track fed by a file, for measuring.
//
// Face tracking is measured on test videos with a reference
// (tools/face_tracking/README.md), through the same renderer and frame tap
// a camera or a remote video goes through, without turning a camera on.
// This plays a `.y4m` file (raw 4:2:0 frames, what Chrome's fake camera
// reads too) at its own frame rate, over and over, into a custom video
// source (`CreateCustomVideoSource`): one pacing thread per track.
//
// Lifetime: Stop() joins the thread; the track itself is released by the
// usual mediaStreamDispose.
#ifndef ROOSTER_FILE_VIDEO_SOURCE_H_
#define ROOSTER_FILE_VIDEO_SOURCE_H_

#include <atomic>
#include <chrono>
#include <cstdint>
#include <cstdlib>
#include <fstream>
#include <map>
#include <memory>
#include <mutex>
#include <sstream>
#include <string>
#include <thread>
#include <vector>

#include "rtc_types.h"
#include "rtc_video_frame.h"
#include "rtc_video_source.h"

namespace flutter_webrtc_plugin {

using namespace libwebrtc;

// What a `.y4m` file holds, from its header.
struct RoosterY4mHeader {
  int width = 0;
  int height = 0;
  int fps_num = 30;
  int fps_den = 1;

  // Parses the first line of a file. Only 4:2:0 is taken: what WebRTC
  // carries, and what `ffmpeg -pix_fmt yuv420p` writes.
  static bool Parse(const std::string& line, RoosterY4mHeader* out,
                    std::string* error) {
    std::istringstream words(line);
    std::string word;
    if (!(words >> word) || word != "YUV4MPEG2") {
      *error = "not a YUV4MPEG2 file";
      return false;
    }
    RoosterY4mHeader header;
    while (words >> word) {
      const char tag = word[0];
      const std::string value = word.substr(1);
      if (tag == 'W') {
        header.width = std::atoi(value.c_str());
      } else if (tag == 'H') {
        header.height = std::atoi(value.c_str());
      } else if (tag == 'F') {
        const size_t colon = value.find(':');
        if (colon == std::string::npos) {
          *error = "bad frame rate " + value;
          return false;
        }
        header.fps_num = std::atoi(value.substr(0, colon).c_str());
        header.fps_den = std::atoi(value.substr(colon + 1).c_str());
      } else if (tag == 'C' && value.rfind("420", 0) != 0) {
        *error = "only 4:2:0 is played, not " + value;
        return false;
      }
    }
    if (header.width <= 0 || header.height <= 0 || header.fps_num <= 0 ||
        header.fps_den <= 0) {
      *error = "no size or frame rate";
      return false;
    }
    *out = header;
    return true;
  }

  size_t FrameBytes() const {
    const size_t chroma = size_t((width + 1) / 2) * size_t((height + 1) / 2);
    return size_t(width) * size_t(height) + 2 * chroma;
  }
};

class RoosterFileVideoFeeder {
 public:
  // Opens `path` and checks its header; null with `error` set otherwise.
  static std::unique_ptr<RoosterFileVideoFeeder> Open(const std::string& path,
                                                      std::string* error) {
    std::unique_ptr<RoosterFileVideoFeeder> feeder(new RoosterFileVideoFeeder());
    feeder->file_.open(path, std::ios::binary);
    if (!feeder->file_) {
      *error = "cannot open " + path;
      return nullptr;
    }
    std::string line;
    if (!std::getline(feeder->file_, line) ||
        !RoosterY4mHeader::Parse(line, &feeder->header_, error)) {
      return nullptr;
    }
    feeder->first_frame_ = feeder->file_.tellg();
    // Every frame is a "FRAME" line and its pixels; the lines of this file
    // have no parameters if the first one has none.
    std::string frame_line;
    if (!std::getline(feeder->file_, frame_line) ||
        frame_line.rfind("FRAME", 0) != 0) {
      *error = "no frame in " + path;
      return nullptr;
    }
    feeder->file_.seekg(0, std::ios::end);
    const int64_t data =
        int64_t(feeder->file_.tellg()) - int64_t(feeder->first_frame_);
    feeder->frames_ =
        data / int64_t(frame_line.size() + 1 + feeder->header_.FrameBytes());
    feeder->file_.clear();
    feeder->file_.seekg(feeder->first_frame_);
    return feeder;
  }

  ~RoosterFileVideoFeeder() { Stop(); }

  RoosterFileVideoFeeder(const RoosterFileVideoFeeder&) = delete;
  RoosterFileVideoFeeder& operator=(const RoosterFileVideoFeeder&) = delete;

  const RoosterY4mHeader& header() const { return header_; }
  int64_t frames() const { return frames_; }

  void Start(scoped_refptr<RTCVideoSource> source) {
    source_ = source;
    thread_ = std::thread(&RoosterFileVideoFeeder::Run, this);
  }

  void Stop() {
    stop_.store(true);
    if (thread_.joinable()) thread_.join();
  }

 private:
  RoosterFileVideoFeeder() = default;

  // The next frame's pixels, from the start again after the last one.
  bool ReadFrame(std::vector<uint8_t>* pixels) {
    for (int attempt = 0; attempt < 2; attempt++) {
      std::string line;
      if (std::getline(file_, line) && line.rfind("FRAME", 0) == 0 &&
          file_.read(reinterpret_cast<char*>(pixels->data()),
                     std::streamsize(pixels->size()))) {
        return true;
      }
      file_.clear();
      file_.seekg(first_frame_);
    }
    return false;
  }

  void Run() {
    using Clock = std::chrono::steady_clock;
    const int w = header_.width;
    const int h = header_.height;
    const int cw = (w + 1) / 2;
    const size_t luma = size_t(w) * size_t(h);
    const size_t chroma = size_t(cw) * size_t((h + 1) / 2);
    std::vector<uint8_t> pixels(header_.FrameBytes());
    const auto period = std::chrono::microseconds(
        int64_t(1000000) * header_.fps_den / header_.fps_num);
    auto next = Clock::now();
    while (!stop_.load()) {
      if (!ReadFrame(&pixels)) break;
      const uint8_t* y = pixels.data();
      scoped_refptr<RTCVideoFrame> frame = RTCVideoFrame::Create(
          w, h, y, w, y + luma, cw, y + luma + chroma, cw);
      if (frame.get()) source_->OnCapturedFrame(frame);

      next += period;
      const auto now = Clock::now();
      if (now - next > std::chrono::milliseconds(200)) {
        // Starved for long: a burst of frames would only be dropped.
        next = now;
      } else if (next > now) {
        std::this_thread::sleep_until(next);
      }
    }
  }

  std::ifstream file_;
  RoosterY4mHeader header_;
  std::streampos first_frame_ = 0;
  int64_t frames_ = 0;
  scoped_refptr<RTCVideoSource> source_;
  std::atomic<bool> stop_{false};
  std::thread thread_;
};

// The file-fed tracks alive in this process, by track id.
class RoosterFileVideoTracks {
 public:
  ~RoosterFileVideoTracks() { StopAll(); }

  void Add(const std::string& track_id,
           std::unique_ptr<RoosterFileVideoFeeder> feeder) {
    std::lock_guard<std::mutex> lock(mutex_);
    feeders_[track_id] = std::move(feeder);
  }

  // False when no such track was playing.
  bool Stop(const std::string& track_id) {
    std::unique_ptr<RoosterFileVideoFeeder> feeder;
    {
      std::lock_guard<std::mutex> lock(mutex_);
      auto it = feeders_.find(track_id);
      if (it == feeders_.end()) return false;
      feeder = std::move(it->second);
      feeders_.erase(it);
    }
    feeder->Stop();
    return true;
  }

  void StopAll() {
    std::map<std::string, std::unique_ptr<RoosterFileVideoFeeder>> feeders;
    {
      std::lock_guard<std::mutex> lock(mutex_);
      feeders.swap(feeders_);
    }
    for (auto& entry : feeders) entry.second->Stop();
  }

 private:
  std::mutex mutex_;
  std::map<std::string, std::unique_ptr<RoosterFileVideoFeeder>> feeders_;
};

}  // namespace flutter_webrtc_plugin

#endif  // ROOSTER_FILE_VIDEO_SOURCE_H_
