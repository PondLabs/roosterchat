#include "splash_window.h"

#include <dwmapi.h>
#include <flutter_windows.h>

#include "resource.h"

namespace {

constexpr const wchar_t kSplashClassName[] = L"ROOSTER_SPLASH_WINDOW";

// WindowManagement.showLauncher's size, in logical pixels.
constexpr int kWidth = 380;
constexpr int kHeight = 440;
constexpr int kIconSize = 160;

#ifndef DWMWA_USE_IMMERSIVE_DARK_MODE
#define DWMWA_USE_IMMERSIVE_DARK_MODE 20
#endif

// LoadingPage's colours, by the same system setting it reads.
bool IsDark() {
  DWORD light_mode = 1;
  DWORD size = sizeof(light_mode);
  RegGetValue(HKEY_CURRENT_USER,
              L"Software\\Microsoft\\Windows\\CurrentVersion\\Themes\\Personalize",
              L"AppsUseLightTheme", RRF_RT_REG_DWORD, nullptr, &light_mode,
              &size);
  return light_mode == 0;
}

LRESULT CALLBACK SplashProc(HWND hwnd, UINT message, WPARAM wparam,
                            LPARAM lparam) {
  switch (message) {
    case WM_PAINT: {
      PAINTSTRUCT ps;
      HDC dc = BeginPaint(hwnd, &ps);
      RECT client;
      GetClientRect(hwnd, &client);
      HBRUSH background =
          CreateSolidBrush(IsDark() ? RGB(0x1B, 0x16, 0x13) : RGB(0xE4, 0xD7, 0xC6));
      FillRect(dc, &client, background);
      DeleteObject(background);

      int icon = MulDiv(kIconSize, GetDpiForWindow(hwnd), 96);
      HICON image = static_cast<HICON>(
          LoadImage(GetModuleHandle(nullptr), MAKEINTRESOURCE(IDI_APP_ICON),
                    IMAGE_ICON, icon, icon, LR_DEFAULTCOLOR));
      if (image) {
        DrawIconEx(dc, (client.right - icon) / 2, (client.bottom - icon) / 2,
                   image, icon, icon, 0, nullptr, DI_NORMAL);
        DestroyIcon(image);
      }
      EndPaint(hwnd, &ps);
      return 0;
    }
    case WM_CLOSE:
      // Closed before the app was up: quit, as closing the app would.
      PostQuitMessage(0);
      return 0;
  }
  return DefWindowProc(hwnd, message, wparam, lparam);
}

}  // namespace

HWND ShowSplashWindow() {
  HINSTANCE instance = GetModuleHandle(nullptr);
  WNDCLASS window_class{};
  window_class.hCursor = LoadCursor(nullptr, IDC_APPSTARTING);
  window_class.lpszClassName = kSplashClassName;
  window_class.hInstance = instance;
  window_class.hIcon = LoadIcon(instance, MAKEINTRESOURCE(IDI_APP_ICON));
  window_class.lpfnWndProc = SplashProc;
  RegisterClass(&window_class);

  // Centred on the main monitor's work area, where windowManager.center()
  // puts the loading window, so the swap does not move anything.
  POINT origin = {0, 0};
  HMONITOR monitor = MonitorFromPoint(origin, MONITOR_DEFAULTTOPRIMARY);
  MONITORINFO info{sizeof(info)};
  GetMonitorInfo(monitor, &info);
  double scale = FlutterDesktopGetDpiForMonitor(monitor) / 96.0;
  int width = static_cast<int>(kWidth * scale);
  int height = static_cast<int>(kHeight * scale);
  const RECT& work = info.rcWork;

  HWND window = CreateWindow(
      kSplashClassName, L"Rooster",
      WS_OVERLAPPED | WS_CAPTION | WS_SYSMENU | WS_MINIMIZEBOX,
      work.left + (work.right - work.left - width) / 2,
      work.top + (work.bottom - work.top - height) / 2, width, height,
      nullptr, nullptr, instance, nullptr);
  if (!window) return nullptr;

  BOOL dark = IsDark();
  DwmSetWindowAttribute(window, DWMWA_USE_IMMERSIVE_DARK_MODE, &dark,
                        sizeof(dark));
  ShowWindow(window, SW_SHOWNORMAL);
  // Painted now: the engine starts on this thread before the message loop.
  UpdateWindow(window);
  return window;
}
