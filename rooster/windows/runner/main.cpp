#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>
#include <iostream>
#include "flutter_window.h"
#include "utils.h"

// ROOSTER: clipboard managers (Win+V, WindowsCM) paste by injecting Ctrl+V
// with SendInput, often without a scan code. Flutter tells keys apart by scan
// code, so Ctrl and V both arrive as the same unknown key, the Ctrl press is
// released when V goes down, and the paste never happens. Give such key
// messages the scan code their virtual key has on the current layout.
static void FillMissingScanCode(::MSG &msg)
{
  switch (msg.message)
  {
  case WM_KEYDOWN:
  case WM_KEYUP:
  case WM_SYSKEYDOWN:
  case WM_SYSKEYUP:
    break;
  default:
    return;
  }

  if (msg.wParam == VK_PACKET || ((msg.lParam >> 16) & 0xff) != 0)
    return;

  UINT scan_code = ::MapVirtualKeyW(static_cast<UINT>(msg.wParam),
                                    MAPVK_VK_TO_VSC_EX);
  if ((scan_code & 0xff) == 0)
    return;

  LPARAM lparam = msg.lParam & ~static_cast<LPARAM>(0x00ff0000);
  lparam |= static_cast<LPARAM>(scan_code & 0xff) << 16;
  if ((scan_code & 0xff00) == 0xe000 || (scan_code & 0xff00) == 0xe100)
    lparam |= static_cast<LPARAM>(1) << 24;
  msg.lParam = lparam;
}

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command)
{
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent())
  {
    CreateAndAttachConsole();
  }

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  // ROOSTER: one Rooster at a time. The named pipe single_instance.dart
  // checks has gaps (between two connections, and while the running one is
  // too busy to answer), and a launch that fell into one ran as a second
  // full copy: two syncs of the same account, two toasts per message. Windows
  // makes this check atomically. The handle is never closed, so the lock
  // lasts as long as the process. A launch that is not the first only hands
  // over to the running one and quits (main.dart).
  ::CreateMutexW(nullptr, FALSE, L"Local\\com.pondlabs.rooster.instance");
  if (::GetLastError() == ERROR_ALREADY_EXISTS) {
    command_line_arguments.push_back("--rooster-secondary");
  }

  flutter::DartProject project(L"data");

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  // ROOSTER: window title shows the fork's name, not upstream's.
  if (!window.Create(L"Rooster", origin, size))
  {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0))
  {
    FillMissingScanCode(msg);
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
