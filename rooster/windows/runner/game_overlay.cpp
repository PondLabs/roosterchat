#include "game_overlay.h"

#include <flutter/standard_method_codec.h>
#include <flutter_windows.h>
#include <shellapi.h>

#include <cstring>

namespace {

constexpr char kChannelName[] = "com.pondlabs.rooster/overlay";

// Honest, stable names: anticheats read the class and title of windows over
// the game, and a nameless or random one looks like an ESP overlay hiding.
constexpr wchar_t kWindowClass[] = L"RoosterOverlayWindow";
constexpr wchar_t kWindowTitle[] = L"Rooster Overlay";

// Catches what the foreground hook does not announce: a game going
// fullscreen, or into exclusive fullscreen, while it already has the focus.
constexpr UINT kCheckIntervalMs = 1000;

// Logical pixels from the screen's edge, and between stacked panels.
constexpr int kMargin = 16;
constexpr int kGap = 8;

// Panels are a list of people or a few toasts. Anything near the screen's
// size is a bug in the caller, and a window covering most of the game is
// what anticheats inspect.
constexpr int kMaxPanelSide = 2048;

GameOverlay* g_overlay = nullptr;
bool g_class_registered = false;

const flutter::EncodableValue* Find(const flutter::EncodableMap& map,
                                    const char* key) {
  auto it = map.find(flutter::EncodableValue(key));
  return it == map.end() ? nullptr : &it->second;
}

LRESULT CALLBACK OverlayWindowProc(HWND window, UINT message, WPARAM wparam,
                                   LPARAM lparam) {
  switch (message) {
    case WM_MOUSEACTIVATE:
      // Taking the focus would minimize a fullscreen game.
      return MA_NOACTIVATE;
    case WM_NCHITTEST:
      return HTTRANSPARENT;
  }
  return DefWindowProcW(window, message, wparam, lparam);
}

HWND CreatePanelWindow() {
  HINSTANCE instance = GetModuleHandleW(nullptr);
  if (!g_class_registered) {
    WNDCLASSEXW window_class = {};
    window_class.cbSize = sizeof(window_class);
    window_class.lpfnWndProc = OverlayWindowProc;
    window_class.hInstance = instance;
    window_class.lpszClassName = kWindowClass;
    g_class_registered = RegisterClassExW(&window_class) != 0;
    if (!g_class_registered) {
      return nullptr;
    }
  }
  // Layered and transparent: clicks go through to the game. No activation
  // and no taskbar button or Alt+Tab entry. No owner either: an owned
  // window would hide whenever Rooster's own window does.
  return CreateWindowExW(WS_EX_LAYERED | WS_EX_TRANSPARENT | WS_EX_TOPMOST |
                             WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE,
                         kWindowClass, kWindowTitle, WS_POPUP, 0, 0, 0, 0,
                         nullptr, nullptr, instance, nullptr);
}

// The window in front when it fills its monitor without a title bar (a game
// fullscreen or borderless, a video fullscreen), unless it is Rooster's own
// or the desktop. Reads only what any window manager reads: the foreground
// window's style, rectangle and class. It never opens the game's process.
HWND FullscreenWindowInFront() {
  HWND window = GetForegroundWindow();
  if (window == nullptr || !IsWindowVisible(window) || IsIconic(window) ||
      window == GetShellWindow() || window == GetDesktopWindow()) {
    return nullptr;
  }

  DWORD process = 0;
  GetWindowThreadProcessId(window, &process);
  if (process == GetCurrentProcessId()) {
    return nullptr;
  }

  wchar_t name[32] = {};
  if (GetClassNameW(window, name, 32) > 0 &&
      (wcscmp(name, L"Progman") == 0 || wcscmp(name, L"WorkerW") == 0)) {
    return nullptr;  // The desktop.
  }

  // A title bar rules out maximized windows, which with an auto-hidden
  // taskbar also cover the whole monitor.
  if ((GetWindowLongW(window, GWL_STYLE) & WS_CAPTION) == WS_CAPTION) {
    return nullptr;
  }

  HMONITOR monitor = MonitorFromWindow(window, MONITOR_DEFAULTTONULL);
  MONITORINFO info = {};
  info.cbSize = sizeof(info);
  RECT rect = {};
  if (monitor == nullptr || !GetMonitorInfoW(monitor, &info) ||
      !GetWindowRect(window, &rect)) {
    return nullptr;
  }
  if (rect.left > info.rcMonitor.left || rect.top > info.rcMonitor.top ||
      rect.right < info.rcMonitor.right ||
      rect.bottom < info.rcMonitor.bottom) {
    return nullptr;
  }

  // Exclusive fullscreen shows no other window, and a DXGI game can give up
  // fullscreen when one covers it. Not knowing counts as exclusive.
  QUERY_USER_NOTIFICATION_STATE state;
  if (FAILED(SHQueryUserNotificationState(&state)) ||
      state == QUNS_RUNNING_D3D_FULL_SCREEN) {
    return nullptr;
  }
  return window;
}

// Puts [bgra] in [window] at [where], with per-pixel alpha.
bool PaintPanel(HWND window, const std::vector<uint8_t>& bgra, int width,
                int height, POINT where) {
  BITMAPINFO info = {};
  info.bmiHeader.biSize = sizeof(info.bmiHeader);
  info.bmiHeader.biWidth = width;
  info.bmiHeader.biHeight = -height;  // Top-down, like Dart's rows.
  info.bmiHeader.biPlanes = 1;
  info.bmiHeader.biBitCount = 32;
  info.bmiHeader.biCompression = BI_RGB;

  HDC screen = GetDC(nullptr);
  HDC memory = CreateCompatibleDC(screen);
  void* bits = nullptr;
  HBITMAP bitmap =
      CreateDIBSection(memory, &info, DIB_RGB_COLORS, &bits, nullptr, 0);
  bool painted = false;
  if (bitmap != nullptr) {
    std::memcpy(bits, bgra.data(), bgra.size());
    HGDIOBJ previous = SelectObject(memory, bitmap);
    SIZE size = {width, height};
    POINT origin = {0, 0};
    BLENDFUNCTION blend = {AC_SRC_OVER, 0, 255, AC_SRC_ALPHA};
    painted = UpdateLayeredWindow(window, screen, &where, &size, memory,
                                  &origin, 0, &blend, ULW_ALPHA) != FALSE;
    SelectObject(memory, previous);
    DeleteObject(bitmap);
  }
  DeleteDC(memory);
  ReleaseDC(nullptr, screen);
  return painted;
}

}  // namespace

GameOverlay::GameOverlay(flutter::BinaryMessenger* messenger)
    : channel_(std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          messenger, kChannelName,
          &flutter::StandardMethodCodec::GetInstance())) {
  // Nothing is hooked or created until Dart starts the overlay, so a second
  // Rooster that only hands over to the first never does either.
  channel_->SetMethodCallHandler([this](const auto& call, auto result) {
    OnMethodCall(call, std::move(result));
  });
}

GameOverlay::~GameOverlay() {
  channel_->SetMethodCallHandler(nullptr);
  Stop();
  if (g_class_registered) {
    UnregisterClassW(kWindowClass, GetModuleHandleW(nullptr));
    g_class_registered = false;
  }
}

void GameOverlay::OnMethodCall(
    const flutter::MethodCall<flutter::EncodableValue>& call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  const auto* args = std::get_if<flutter::EncodableMap>(call.arguments());
  if (call.method_name() == "start") {
    Start();
    result->Success(flutter::EncodableValue(State()));
  } else if (call.method_name() == "stop") {
    Stop();
    result->Success();
  } else if (call.method_name() == "setPanel") {
    if (args == nullptr || !SetPanel(*args)) {
      result->Error("bad-arguments",
                    "setPanel takes id, corner, width, height and pixels");
      return;
    }
    result->Success();
  } else if (call.method_name() == "removePanel") {
    const auto* id = args == nullptr ? nullptr : Find(*args, "id");
    if (id == nullptr || !std::holds_alternative<int32_t>(*id)) {
      result->Error("bad-arguments", "removePanel takes an id");
      return;
    }
    RemovePanel(std::get<int32_t>(*id));
    result->Success();
  } else {
    result->NotImplemented();
  }
}

void GameOverlay::Start() {
  // A Dart restart starts again from nothing: drop what the last one showed.
  for (auto& [id, panel] : panels_) {
    DestroyWindow(panel.window);
  }
  panels_.clear();

  g_overlay = this;
  if (hook_ == nullptr) {
    // Out of context: Windows tells this thread, on its own message loop.
    // An in-context hook would load code into other processes, the game's
    // included.
    hook_ = SetWinEventHook(EVENT_SYSTEM_FOREGROUND, EVENT_SYSTEM_FOREGROUND,
                            nullptr, OnForegroundChanged, 0, 0,
                            WINEVENT_OUTOFCONTEXT);
  }
  if (timer_ == 0) {
    timer_ = SetTimer(nullptr, 0, kCheckIntervalMs, OnTimer);
  }

  game_ = nullptr;
  Check();
}

void GameOverlay::Stop() {
  if (hook_ != nullptr) {
    UnhookWinEvent(hook_);
    hook_ = nullptr;
  }
  if (timer_ != 0) {
    KillTimer(nullptr, timer_);
    timer_ = 0;
  }
  for (auto& [id, panel] : panels_) {
    DestroyWindow(panel.window);
  }
  panels_.clear();
  game_ = nullptr;
  if (g_overlay == this) {
    g_overlay = nullptr;
  }
}

bool GameOverlay::SetPanel(const flutter::EncodableMap& args) {
  const auto* id = Find(args, "id");
  const auto* corner = Find(args, "corner");
  const auto* width = Find(args, "width");
  const auto* height = Find(args, "height");
  const auto* pixels = Find(args, "pixels");
  if (id == nullptr || corner == nullptr || width == nullptr ||
      height == nullptr || pixels == nullptr ||
      !std::holds_alternative<int32_t>(*id) ||
      !std::holds_alternative<std::string>(*corner) ||
      !std::holds_alternative<int32_t>(*width) ||
      !std::holds_alternative<int32_t>(*height) ||
      !std::holds_alternative<std::vector<uint8_t>>(*pixels)) {
    return false;
  }
  const int w = std::get<int32_t>(*width);
  const int h = std::get<int32_t>(*height);
  const auto& rgba = std::get<std::vector<uint8_t>>(*pixels);
  if (w <= 0 || h <= 0 || w > kMaxPanelSide || h > kMaxPanelSide ||
      rgba.size() != static_cast<size_t>(w) * static_cast<size_t>(h) * 4) {
    return false;
  }

  Panel& panel = panels_[std::get<int32_t>(*id)];
  if (panel.window == nullptr) {
    panel.window = CreatePanelWindow();
    if (panel.window == nullptr) {
      panels_.erase(std::get<int32_t>(*id));
      return false;
    }
  }
  panel.corner = std::get<std::string>(*corner);
  panel.width = w;
  panel.height = h;
  // Dart draws premultiplied RGBA (ImageByteFormat.rawRgba).
  panel.bgra.resize(rgba.size());
  for (size_t i = 0; i < rgba.size(); i += 4) {
    panel.bgra[i] = rgba[i + 2];
    panel.bgra[i + 1] = rgba[i + 1];
    panel.bgra[i + 2] = rgba[i];
    panel.bgra[i + 3] = rgba[i + 3];
  }
  Layout(false);
  return true;
}

void GameOverlay::RemovePanel(int32_t id) {
  auto it = panels_.find(id);
  if (it == panels_.end()) {
    return;
  }
  DestroyWindow(it->second.window);
  panels_.erase(it);
  Layout(false);
}

void GameOverlay::Check() {
  HWND game = FullscreenWindowInFront();
  RECT screen = {};
  UINT dpi = dpi_;
  if (game != nullptr) {
    HMONITOR monitor = MonitorFromWindow(game, MONITOR_DEFAULTTONEAREST);
    MONITORINFO info = {};
    info.cbSize = sizeof(info);
    GetMonitorInfoW(monitor, &info);
    screen = info.rcMonitor;
    dpi = FlutterDesktopGetDpiForMonitor(monitor);
  }
  if (game == game_ && EqualRect(&screen, &screen_) && dpi == dpi_) {
    return;
  }

  const bool was_in_front = game_ != nullptr;
  const bool dpi_changed = dpi != dpi_;
  game_ = game;
  screen_ = screen;
  dpi_ = dpi;
  Layout(true);

  if (was_in_front != (game != nullptr) || dpi_changed) {
    channel_->InvokeMethod("onGameChanged",
                           std::make_unique<flutter::EncodableValue>(State()));
  }
}

void GameOverlay::Layout(bool raise) {
  const int margin = MulDiv(kMargin, dpi_, USER_DEFAULT_SCREEN_DPI);
  const int gap = MulDiv(kGap, dpi_, USER_DEFAULT_SCREEN_DPI);
  // How far down (top corners) or up (bottom corners) the next panel goes.
  std::map<std::string, int> stacked;

  for (auto& [id, panel] : panels_) {
    if (game_ == nullptr) {
      if (panel.shown) {
        ShowWindow(panel.window, SW_HIDE);
        panel.shown = false;
      }
      continue;
    }

    const bool left = panel.corner == "topLeft" || panel.corner == "bottomLeft";
    const bool top = panel.corner == "topLeft" || panel.corner == "topRight";
    int& offset = stacked.try_emplace(panel.corner, margin).first->second;
    POINT where = {
        left ? screen_.left + margin : screen_.right - margin - panel.width,
        top ? screen_.top + offset : screen_.bottom - offset - panel.height};
    offset += panel.height + gap;

    if (!PaintPanel(panel.window, panel.bgra, panel.width, panel.height,
                    where)) {
      continue;
    }
    if (raise || !panel.shown) {
      SetWindowPos(panel.window, HWND_TOPMOST, 0, 0, 0, 0,
                   SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE | SWP_SHOWWINDOW);
      panel.shown = true;
    }
  }
}

flutter::EncodableMap GameOverlay::State() const {
  return flutter::EncodableMap{
      {flutter::EncodableValue("inFront"),
       flutter::EncodableValue(game_ != nullptr)},
      {flutter::EncodableValue("scale"),
       flutter::EncodableValue(static_cast<double>(dpi_) /
                               USER_DEFAULT_SCREEN_DPI)},
  };
}

void CALLBACK GameOverlay::OnForegroundChanged(HWINEVENTHOOK /* hook */,
                                               DWORD /* event */,
                                               HWND /* window */,
                                               LONG /* object */,
                                               LONG /* child */,
                                               DWORD /* thread */,
                                               DWORD /* time */) {
  if (g_overlay != nullptr) {
    g_overlay->Check();
  }
}

void CALLBACK GameOverlay::OnTimer(HWND /* window */, UINT /* message */,
                                   UINT_PTR /* id */, DWORD /* time */) {
  if (g_overlay != nullptr) {
    g_overlay->Check();
  }
}
