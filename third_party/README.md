# third_party

Vendored copies of packages this repo needs to modify. We do not push changes
back to their origin; we change them here.

| Directory | Origin | Ref |
|-----------|--------|-----|
| `livekit-client-sdk-flutter` | https://github.com/commetchat/livekit-client-sdk-flutter (branch `hkdf`) | `19f6b86d7a391876aceabf8ef3e117d399c23899` (2026-05-23) |
| `flutter-webrtc` | https://github.com/flutter-webrtc/flutter-webrtc (tag `1.6.2+hotfix.2`) | `d77879b` (2026-09) |
| `tray_manager` | https://pub.dev/packages/tray_manager | `0.5.3` (2026-09) |
| `flutter_web_auth_2` | https://github.com/ThexXTURBOXx/flutter_web_auth_2 (tag `v4.1.0`) | `4.1.0` (2026) + cutover: `desktop_webview_window` dependency and `lib/src/webview.dart` deleted, `linows.dart` always uses the external-browser loopback server |
| `flutter_inappwebview_windows_stub` | purpose-built cutover stub (no upstream) | `0.0.0-cutover.1`: keeps the `flutter_inappwebview_windows` plugin name with a no-op native registration; links no WebView2 |
| `deep_filter` | https://github.com/Rikorose/DeepFilterNet (`libDF/`, `models/DeepFilterNet3_onnx.tar.gz`, MIT or Apache-2.0) | `d375b2d8309e0935d165700c91da9de862a99c31` (2024-10-17), trimmed to the real-time inference |
| `flutter_vodozemac` | https://pub.dev/packages/flutter_vodozemac | `0.5.0` (2026-10) + the `windows-arm64` cargokit target |
| `media_kit_libs_windows_video` | https://pub.dev/packages/media_kit_libs_windows_video | `1.0.11` (2026-10) + arm64 libmpv and ANGLE |
| `three_js_angle_renderer` | https://pub.dev/packages/three_js_angle_renderer (MIT) | `0.0.1` (2026-11) + the tone-mapping program check |
| `matrix-dart-sdk` | https://github.com/commetchat/matrix-dart-sdk (branch `upstream-v6.1.1`, AGPL-3.0) | `58e0bd24c6a2d74d727dc92a24dc076144fae43b` (2026-03-09), complete and unchanged |

`example/`, `test/`, `testfiles/`, `.github/` and git metadata were dropped
from the copies, except in `matrix-dart-sdk`, which keeps everything but
`.git` so its own tests run and it matches the pub cache checkout file for
file. Local changes are marked with `// ROOSTER:` comments in Dart and C++
and listed in `docs/voice-audio-processing.md`.

`three_js_angle_renderer` (Sunny Side Putt's 3D renderer) decided on every
draw whether a material's program had to change by comparing the tone
mapping the program was built with against a local that `setProgram`
assigned to itself, so it was always "none"; every tone-mapped material
(nearly all of them) rebuilt its program parameters and cache key on every
draw of every frame, and `getParameters` gave render targets (the shadow
map) the renderer's tone mapping where three.js gives none, so the depth
materials did the same. Both are fixed and marked `// ROOSTER:` in
`lib/renderers/renderer.dart` and `lib/angle/angle_programs.dart`.

Uploading uniforms was the largest share of the UI thread's time in a
Sunny Side Putt frame (about a quarter of the samples in a CPU profile):
each uniform remembered its last value in a `Map<int, dynamic>`, so every
matrix set hashed 16 keys to compare and, when the matrix had changed
(every draw, for `modelViewMatrix`), cleared the map and boxed 16 doubles
back into it, and every set reached its setter through `dynamic` and a
`Function` field. In `lib/angle/angle_uniforms_helper.dart` the uniforms
now share a typed `AngleUniformNode` interface with a switch over the
setter kind, keep their cache in a list (`UniformCache`), and compare and
copy matrices as a `Float32List`; the values uploaded and when are the
same (`rooster/unit_test/sunny_side_putt/ui/uniform_upload_test.dart`).

On native the renderer drew the shadow map after the scene (a bind of the
null framebuffer brings nothing back there), so the scene read the last
frame's map: shadows a frame late, and a dark flash whenever the map was
remade. `AngleRenderer.restoreScreenFramebuffer`, set by `lib/three_viewer.dart`
when it draws straight into its texture, binds the texture back after the
shadow pass, and shadows draw first on native too. On the shared-FBO path
(Linux, and Windows without a surface producer) the viewer also calls
`glFinish` before telling Flutter of a frame: Flutter samples that same
texture, and with a flush alone it could show a frame still being drawn.
The surface paths swap buffers instead and do not stall. `lib/three_viewer.dart`
also waits for or drops an ANGLE start that a dispose cut short, and reports
a start that failed (`onStartFailed`).

`flutter-webrtc` replaced the commetchat fork (branch `hkdf`, 1.4.1). Upstream
1.6.2 already carries the fork's only change (`KeyDerivationAlgorithm`
handling in the frame cryptor) and adds what we needed it for: system-audio
capture in `getDisplayMedia({audio: true})` on Windows (WASAPI process
loopback) and Linux (PulseAudio / PipeWire monitor source, needs `libpulse`
dev headers at build time). It pulls the prebuilt libwebrtc `m150.7871.01` at
configure time into `flutter-webrtc/third_party/{downloads,libwebrtc}/`, both
gitignored. `// ROOSTER` changes: `LoopbackCapturer::SetRawTap` (packets as
they come off the OS, fed by both capturers) and `rooster_system_audio_reference.h`
with the `roosterStartSystemAudioReference` / `roosterStopSystemAudioReference`
methods in `flutter_webrtc.cc`, which give the voice DSP the system mix as a
loudspeaker reference. `rooster_music_source.h` with the
`roosterCreateMusicTrack` / `roosterStopMusicTrack` methods: a local audio
track fed from Rust (`rooster_music_pull`) by a 10 ms pacing thread, for the
DJ booth (`docs/dj-booth.md`).

`livekit-client-sdk-flutter` carries a backport of the upstream 2.8.0/2.11.0
unpublish fixes (issue #79): `removePublishedTrack` removes every simulcast
codec sender (a backup codec publishes over its own sender) before it disposes
the publication and renegotiates, backup codec state is cleared on unpublish
and before a full-reconnect republish, and the degradation preference is
applied to backup senders too. Marked `// ROOSTER` in
`lib/src/participant/local.dart` and `lib/src/track/local/video.dart`.
On Linux, `linux/task_runner_linux.cc` hands each task to the main loop as
its own callback, which owns it. The runner used to queue tasks and hand the
loop a pointer to itself; an audio visualizer stopped with a level still on
its way from the audio thread (hanging up a call) left a callback that
locked a mutex in the freed runner on the main thread, and the app froze for
good. The integration test caught it (its watchdog's backtrace).
`AudioPublishOptions.stereo` (DJ booth music): `TF_STEREO` on the published
track, `stereo=1;sprop-stereo=1` munged into our offer for it
(`lib/src/core/transport.dart`), and the subscriber answer asks for stereo
wherever the server's offer has it (`lib/src/core/engine.dart`).
`AudioCaptureOptions.copyWith` carries every field
(`lib/src/track/options.dart`): it used to rebuild the options from six of
the nine, so a copy went back to `stopAudioCaptureOnMute: true` and dropped
the `processor`, which took the web AudioWorklet off the track whenever the
microphone was restarted to change one option. `LocalTrack.restartTrack`
(`lib/src/track/local/local.dart`) takes the processor before `stop()`,
which drops it (upstream reads it after, so every restart lost it), and
puts it on before touching the sender, so the raw capture never goes out.
`restartTrack` also takes the new options only once the new capture exists
(upstream took them first, so a capture that could not be opened was never
tried again), opens the new capture before it stops the old one on desktop
and mobile (a failed open leaves the old one sending; the browser has to
close the old one first, or the new one gets its processing), keeps a web
processor across a failed restart, keeps a track that was muted during the
restart muted, and watches the capture it made for its end. A microphone whose capture ended
stays published (`lib/src/participant/local.dart`), for the app's microphone
watch to repair, instead of being unpublished; a microphone opened for a
publish that failed is stopped; and the local participant's lookup by source
no longer falls back to a publication without a source (it took the DJ
booth's music for the microphone). See
`docs/voice-call-health.md`.
`Room.onConnectStep` (`lib/src/core/room.dart`, set on the engine in
`lib/src/core/engine.dart`, with the `ConnectStep` enum in
`lib/src/types/other.dart`) tells the app when each step of a
connect is done (the attempt started, the WebSocket open, the join answered,
the primary peer connection connected), for the `voice_join` timings in
`docs/speed-log.md`. It only reports: the order, the timeouts and what the
SDK does are unchanged.

`deep_filter` is libDF, DeepFilterNet's Rust library, which the voice DSP
(`rust/audio_dsp/src/dfn.rs`) suppresses noise with; crates.io only has an
old version without the inference. Only `src/lib.rs`, `src/tract.rs`, the
DeepFilterNet3 model and the licences were copied, and the manifest keeps
just what the inference needs. `// ROOSTER` changes: the dataset, transforms,
C API, wasm-bindgen and CLI modules dropped; tract 0.21.13 instead of
0.21.4, for its wasm SIMD kernels (a symbol table rename in three places)
and its own ndarray, re-exported as `df::tract::ndarray`; `DEFAULT_MODEL`,
the model's bytes, so a load error is not a panic; the model's path; and on
wasm a getrandom backend that refuses, since tract-onnx's random operators
pull getrandom in and the worker instantiates the wasm without imports.

`tools/voice_dsp/check_contracts.py` fails CI when the `// ROOSTER` count of
any of these packages goes down or a change noise suppression needs goes missing:
raise its floor when you add markers.

Two upstream flutter-webrtc behaviours on desktop that bit us (see
`docs/voice-audio-processing.md`, "Signal chain"): `getUserMedia` selects
the input only from `optional: [{sourceId}]` and records from device 0
otherwise, and `MediaTrackForId` finds local tracks before received ones
with the same id. A third comes from libwebrtc underneath: its audio device
module keeps the microphone as a position in the device list and looks it
up again whenever recording starts, which it does on every unmute. The
`// ROOSTER` change in `common/cpp` (`ReselectRecordingDevice`) selects the
microphone again by id before a local audio track is enabled.
The iOS and macOS podspecs pin `WebRTC-SDK` to `150.7871.01`, the version the
vendored `flutter-webrtc` pins (upstream livekit_client made the same move in
2.13.0). CocoaPods installs a single copy of the pod, so if the two pins
differ `pod install` fails. Bump them together.

`tray_manager` shows the system tray icon (voice status: idle, live, muted).
The `// ROOSTER` change makes the Linux appindicator optional: without
`libayatana-appindicator3-dev` (or `libappindicator3-dev`) at build time the
plugin still builds, answers every call with "not implemented", and the app
runs without a tray icon, instead of the build failing (the Flatpak runtime
has no appindicator). Marked in `linux/CMakeLists.txt` and
`linux/tray_manager_plugin.cc`.

`flutter_vodozemac` builds vodozemac's Rust bindings with its own copy of
cargokit, which (like ours in `rust/rust_builder/cargokit`, patched the same
way) listed no `aarch64-pc-windows-msvc` target: a Windows arm64 build had
no E2EE library. The `// ROOSTER` change in
`cargokit/build_tool/lib/src/target.dart` adds the `windows-arm64` entry
upstream cargokit has.

`media_kit_libs_windows_video` fetches libmpv and ANGLE at configure time,
upstream for x64 only; an arm64 process cannot load them (no video, no
soundboard). The `// ROOSTER` change in `windows/CMakeLists.txt` takes the
arm64 builds when `FLUTTER_TARGET_PLATFORM` is `windows-arm64`: libmpv from
media-kit's own `libmpv-win32-video-cmake` (20241021, aarch64) and ANGLE from
the fork behind media-kit/media-kit#1436 (Carapacik's v1.1.0, built from
chromium/8059), both pinned by SHA-256. The x64 inputs are upstream's,
unchanged.

`matrix-dart-sdk` is the Matrix SDK (`package:matrix`) the app and
`matrix_dart_sdk_drift_db` use, copied from the commit `pubspec.lock`
resolved (`58e0bd24c6a2d74d727dc92a24dc076144fae43b`, the
`upstream-v6.1.1` branch of the commetchat fork) with no line changed.
Every later change to it is marked with a `// ROOSTER` comment, so a
`diff -r -x .git` against that commit shows only our changes. Git stores
`lib/msc_extensions/msc_1236_widgets/src/widget.dart` with LF line endings
where upstream has CRLF (`* text=auto`); compare with `--strip-trailing-cr`.
Changes since the copy:

- `scripts/*.sh` are executable again (mode 755), as in the fork; the copy
  had lost the mode.
- `test/html_to_text_test.dart` expects a link's text without the 🔗 prefix,
  as the fork's `lib/src/utils/html_to_text.dart` writes it (2 cases).
- The upload loop of `Room.sendFileEvent` (`lib/src/room.dart`, with the
  rules in the new `lib/src/utils/file_upload_loop.dart`): the file and its
  thumbnail upload together; each part that fails is tried again by itself
  at most twice, after 2 s and 8 s, waits for a `retry_after_ms` of up to
  8 s, is not tried again after running for more than 60 s, and ends the
  send on a size, permission or authentication error. A part that went up
  is kept with its key and hash (`Room.sendingFileUploads`; not its
  encrypted bytes) until the event is sent or the send is cancelled, so a
  retry uploads only what did not. What to reuse is decided once per send
  (`FilePartSend`), and in an encrypted room the file to upload is only
  ever the encrypted one: a part without its encryption is never uploaded.
  The `uploading` stage is published, and the message stays in
  `sendingQueueEventsByTxId` for the whole send, so its pending event read
  again during a long upload is not marked failed.
- `Client.sendClock` (`lib/src/client.dart`): the clock the upload loop
  reads and waits by, given by tests.
- `Client._handleRoomEvents` (`lib/src/client.dart`): a timeline event
  that comes back under a transaction id lets go of the file kept to send
  that message again (`Room.forgetFileSend`): it reached the room, even
  when our `PUT /send` failed.
- `Event.sendAgain` (`lib/src/event.dart`): a file message whose event
  carries its uploads' address (`url`, or `file` in an encrypted room) is
  sent again as that event, under the same transaction id, with no upload.
  Not when the room now encrypts files and the event has a `url` (an
  upload in the clear): the file then goes up again, encrypted.
  `Event.cancelSend` lets go of the file and the parts kept for it.
- Cancel of a message being sent (`Room.cancelSending`, `lib/src/room.dart`
  and `lib/src/event.dart`): a flag per transaction id, kept for good, that
  `Room.sendFileEvent` checks before the encryption, the upload loop before
  each attempt and during its waits, and `Room.sendEvent` while the message
  waits in the room's queue (it leaves the queue at once) and right before
  each `PUT /send`. Each upload runs in a zone whose
  `currentUploadCancel()` the app's HTTP client uses to abort the request
  in flight. From the first `PUT /send` on, the server may have the event:
  `Room.canCancelSend` is false and `Event.cancelSend` throws without
  taking the message away; once the server has taken it, it stays so for
  good, even from an event object read before. The one-second wait
  between attempts of an event ends on a cancel, and an attempt that
  fails after its message was cancelled shows nothing. A cancelled send shows nothing again and takes
  its pending event out of the database and the timelines
  (`Room.dropUnsentEvent`, what `Event.cancelSend` did before, moved,
  with the removal from the database after the fake redaction, which
  would otherwise store the event again).
  `Event.sendAgain` sends no cancelled message.
- At most four upload requests of file messages at once per client
  (`maxUploadsAtOnce` in `lib/src/utils/file_upload_loop.dart`), across
  messages, in the order they came.
- A file message whose uploads went up in the clear is not sent once its
  room encrypts files (`uploadedInTheClear` of `Room.sendEvent`, read with
  the event's own encryption in `_sendContent`): the send fails, and a
  retry uploads the file again, encrypted.
- `FileSendRequestCredentials` keeps the thread a file message goes to,
  and `Event.sendAgain` passes it on when the file is uploaded again.
- A file sent from disk (`lib/src/utils/file_send_source.dart`): a
  `MatrixFile` may carry a `FileSendSource` instead of its bytes (its
  `size` is then the source's length, and `encrypt()` refuses it). The
  upload loop opens a new read of it at each attempt
  (`FileSendSource.read`, or `readEncrypted` in an encrypted room, with a
  new key), sends it as a stream (`Client.uploadContentStream`, which
  checks the server's limit before reading), closes it before the attempt
  ends (also on a cancel), and takes the key, iv and hash its event
  carries from the read that went up (`uploadFileParts` gives
  `UploadedFilePart`s). A read that ends short, or a file that changed
  since it was attached, ends the send with `FileSourceChangedException`,
  without a new attempt. `Room.sendFileEvent` checks the server's limit by
  `MatrixFile.size`, and `Event.downloadAndDecryptAttachment` gives no
  file with no bytes for a message still being sent from disk.
