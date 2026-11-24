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
  would otherwise store the event again). A message cancelled while
  `Room.sendEvent` stores its failure (an encryption refused for good) is
  taken out again once that is stored, so no row of it is left.
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
- Photos sent before their upload (the app's
  `lib/client/matrix/media/async_photo_send.dart`): `runUploadToReserved`
  (`lib/src/client.dart`) runs the upload loop of a part in a zone where
  `Client.uploadContent` puts the bytes to an mxc reserved before
  (`PUT /upload/{serverName}/{mediaId}`, an `M_CANNOT_OVERWRITE_MEDIA`
  answer counted as an earlier attempt that landed), and
  `uploadContentStream` refuses to run there. `Room.uploadsAfterEvent`
  and `uploadsAfterEventEnded` (`lib/src/room.dart`) mark a message whose
  event was sent while its uploads run: `Room.canCancelSend` is true for
  it until they end, so its cancel stops them. `Room.showFileMessage`
  shows a file message of this device, being sent or failed, without
  sending anything, keeping its file as `sendFileEvent` does;
  `Room.showFailedMessage` shows a failed message with any content and
  keeps nothing (a photo whose upload the app's closing cut short).
- Room keys for who just came in (T8.1): `Room.getUserDeviceKeys`
  (`lib/src/room.dart`), which every room key share reads, first calls
  the new `Client.updateStaleUserDeviceKeys` (`lib/src/client.dart`): the
  invited and joined members whose device list was never queried or is
  marked outdated are queried, and the share waits for the answer. Before,
  a message sent before the sync's own query answered (it runs after the
  sync that brought them in) never reached their devices. A user whose
  homeserver failed is not asked again for 5 min, nor one left
  unanswered for 1 min. The share waits for that query 10 s at most
  (`Client.staleDeviceKeysTimeout`, what the query lets the homeserver
  wait for other servers), then goes to the devices known; the answer
  that comes later counts for the next send. `Client.updateUserDeviceKeys` takes
  `onlyAdditionalUsers` for that query, and puts each parsed device list
  in place whole. Who gets the key is unchanged (`Client.shareKeysWith`);
  `KeyManager._createOutboundGroupSession`
  (`lib/encryption/key_manager.dart`) logs how many devices of the room's
  members the key leaves out, with no ids.
- Matrix v1.1–v1.19 compliance quick fixes (T0.1):
  `Client.supportedVersions` (`lib/src/client.dart`) covers `v1.1` through
  `v1.19`, and `Client.checkHomeserver` accepts newer `v1.x` versions while
  throwing `BadServerVersionsException` instead of `assert(false)` when no
  compatible version is advertised. OIDC `expires_in` in
  `lib/msc_extensions/msc_2964_oidc_login_flow/msc_2964_oidc_login_flow.dart`
  and `Client.refreshAccessToken` (`lib/src/client.dart`) uses
  `Duration(seconds:)` (preserving milliseconds for legacy `/v3/refresh`
  `expires_in_ms`) and treats missing, zero, or negative lifetimes as null.
  `Room.sendEvent` (`lib/src/room.dart`) no longer emits `<mx-reply>` HTML or
  `> <@user>` plaintext reply fallbacks (Matrix v1.13, MSC2781). VoIP events
  emit stable `sdp_stream_metadata` (`lib/src/voip/models/call_events.dart`,
  Matrix v1.10, MSC3077) while `VoIP` (`lib/src/voip/voip.dart`) retains
  fallback reads of `org.matrix.msc3077.sdp_stream_metadata`.
  `Encryption.encryptGroupMessagePayload` (`lib/encryption/encryption.dart`)
  omits deprecated `device_id` and `sender_key` from Megolm payloads
  (Matrix v1.3, MSC3700), and `Event.requestKey` (`lib/src/event.dart`) /
  `Room.requestSessionKey` (`lib/src/room.dart`) accept a nullable `senderKey`
  so undecryptable v1.3 events remain key-requestable. `Room.setPower`
  (`lib/src/room.dart`) throws `RoomCreatorPowerLevelException` for creators
  in room version 12+ and never writes creators into
  `m.room.power_levels.users`.
- Matrix v1.19 SDK core contracts (T1.1a):
  `AuthenticationTypes.oauth` (`'m.oauth'`, Matrix v1.17 MSC4312) in
  `lib/matrix_api_lite/model/auth/authentication_types.dart`.
  `Capabilities` (`lib/matrix_api_lite/generated/model.dart`) adds
  `mForgetForcedUponLeave` (`m.forget_forced_upon_leave`, v1.18 MSC4267) and
  `mPreviewUrl` (`m.preview_url`, v1.20 MSC4452) alongside `mProfileFields`,
  defaulting to `null` when absent. `GetAuthMetadataResponse`
  (`lib/matrix_api_lite/generated/model.dart`) makes `registrationEndpoint` and
  `revocationEndpoint` optional (`Uri?`, with explicit null checks in
  `lib/msc_extensions/msc_2964_oidc_login_flow/msc_2964_oidc_login_flow.dart`
  and
  `lib/msc_extensions/msc_2966_oidc_dynamic_client_registration/msc_2966_oidc_dynamic_client_registration.dart`),
  adds `deviceAuthorizationEndpoint`, `accountManagementUri`,
  `accountManagementActionsSupported`, `clientIdMetadataDocumentSupported`, and
  `scopesSupported`, tolerates absent/null optional fields, and ignores unknown
  extra keys. `MatrixError` (`lib/matrix_api_lite/model/matrix_exception.dart`)
  adds standardized codes (`M_USER_LOCKED`, `M_USER_SUSPENDED`,
  `M_USER_LIMIT_EXCEEDED`, `M_CANNOT_OVERWRITE_MEDIA`, `M_NOT_YET_UPLOADED`,
  `M_MISSING_TOKEN`, `M_WRONG_ROOM_KEYS_VERSION`, `M_DUPLICATE_ANNOTATION`).
  `MatrixException` and `MatrixApi` (`request` and `unexpectedResponse`) parse
  the HTTP `Retry-After` header case-insensitively (delta-seconds and RFC 7231
  HTTP-date in pure web-safe Dart with an injectable clock, Matrix v1.10
  MSC4041) into `retryAfterMs` whenever the JSON body omits `retry_after_ms`,
  ignoring negative or malformed header values without throwing.
- Matrix v1.18–v1.19 event and account data models (T1.1b): `EventTypes`
  (`lib/matrix_api_lite/model/event_types.dart`) adds `RoomImagePack`
  (`m.room.image_pack`) and `ImagePackRooms` (`m.image_pack.rooms`, v1.19
  MSC2545), `RecentEmoji` (`m.recent_emoji`, v1.18 MSC4356), `KeyBackup`
  (`m.key_backup`, v1.19 MSC4287), `InvitePermissionConfig`
  (`m.invite_permission_config`, v1.18 MSC4380), `RoomPolicy`
  (`m.room.policy`, v1.18 MSC4284), `RoomKeyBundle` (`m.room_key_bundle`,
  v1.19 MSC4268) and `RtcMember` (`m.rtc.member`, MSC4143). Their typed
  contents live in `lib/matrix_api_lite/model/matrix_v1_19_models.dart`
  (exported from `lib/matrix_api_lite.dart`): optional fields are read
  tolerantly, unknown keys round-trip through `additionalProperties`, and only
  a missing required field throws, as a `FormatException`. `MatrixImageInfo`
  carries `is_animated` (v1.18 MSC4230), read from events by the
  `imageInfo`/`isAnimated` extension on `MatrixEvent`, and `MatrixEvent` gains
  a typed `replacesState` for `unsigned.replaces_state`. The legacy
  `im.ponies.*` packs (`ImagePackContent`) and `io.element.recent_emoji` are
  unchanged.
- QR key verification reciprocate cancel code (T3.3a):
  `_KeyVerificationMethodQRReciprocate.handlePayload`
  (`lib/encryption/utils/key_verification.dart`) cancels with `m.key_mismatch`
  instead of `m.invalid_message` when `validateStart` rejects an incoming
  `m.reciprocate.v1` start event whose shared secret does not match.
- Olm `sender_device_keys` (T3.1, Matrix v1.15 MSC4147):
  `OlmManager.encryptToDeviceMessagePayload`
  (`lib/encryption/olm_manager.dart`) puts our device keys, as `/keys/query`
  returns them and without `unsigned`, in every Olm payload. On receipt the
  keys must be the sender's, carry the Olm session's Curve25519 key and the
  payload's claimed `keys.ed25519`, and be validly self-signed, or the event
  is discarded (`DecryptException`). A device not known yet is stored
  unverified, with its list marked outdated for the next `/keys/query`;
  divergent keys that collide with a known or previously seen device's
  Curve25519 or Ed25519 key reject the event (`DecryptException`), and no
  known device is ever overwritten.
- Key backup account data (T3.1, Matrix v1.19 MSC4287): `m.key_backup`
  (`{"enabled": bool}`, `KeyBackupContent`) holds the user's choice to use key
  backup. `SSSS.store` (`lib/encryption/ssss.dart`) writes it on when a new
  backup key goes into `m.megolm_backup.v1` (not when the key is copied under
  another storage key). `KeyManager` (`lib/encryption/key_manager.dart`)
  reads it (`keyBackupEnabled` falls back to the presence of
  `m.megolm_backup.v1`), updates `client.accountData` and the local database
  after `setKeyBackupEnabled` and `deleteKeyBackup`, stops uploading keys
  while it is off, and adds
  `getKeyBackupStatus`, `createKeyBackup` (creation and rotation, deleting the
  replaced version only after the new key is stored), `deleteKeyBackup`
  (turns it off and empties the stored key) and
  `restoreKeyBackupWithRecoveryKey` (a backup whose key is not in secret
  storage).
- Matrix v1.16 sync (`state_after`, `use_state_after`), v1.4 thread unread
  counts (`unread_thread_notifications`), and v1.15 Rich Topics (`m.topic`)
  (T1.2):
  `JoinedRoomUpdate` and `LeftRoomUpdate`
  (`lib/matrix_api_lite/model/sync_update.dart`) deserialize and serialize
  `state_after` (v1.16 MSC4222) and `JoinedRoomUpdate` parses
  `unread_thread_notifications` (v1.4 MSC3773), skipping malformed entries
  without crashing sync. `Client._innerSync` (`lib/src/client.dart`) sends
  `use_state_after=true` only when the server advertises a semantic Matrix
  version `>= v1.16` (omitting it on `<= v1.15` or unknown versions; the
  versions come from `getVersions()`, cached in the database), and
  `_handleRooms` / `_storeArchivedRoom` apply legacy `state` before timeline
  events and `state_after` after timeline events (respecting `Direction.b`
  guards). A left room's legacy `state` used to be applied after its timeline;
  it now comes before it, as for a joined room. When an update carries
  `state_after`, even an empty one, its timeline does not define room state
  (a timeline state event may have lost state resolution), in memory or in
  the database. A database stores a timeline event that has a state key as
  room state too, and `DatabaseApi.storeEventUpdate` cannot take a parameter
  that says otherwise: the database the app uses outside the browser
  (`matrix_dart_sdk_drift_db`) implements `DatabaseApi` in another package and
  would no longer compile. So `Client._handleRoomEvents` hands such an event
  to the database as a `_TimelineOnlyEvent` (`lib/src/client.dart`), which has
  no state key and writes the real one in its JSON: the event is stored in the
  timeline, whole, and not as room state, in either database.
  `Room.unreadThreadNotifications` (`lib/src/room.dart`) exposes the per-thread
  unread counts. An update that brings `unread_notifications` or
  `unread_thread_notifications` replaces them all, so a thread the server
  leaves out (it has no notifications) is no longer counted. `Room.topic`,
  `Room.topicHtml`, and `Room.setDescription(plain, {html})` read and write
  MSC3765 `m.topic` (`m.text` with `text/plain` and `text/html`) while keeping
  legacy `topic` compatibility on both read and write. The static
  `Room.richTopicRepresentation(content, mimetype)` (T4.4b) is the same parser
  over any `m.room.topic` content, so the app reads each topic change in the
  timeline as it reads the room's current topic.
- Claimed Ed25519 key of `m.room_key` (T3.1b): `KeyManager.handleToDeviceEvent`
  (`lib/encryption/key_manager.dart`) takes the key a received room key
  claims from the sender's device whose Curve25519 key is the Olm session's
  (from `/keys/query` or checked `sender_device_keys`), and claims none when
  there is no such device. Upstream copied the Ed25519 key of the device the
  sender named in `requesting_device_id`, a field the sender controls, so a
  room key sent over any Olm session of that user could claim a verified
  device; `sender_claimed_ed25519_key` and `sender_claimed_keys` written in
  the content are dropped too, since `SessionKey.fromDb` falls back to them
  when the session has no claimed keys of its own. `RoomKeyRequest.forwardKey`
  claims our own key only for sessions we created (upstream claimed it for
  any session without a claimed key), else the key of the device the
  session's Curve25519 key belongs to, and forwards nothing when no key is
  claimed.
- Matrix v1.18–v1.19 Client-Server endpoints (T1.1c):
  `MatrixApi` (`lib/matrix_api_lite/matrix_api.dart`) adds
  `getMutualRooms(userId, {from})` for `GET /_matrix/client/v1/mutual_rooms`
  (v1.19 MSC2666; `GetMutualRoomsResponse` reads `joined`, `count` and
  `next_batch`), and `getUserSuspended` / `setUserSuspended` and
  `getUserLocked` / `setUserLocked` for `GET`/`PUT
  /_matrix/client/v1/admin/suspend/{userId}` and `.../admin/lock/{userId}`
  (v1.18 MSC4323, bodies `{suspended}` and `{locked}`). They are written like
  the generated endpoints, so a `404 M_UNRECOGNIZED` or `403 M_FORBIDDEN`
  comes out as a `MatrixException`; the generated `Api` and its models are
  left as generated. `reportEvent` (`lib/matrix_api_lite/generated/api.dart`)
  keeps `score` optional and deprecated (removed in v1.18 MSC4277), sends it
  only when passed, and takes any 200 as a success without parsing the body.
  `Room.redactEvent` (`lib/src/room.dart`) sends the redaction as an
  `m.room.redaction` event through `PUT /rooms/{roomId}/send` with `redacts`
  (and `reason` when given) in the content when the server advertises a
  `v<major>.<minor>` version `>= v1.18` (v1.18 MSC4169), straight through the
  API so it is never encrypted; with older or unreadable versions, or when
  `/send` answers `M_UNRECOGNIZED`, it uses `PUT /redact` as before.
  `Client.redactEventWithMetadata` (MatrixRTC) still uses `/redact`.
- OAuth 2.0 discovery and sign-in (T2.1a): `Client.getWellknown`
  (`lib/src/client.dart`) follows 301/302/307/308 on
  `/.well-known/matrix/client` itself (MSC4402, Matrix v1.20): each
  `Location` is resolved against the URL it came from, at most
  `Client.maxWellKnownRedirects` (5) hops, only `http`/`https`, and no URL
  twice; anything else throws `WellKnownRedirectException`, which
  `checkHomeserver` passes on instead of treating it as "no well-known file".
  In a browser `fetch` follows the redirects (asking it not to makes it fail).
  `checkHomeserver` asks for `auth_metadata` before `/v3/login`, and with
  metadata in hand a `/v3/login` that answers 404, an error or no flows no
  longer fails the check (servers whose accounts live in MAS). In
  `msc_2964_oidc_login_flow/`, `oidc_authorization.dart` negotiates the scopes
  (`urn:matrix:client:api:*` and `urn:matrix:client:device:<id>` when
  `scopes_supported` lists them, MSC2967's `urn:matrix:org.matrix.msc2967.client:*`
  otherwise; `openid` only when the server lists no scopes or lists it),
  tells whether a server offers Authorization Code with S256 and
  `prompt=create`, and reads the authorization redirect
  (`parseOidcAuthorizationCallback`: a missing or different `state`, an OAuth
  `error` or no `code` throw `OidcCallbackException` before anything is
  exchanged). `initOidcLoginSession` and `oidcLogin` take the metadata already
  fetched, and the session keeps its device ID, scopes and response mode. In
  `msc_2966_oidc_dynamic_client_registration/`, `obtainOidcClient` uses a
  Client ID Metadata Document URL as `client_id` when the server announces
  `client_id_metadata_document_supported: true`, and registers the client
  (RFC 7591) otherwise; `OidcClientRegistrationException` when the server
  offers neither.
- Encrypted history shared on invite (T3.2, Matrix v1.19 MSC4268):
  `lib/encryption/room_key_bundle.dart` (`Encryption.roomKeyBundle`).
  `Room.invite(userId, shareHistory: true)` invites, then bundles the room's
  Megolm sessions marked `shared_history: true` (MSC3061). `KeyManager` marks
  a new outbound session when the room is `shared` or `world_readable`, and
  `clearOrUseOutboundGroupSession` ends the session before the next message
  when its mark no longer matches the room (`shared` to `invited` or
  `joined`, and back), so no marked session encrypts what is said under
  `invited` or `joined`; sessions from before this change never leave. The
  history visibility these decisions use is
  `RoomKeyBundleManager.historyVisibilityOf`: the room's state, or the
  latest `m.room.history_visibility` this session's syncs brought when the
  state in memory has none, and `joined` when the two disagree. The state in
  memory alone misses an event stored while `Room.postLoad` was reading the
  database (the app loads a room as soon as a sync brings it), and then says
  nothing or what the room was before. A message sent before our own sync
  shows the change still goes out on the old session. The invite encrypts
  the bundle as an attachment
  (`encryptFile`), uploads it and sends `m.room_key_bundle` over Olm to the
  invitee's devices whose `encryptToDevice` holds (`Client.shareKeysWith`,
  never blocked). Nothing is uploaded or sent when the room's
  `m.room.history_visibility` is `joined` or absent, the invitee is banned,
  or there is no device or no session to share. The invitee reads the
  stable and the unstable (`io.element.msc4268.room_key_bundle`) types, only
  over Olm and from a known, unblocked device of the sender (signed by its
  master key when the sender has one), keeps it until the sync is through
  and takes it in once it joins, only if the sender is who invited it (seen
  while the invite was active, at most a day before); leaving drops it,
  and at most 20 bundles wait at a time. The download (the
  authenticated media path when the server has it) stops past 10 MiB before
  anything is decrypted, the SHA-256 must match, and every session must be a
  Megolm session of that room whose key gives its `session_id`, or nothing
  is imported. An import never replaces a session received directly
  (`m.room_key`, empty forwarding chain) or one known from as early an
  index, claims the key of the known device the session's Curve25519 key
  belongs to (as T3.1b does for `m.room_key`), and adds the bundle sender's
  Curve25519 key to the forwarding chain. `onImported`, `onRejected` and
  `lastImport` tell the app. Pending bundles and inviters live in memory.
- Inbound Megolm sessions compared with the database (T3.4b):
  `KeyManager.setInboundGroupSession` compares the new session with the one
  in memory or, when none is there (as after a restart), with the one the
  database keeps, and keeps whichever starts at the earlier index (or, at the
  same index, has the shorter forwarding chain). Upstream compared only with
  memory, so after a restart a session from the key backup, a forwarded key,
  an import or a bundle that starts later replaced a stored one from index 0
  and earlier messages stopped decrypting. The stored session is read
  without `loadInboundGroupSession` (which writes it into memory after the
  read, over what a concurrent call may have just set), and memory is checked
  again after the read, so of two calls at once the better session still
  wins. A stored session that wins goes in memory, where callers look next.
  An unreadable stored session is replaced.
- Dehydrated devices, opt-in (MSC3814, T3.5): `dehydratedDeviceSetup`
  asks nothing of a server that does not announce `org.matrix.msc3814` in
  `unstable_features` of `/versions` (`dehydratedDevicesSupported`; no spec
  version has the stable endpoints yet) and returns a
  `DehydratedDeviceResult` instead of nothing. Only a 404 makes a new
  dehydrated device; upstream also replaced it on any other error answer
  but a 400 (a 403, a 429...), dropping the events waiting for it. A key that is missing from secret
  storage (`org.matrix.msc3814`) or does not open the device leaves the
  device on the server (`keyMismatch`). The device's cross-signing chain
  may end at a master key whose private key is in the secret storage just
  unlocked, as after a login the device is read while the session is being
  verified, before its master key is marked (upstream replaced it then).
  The room keys go to the session's own key manager (memory and database,
  through `setInboundGroupSession`), an event that does not decrypt is
  skipped, and a repeated `next_batch` ends the loop. Nothing of the
  session's own account or Olm sessions changes on any failure.
  `deleteDehydratedDevice` and `deleteDehydratedDeviceIfSupported` are
  MSC3814's DELETE, for turning the opt-in off.
- Sync filter defined again when it changed (T4.3): `Client._checkSyncFilter`
  (`lib/src/client.dart`) used to define the sync filter once per login and
  keep its id for ever, so a session never got a filter the app changed
  later. Rooster now asks for per-thread unread counts in it (Matrix v1.4,
  MSC3773, `room.timeline.unread_thread_notifications`). The filter an id
  was defined from is kept with `cacheCustomObject`
  (`rooster_defined_sync_filter`), read once per run, and a different one
  (or none, as in every session from before) defines the filter again and
  stores the new id. When that definition fails (the server is unreachable
  or refuses it), the session keeps the id it had and goes on syncing with
  it, the failure is logged, and the next run tries again; a login with no
  id yet still fails its sync, as upstream. `DatabaseApi` does not change,
  so the drift database still compiles. The SDK's `clearCache` empties
  custom cache objects too, which costs one more definition after it.
- Per-thread unread counts kept across restarts (T4.3): with
  `unread_thread_notifications` in the filter the server leaves the threads
  out of a room's own counts, and neither database's `storeRoomUpdate`
  stores `Room.unreadThreadNotifications` (`DatabaseApi` cannot take them:
  the drift database implements it in another package). So a sync that
  changes them (a new room that has some, a room whose counts change, a
  room left) writes every room's counts once, at the end of
  `Client.handleSync`, with `cacheCustomObject`
  (`rooster_unread_thread_notifications`), and `Client.init` puts them back
  on the joined rooms it loads. `Client.storeUnreadThreadNotifications()`
  writes them on demand, for the app clearing a thread it read before the
  next sync says so. A store that fails is logged and tried again with the
  next sync; an unreadable cache is skipped. Without this, a room with
  unread thread replies looked read after a restart until a sync brought
  its counts again.
- Simplified Sliding Sync (T5.1, MSC4186, Matrix 2.0): `lib/src/sliding_sync/`
  holds the request and connection (`sliding_sync_transport.dart`), the
  answer turned into the `/v3/sync` shape (`sliding_sync_hydration.dart`)
  and what keeps E2EE whole across a change of transport
  (`sync_transport_continuity.dart`); `Client._innerSync` picks the
  transport. The loop uses Sliding Sync only when `/_matrix/client/versions`
  announces `org.matrix.simplified_msc3575` (the unstable path) or
  `org.matrix.simplified_msc3575.stable` (`/_matrix/client/v5/sync`, tried
  first; a refusal there falls to the unstable path) and
  `Client.forceLegacySync` is off. Everywhere else `/v3/sync` runs as
  before: no request, no write, and one custom cache read per run. A
  request sends `conn_id`, one list (`all_rooms`, every state event as
  `/v3/sync` gives, its range grown 50 rooms a request until it covers
  every room, without waiting while it grows), the room subscriptions
  (`Client.slidingSync?.subscribeRoom`) and the `to_device`, `e2ee`,
  `account_data`, `receipts` and `typing` extensions. The answer becomes
  a `SyncUpdate` handled by the same `_handleSync` (`required_state` is
  the state after the timeline, so it goes in as `state_after`), so
  rooms, account data, to-device messages, one-time key counts and device
  lists take the path they take from `/v3/sync`. `pos` and the to-device
  `since` move only after the answer is processed. `M_UNKNOWN_POS` drops
  `pos` (never the to-device `since`) and asks once more at once; a second
  refusal is a sync error, waited out like any other, never a logout. A
  404, 405 or `M_UNRECOGNIZED` sends the loop back to `/v3/sync` for the
  rest of the run (`Client.slidingSyncFallbackReason`).
  How the change keeps to-device messages and device lists: the two
  transports have independent positions. `/v3/sync` keeps its own token
  while Sliding Sync runs (the one stored stays the `/v3` one; `prevBatch`
  only holds `pos` in memory, so notifications know the session is past
  its first sync), saved as `legacy_since` when Sliding Sync takes over,
  and goes on from it when it comes back. The custom cache object
  `rooster_sliding_sync`, written in the sync's transaction, holds the
  transport, `pos`, the to-device `since`, the to-device messages of the
  last sync (a short hash of sender, type and canonical content) and the
  users Sliding Sync reported in `device_lists`. The server deletes
  to-device messages only when the next request of the same transport
  acknowledges them, so the first sync of the other transport gets the
  last batch again: it is dropped by its hashes. A `/v3/sync` from the old
  token reports again every device list change Sliding Sync reported: the
  repeats are dropped, and a tracked user among them whose keys were
  downloaded since gets them downloaded once more, since the old token
  cannot tell a repeat from a newer change. A sync that cannot say what
  changed (a Sliding Sync connection without `pos`, after `M_UNKNOWN_POS`
  or taking over from `/v3/sync`, and an initial `/v3/sync` when there was
  no `/v3` token) marks every tracked device list outdated, so their keys
  are downloaded again. The state survives a restart, so a change of
  transport between runs is handled the same way. `clearCache` drops
  `pos` and `legacy_since` and keeps the to-device position. `DatabaseApi`
  does not change.
  A room sent `initial` (the first time on a connection: a new
  connection, or the range growing over it) brings the room as it is, so
  its events notify no one and raise no call event, as in an initial
  `/v3/sync`; a `limited` timeline that overlaps the newest stored events
  keeps them (no gap), one that does not drops them as `/v3/sync` does.
  An answer without `count` stops growing the range, and one without
  `pos` still waits for news: no polling. Limits of MSC4186: it has no
  per-thread unread counts, so a Sliding Sync update leaves
  `Room.unreadThreadNotifications` as they are (the room's own counts come
  from the server; the per-thread ones change only from `/v3/sync` or a
  thread read here), and it has no presence, so other people's presence
  stops changing while Sliding Sync runs (asking `/presence` for the
  people on screen is left for another task).
- Room keys stored before T3.1b (T6.1): such a session kept, with no claimed
  keys of its own, the Ed25519 key of the device its sender named in
  `requesting_device_id` (or any claim the sender wrote) in its content.
  `SessionKey.fromDb` no longer reads a claim from the content of a session
  that was not forwarded, so it claims nothing from its first load.
  `KeyManager.migrateClaimedKeysFromOlmSessions`, started by the first
  `Encryption.onSync` (device lists loaded and updated), then goes once per
  database over the stored sessions with that shape: one that a single known
  device has the Olm session's Curve25519 key for claims that device's key;
  any other claims nothing. The claim leaves the content either way, and the
  session is stored again with its own pickle and indexes (nothing is
  deleted, every message still decrypts; it is queued for the key backup
  again). The mark is the custom cache object
  `rooster_claimed_keys_from_olm_session` (`DatabaseApi` does not change);
  `clearCache` drops it, and the next run finds nothing left to change.
  `Encryption.megolmSenderTrust(event)` says whether a decrypted message's
  session proves its sender's device: `verified` or `unverifiedDevice` when
  the session claims the Ed25519 key of the sender's device that holds its
  Curve25519 key, `unverifiedOrigin` when it claims none, another device's,
  or was forwarded.
- MatrixRTC's newer pieces (T5.2: MSC4354, MSC4140, MSC4143):
  sticky events come in `JoinedRoomUpdate.sticky`, from a room's `sticky`
  or `msc4354_sticky` section and from timeline events that carry
  `sticky`/`msc4354_sticky` on top, once per event id; `MatrixEvent` drops
  that top-level object, so its `duration_ms` is kept in `unsigned`
  (`JoinedRoomUpdate.stickyDurationKey`). Sliding Sync asks for them with
  the `org.matrix.msc4354.sticky_events` extension, and the hydration puts
  its rooms' events in the same section, so both transports take the same
  path. `Client` keeps them per room (`RoomStickyEvents`, an extension on
  `Room` backed by an `Expando`, so the app's test doubles that implement
  `Room` keep working): the latest of each sender, type and sticky key,
  decrypted when they come encrypted. An incremental sync hands a sticky
  event out once, so they are written to the custom cache object
  `rooster_msc4354_sticky_events` at the end of a sync that changed them
  and come back in `Client.init`. Whether one still counts is the
  reader's to say, by its own clock (`RoomStickyEvents.stickyExpiresAt`);
  the SDK asks no clock of its own, since this machine's can be hours off
  (pruned by it, every sticky event was forgotten as it arrived on a
  machine three hours ahead). When they are written, a room forgets the
  ones that ended more than an hour (the longest one stays sticky) before
  the newest sticky event one of our own homeserver's users sent there: a
  time that homeserver's clock has reached. Another homeserver's
  timestamps forget nobody's, and a room with no sticky event from ours
  keeps the latest of each sender, type and sticky key. `DatabaseApi` does
  not change.
  Delayed events: `DelayedEventsSupport.of(versions)` is `stable` from
  Matrix v1.20 or with `org.matrix.msc4140.stable`
  (`/_matrix/client/v1/delayed_events`, `?delay=`), else `unstable` with
  `org.matrix.msc4140`, else `none`. `setRoomStateWithKeyWithDelay`,
  `manageDelayedEvent` and `getScheduledDelayedEvents` take a `via`
  (unstable by default, as before), and `DelayedEventCanceller.via`
  remembers where the call extension scheduled its leave, so the leave is
  cancelled there even if `/versions` changes mid-call.
  `getCallMembershipsFromRoom` also lists `m.rtc.member` and
  `org.matrix.msc4143.rtc.member` memberships (state or sticky,
  `RtcMemberships`, `RtcCallMembership.fromRtcMember`), skipping a device
  the legacy memberships already list.
- Room state loaded while a sync is stored (T6.4): `Room.postLoad` reads
  the room's state from the database inside `DatabaseApi.transaction`, and
  marks the room loaded before that transaction ends. A sync stores its
  events in a transaction and, while a room is partial, keeps the state it
  brings out of memory; a read that overlapped it saw the database without
  that sync's writes, so a new room read no `m.room.history_visibility`
  after `postLoad` and one that turned `joined` went on saying `shared` in
  memory. Now the read waits for the sync to be stored, and a later sync
  finds the room loaded. From inside a transaction (a page of history
  checked during the sync) it runs at once, as nested transactions do.
  The race the T3.2 entry above describes is closed there;
  `RoomKeyBundleManager.historyVisibilityOf` stays as a second word, and
  its note of the syncs no longer skips an `m.room.history_visibility`
  dated before the last one seen when it lets out less history (another
  server's clock may run behind): only one that would let out more is
  skipped. `DatabaseApi` does not change.
