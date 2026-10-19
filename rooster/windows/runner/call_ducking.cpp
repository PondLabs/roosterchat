#include "call_ducking.h"

#include <audiopolicy.h>
#include <mmdeviceapi.h>
#include <windows.h>
#include <wrl/client.h>

#include <vector>

using Microsoft::WRL::ComPtr;

namespace {

// Held for the life of the process: a session with no one holding it can go,
// and the one WebRTC opens later would come back without the preference.
// Leaked on purpose: a static destructor would release these after
// CoUninitialize.
auto* held_sessions = new std::vector<ComPtr<IAudioSessionControl2>>();

void OptOut(IMMDeviceCollection* devices,
            std::vector<ComPtr<IAudioSessionControl2>>& sessions) {
  UINT count = 0;
  devices->GetCount(&count);
  for (UINT i = 0; i < count; i++) {
    ComPtr<IMMDevice> device;
    ComPtr<IAudioSessionManager2> manager;
    ComPtr<IAudioSessionControl> control;
    ComPtr<IAudioSessionControl2> control2;
    if (FAILED(devices->Item(i, &device)) ||
        FAILED(device->Activate(__uuidof(IAudioSessionManager2), CLSCTX_ALL,
                                nullptr, &manager)) ||
        // The process's default session, the one WebRTC's streams join.
        FAILED(manager->GetAudioSessionControl(nullptr, 0, &control)) ||
        FAILED(control.As(&control2))) {
      continue;
    }
    control2->SetDuckingPreference(TRUE);
    sessions.push_back(control2);
  }
}

}  // namespace

void OptOutOfCallDucking() {
  ComPtr<IMMDeviceEnumerator> enumerator;
  if (FAILED(CoCreateInstance(__uuidof(MMDeviceEnumerator), nullptr,
                              CLSCTX_ALL, IID_PPV_ARGS(&enumerator)))) {
    return;
  }
  std::vector<ComPtr<IAudioSessionControl2>> sessions;
  for (EDataFlow flow : {eRender, eCapture}) {
    ComPtr<IMMDeviceCollection> devices;
    if (SUCCEEDED(enumerator->EnumAudioEndpoints(flow, DEVICE_STATE_ACTIVE,
                                                 &devices))) {
      OptOut(devices.Get(), sessions);
    }
  }
  held_sessions->swap(sessions);
}
