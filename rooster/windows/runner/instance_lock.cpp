#include "instance_lock.h"

#include <windows.h>

namespace {

constexpr wchar_t kLock[] = L"Local\\com.pondlabs.rooster.instance";
constexpr wchar_t kLeaving[] = L"Local\\com.pondlabs.rooster.leaving";

// What WindowManagement.close allows itself before the window is destroyed
// (12 s to leave the calls, 5 s to close the accounts), and as much again
// for the engine. A Rooster still there after that is stuck, and the
// accounts are closed in it either way.
constexpr ULONGLONG kLeavingWaitMs = 30000;

// Held while this is the Rooster that is running. Never closed otherwise,
// so it lasts as long as the process.
HANDLE g_lock = nullptr;

}  // namespace

bool TakeInstanceLock() {
  HANDLE lock = ::CreateMutexW(nullptr, FALSE, kLock);
  if (::GetLastError() == ERROR_ALREADY_EXISTS) {
    // Kept open all the same: should the first one go while this one is
    // still handing over, a third is not a first.
    return false;
  }
  g_lock = lock;
  return true;
}

void LeaveInstanceLock() {
  if (!g_lock) {
    return;
  }
  // Owned by this thread, the one the window runs on, and never released:
  // Windows hands it to whoever waits for it when the process ends. Made
  // before the lock goes, so there is no moment with neither.
  HANDLE leaving = ::CreateMutexW(nullptr, TRUE, kLeaving);
  if (leaving && ::GetLastError() == ERROR_ALREADY_EXISTS) {
    // Left behind by another Rooster closing: not ours until it is taken.
    ::WaitForSingleObject(leaving, 0);
  }
  ::CloseHandle(g_lock);
  g_lock = nullptr;
}

bool WaitForLeavingInstance() {
  HANDLE leaving =
      ::OpenMutexW(SYNCHRONIZE | MUTEX_MODIFY_STATE, FALSE, kLeaving);
  if (!leaving) {
    return true;
  }

  bool carry_on = true;
  const ULONGLONG deadline = ::GetTickCount64() + kLeavingWaitMs;
  while (carry_on) {
    const ULONGLONG now = ::GetTickCount64();
    if (now >= deadline) {
      break;
    }
    const DWORD got = ::MsgWaitForMultipleObjectsEx(
        1, &leaving, static_cast<DWORD>(deadline - now), QS_ALLINPUT,
        MWMO_INPUTAVAILABLE);
    if (got != WAIT_OBJECT_0 + 1) {
      // It has gone (the mutex is ours: abandoned, or released), or the
      // wait failed.
      if (got == WAIT_OBJECT_0 || got == WAIT_ABANDONED_0) {
        ::ReleaseMutex(leaving);
      }
      break;
    }
    ::MSG msg;
    while (::PeekMessage(&msg, nullptr, 0, 0, PM_REMOVE)) {
      if (msg.message == WM_QUIT) {
        carry_on = false;
        break;
      }
      ::TranslateMessage(&msg);
      ::DispatchMessage(&msg);
    }
  }
  ::CloseHandle(leaving);
  return carry_on;
}
