#ifndef RUNNER_GAME_OVERLAY_H_
#define RUNNER_GAME_OVERLAY_H_

#include <flutter/binary_messenger.h>
#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <windows.h>

#include <cstdint>
#include <map>
#include <memory>
#include <string>
#include <vector>

// The in-game overlay: small panels (who is talking, message toasts) over a
// game running fullscreen or borderless, as Discord's overlay has them.
//
// Dart decides what the panels say and draws them
// (lib/utils/game_overlay/); this shows each one in its own small
// click-through window while a fullscreen window of another app is in front,
// and tells Dart when that changes.
//
// Nothing here goes near the game: no DLL injection, no graphics hooks, no
// handle to its process, no hiding from screen capture. Those are what
// anticheats look for; docs/game-overlay.md says why each one stays out.
class GameOverlay {
 public:
  explicit GameOverlay(flutter::BinaryMessenger* messenger);
  ~GameOverlay();

  GameOverlay(const GameOverlay&) = delete;
  GameOverlay& operator=(const GameOverlay&) = delete;

 private:
  struct Panel {
    HWND window = nullptr;
    bool shown = false;
    std::string corner;
    int width = 0;
    int height = 0;
    // Premultiplied BGRA, top-down: what UpdateLayeredWindow takes.
    std::vector<uint8_t> bgra;
  };

  void OnMethodCall(
      const flutter::MethodCall<flutter::EncodableValue>& call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
  void Start();
  void Stop();
  bool SetPanel(const flutter::EncodableMap& args);
  void RemovePanel(int32_t id);

  // Looks at the foreground window again. When the game in front changes,
  // moves the panels to it (or hides them) and tells Dart.
  void Check();
  // Puts every panel in its corner of the game's screen, stacked in id
  // order, or hides them all when no game is in front. [raise] brings them
  // back above the game, which a newly focused topmost game can cover.
  void Layout(bool raise);
  flutter::EncodableMap State() const;

  static void CALLBACK OnForegroundChanged(HWINEVENTHOOK hook, DWORD event,
                                           HWND window, LONG object,
                                           LONG child, DWORD thread,
                                           DWORD time);
  static void CALLBACK OnTimer(HWND window, UINT message, UINT_PTR id,
                               DWORD time);

  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
  HWINEVENTHOOK hook_ = nullptr;
  UINT_PTR timer_ = 0;

  // The fullscreen window in front, its monitor and that monitor's DPI.
  HWND game_ = nullptr;
  RECT screen_ = {};
  UINT dpi_ = USER_DEFAULT_SCREEN_DPI;

  // By id, which is also the order they stack in from the corner.
  std::map<int32_t, Panel> panels_;
};

#endif  // RUNNER_GAME_OVERLAY_H_
