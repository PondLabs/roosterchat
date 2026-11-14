# Face tracking: whoever shows a video follows the face in it

**Status: accepted (2026-11-14) for the browser and Linux, where it was measured. Windows, macOS and Android are decided here and not tested: nobody ran them.**

Cock-a-Doodle-Who? is the game of guessing the plaque on your own forehead, played in a voice channel. Everyone sees, on the others' camera video, a plaque pinned to their forehead: it has to follow the head's position, size and tilt, on every platform Rooster ships for (browser, Linux, Windows, macOS, Android). Before this, Rooster had no face detection of any kind. The only inference engine in the repository was tract (`third_party/deep_filter`), for the voice.

This record says how a plaque follows a face, on which engine on each platform, and what each platform's task touches. The numbers come from throwaway probes run on 2026-11-14 over five test videos; how they are measured is in [tools/face_tracking/README.md](../../tools/face_tracking/README.md).

## Decision

### Whoever shows a video tracks it

Each app finds the faces in the videos it is showing, on its own device. The plaque is worked out from the pictures the app itself is drawing, with no network between the two, and no frame and nothing about a face is sent or kept.

The plaque is not worked out on every frame, though. A plaque on screen comes from the last frame analysed, which is at most one detection old: 100 ms at the ten detections a second R4.3 asks for, 67 ms at the fifteen an engine aims at, plus the few milliseconds the detection takes. R4.2 is measured on the frame that was analysed, by its frame code, not on the frame on screen when the plaque is drawn: it says how well the forehead is found, not how far a quick head gets from its plaque in those 100 ms.

The other way round was refused: each player tracking their own face and sending the position to the others. A position travels on a data message and the picture on a video track with its own jitter buffer, so the two arrive apart by an amount that changes, and the plaque would slide off a moving head. It would also put face data on the network, and a player on a device that cannot track would have no plaque for anyone.

### A tracker gives two eyes; Dart makes the anchor

Every engine below ends in the same thing: the two eyes of one face in one frame. `FaceAnchor.fromEyes` (`rooster/lib/client/components/face_tracking/face_anchor.dart`) turns them into the anchor: the centre is 0.58 eye distances above the middle of the eyes, at right angles to their line; the width is 2.2 eye distances; the tilt is the tilt of that line. On the reference points of the test videos the forehead sits 0.56 to 0.60 eye distances above the eyes on three different heads. `FaceAnchor.uprightPoint` undoes a frame's rotation (a phone's camera), and `FaceAnchor.inBox` takes the anchor to where the video is drawn: cropped by `BoxFit.cover`, letterboxed, mirrored.

`FaceTracker.start(source)` takes a `FaceVideoSource` (a WebRTC video track and whether the app mirrors it) and gives a `ValueListenable<FaceObservation?>`: for each frame analysed, the frame's size and the anchor, or no anchor when the frame has no face. `FaceTracker.isSupported` says whether the device tracks at all; where it does not the game is not offered. Each platform has one file in `face_tracking/` (`face_tracker_web.dart`, `_linux`, `_windows`, `_macos`, `_android`), all declaring "unavailable" until their task.

### Find the face in the whole frame, then follow it with a square

A detector shrinks its input to a small picture. At 128 or 160 pixels wide, a face a little further from the camera is a dozen pixels across and its eyes land a pixel or two off, which is already more than R4.2 allows; at 320 pixels wide it is accurate, and five to ten times dearer. So every engine works in two steps:

- **Search:** while no face is known, the whole frame, shrunk.
- **Follow:** once a face is known, only a square around it: 5 eye distances wide, centred 0.35 eye distances below the eyes, shrunk to the detector's input. When the square comes back empty the next frame is a search, and the tracker reports "no face" at once.

One engine serves all the trackers of the app, in turn, each at most 15 times a second, keeping only the newest frame of each: eight videos cost eight times one detection, not eight engines.

### The engine on each platform

No engine below uses the network, sends telemetry or needs Google Play services: the model is a file shipped with the app, loaded from the app, and the code that runs it makes no request.

| Platform | Frames are read at | Engine | Model | License | Adds |
|---|---|---|---|---|---|
| Browser | the renderer's own video element, `third_party/flutter-webrtc/lib/src/web/rtc_video_renderer_impl.dart:267` | ONNX Runtime Web 1.31 (wasm, one thread) in a worker | YuNet | MIT, MIT | 3.8 MB gzipped (14.8 MB wasm, 78 KB of JavaScript), downloaded when the first tracker starts; model 230 KB |
| Linux | `FlutterVideoRenderer::OnFrame`, `third_party/flutter-webrtc/common/cpp/src/flutter_video_renderer.cc:47` | tract 0.21.13, in `librust_lib_rooster` | YuNet | Apache-2.0 or MIT, MIT | the model, 230 KB: tract is already linked, for the voice |
| Windows | the same `OnFrame`, shared with Linux | the same | YuNet | the same | the same |
| macOS | `renderFrame:`, `third_party/flutter-webrtc/common/darwin/Classes/FlutterRTCVideoRenderer.m:196` | Vision (`VNDetectFaceLandmarksRequest`), part of macOS | Apple's | part of the system | nothing |
| Android | `SurfaceTextureRenderer.onFrame`, `third_party/flutter-webrtc/android/src/main/java/com/cloudwebrtc/webrtc/SurfaceTextureRenderer.java:100` | LiteRT 1.4.1 (`com.google.ai.edge.litert:litert`) | BlazeFace short range | Apache-2.0, Apache-2.0 | 1.7 MB per ABI in the APK (arm64: a 4.3 MB library); model 230 KB |

The models: YuNet is `face_detection_yunet_2023mar.onnx` from OpenCV Zoo (MIT, Shiqi Yu), 232,589 bytes. Its file fixes the input at 640x640 at every step of the graph, which ONNX Runtime will not override, so the app ships the same weights with those notes removed (`face_detection_yunet_2023mar_dynamic.onnx`, sha256 `dfa4ed65…5022`, 229,873 bytes), for the browser and the desktop alike. BlazeFace short range is MediaPipe's `blaze_face_short_range.tflite` (Apache-2.0), 229,746 bytes.

Android pins LiteRT 1.4.1 on purpose: from 2.0 on, `litert-api` depends on `com.google.android.play:ai-delivery`, a Google Play library. 1.4.1 depends on nothing.

### How a tracker gets the video of a `VoipStream`

Today `VoipStream.buildVideoRenderer` (`rooster/lib/client/components/voip/voip_stream.dart:25`) only gives a widget, and LiveKit makes the renderer inside it. A tracker does not need the renderer: it needs the track, which LiveKit already exposes (`Track.mediaStreamTrack`), and each platform finds the renderer showing that track on its own side.

- `rooster/lib/client/components/voip/voip_stream.dart`: a small interface next to `VoipStream`, `FaceTrackableStream`, with `FaceVideoSource? get faceVideoSource`. A separate interface, because a new member of `VoipStream` would have to be written into the legacy call stream and into nine test fakes.
- `rooster/lib/client/matrix/components/voip_room/matrix_livekit_voip_stream.dart`: `MatrixLivekitVoipStream` implements it. A camera publication with a video track gives `FaceVideoSource(track.mediaStreamTrack, mirrored: …)`; a screen share, an audio stream or an unsubscribed camera gives null. `onStreamChanged` already fires when the track is replaced: whoever holds a tracker starts a new one then.
- `third_party/livekit-client-sdk-flutter/lib/src/widgets/video_track_renderer.dart`: the rule that decides whether a camera is shown mirrored (`_shouldMirror`, line 326) becomes callable from outside the widget, so the stream says "mirrored" exactly when the renderer mirrors.
- Browser, `third_party/flutter-webrtc/lib/src/web/rtc_video_renderer_impl.dart`: a lookup of the video element showing a given track. No element (the video is not on screen) means no observation: nothing is tracked that is not shown.
- Linux and Windows, `third_party/flutter-webrtc/common/cpp`: the plugin gets "tap this track" with the address of a Rust function, the way the DJ's music source gets `rooster_music_pull` (`flutter_webrtc.cc:1360`); the renderer whose track it is (`CheckVideoTrack`, `flutter_video_renderer.cc:103`) hands each frame's I420 planes to that function from `OnFrame`. Rust keeps the newest frame, detects on its own thread and answers Dart through flutter_rust_bridge.
- macOS and Android: the same "tap this track" on the plugin's method channel, answered on an event channel.

### What each platform's task touches

| Task | Files |
|---|---|
| Browser (T0.3) | `face_tracking/face_tracker_web.dart`; `rooster/web/face_tracking/` (the worker; ONNX Runtime's files, fetched by `rooster/scripts/prepare-web.sh` at a pinned version and ignored by git); `rooster/assets/face_tracking/face_detection_yunet_2023mar_dynamic.onnx` and its line in `rooster/pubspec.yaml`; `rooster/assets/licenses/`; `third_party/flutter-webrtc/lib/src/web/rtc_video_renderer_impl.dart`; the three `VoipStream` files above; `third_party/README.md` |
| Linux (T0.4) | `face_tracking/face_tracker_linux.dart` and `demo/demo_video_native.dart`; a new crate `rust/face_tracking` (the model, search and follow, the frame code, the C function the plugin calls) in `Cargo.toml` and `Cargo.lock`; `rust/rust/src/api/` and the generated `rooster/lib/rust/`; `third_party/flutter-webrtc/common/cpp/include/flutter_video_renderer.h`, `common/cpp/src/flutter_video_renderer.cc`, `common/cpp/src/flutter_webrtc.cc` and new headers beside `rooster_music_source.h` for the tap and for a video track fed by a file (`CreateCustomVideoSource`); the same model file and `pubspec.yaml` line as the browser; `rooster/assets/licenses/`; `third_party/README.md` |
| Windows (T3.2) | `face_tracking/face_tracker_windows.dart`; what Windows needs of the shared `common/cpp` and `rust/face_tracking` to build; `third_party/flutter-webrtc/windows/CMakeLists.txt` if a source file was added |
| macOS (T3.3) | `face_tracking/face_tracker_macos.dart`; `third_party/flutter-webrtc/common/darwin/Classes/FlutterRTCVideoRenderer.{h,m}`, a new tap class beside them, `FlutterWebRTCPlugin.m`; `third_party/flutter-webrtc/macos/flutter_webrtc.podspec` (the Vision framework) |
| Android (T3.4) | `face_tracking/face_tracker_android.dart`; `third_party/flutter-webrtc/android/src/main/java/com/cloudwebrtc/webrtc/SurfaceTextureRenderer.java`, a new tap and detector class beside it, `MethodCallHandlerImpl.java`; `third_party/flutter-webrtc/android/build.gradle` (LiteRT 1.4.1); the model in `third_party/flutter-webrtc/android/src/main/assets/`; `rooster/android/app/proguard-rules.pro` if LiteRT needs keep rules |

T0.3 and T0.4 run side by side and write in four of the same places. Each is fixed here, so the second to merge finds nothing to settle:

- **The model**: `rooster/assets/face_tracking/face_detection_yunet_2023mar_dynamic.onnx`, sha256 `dfa4ed65833981965a206ca22688131f467474f6a8d1c094c0fc2783f2c05022`, the same bytes in both.
- **`rooster/pubspec.yaml`**: one line, `    - assets/face_tracking/`, right after `    - assets/cock_a_doodle_who/deck/text/`, the same in both.
- **YuNet's license**: `rooster/assets/licenses/yunet_MIT.txt`, the `LICENSE` file of OpenCV Zoo's `models/face_detection_yunet` byte for byte (sha256 `c83b8120c50ccbd4c4f96edf53141bdd566ebb8f8e9227e415326aa1b1aba958`), the same in both. Only T0.3 adds ONNX Runtime's, as `onnxruntime_MIT.txt`, and only T0.3 puts the two on the licenses screen (`rooster/lib/main.dart`, where `deep_filter_MIT.txt` is loaded): T0.4 does not touch `main.dart`.
- **`third_party/README.md`**: each adds one paragraph at the end of the file, about its own changes only. The browser's paragraph comes first: T0.4 merging second writes its paragraph after T0.3's, and T0.3 merging second writes its paragraph before T0.4's.

## The numbers

Five test videos, 640x480 at 30 frames a second, 1146 frames: `front` (a face looking at the camera, with a light head shake), `glasses` (glasses and a beard on a hand-held phone, eyes 44 to 52 pixels apart), `turn` (a head turning 30 degrees each way), `near_far` (a head from 0.30 m to 1.30 m of the camera, eyes 24 to 132 pixels apart) and `leave` (the face leaves the picture and returns, twice). The reference points never come from a detector being judged: MediaPipe's face mesh model (478 points) run on its own for the filmed videos, the projected 3D model for the rendered ones. The two sources were checked against each other on the rendered videos, over the frames turned 20 degrees or less: the mesh model's forehead is at most 0.054 eye distances from the projected point in `turn` and 0.092 in `near_far`, whose far end has the smallest faces. The tolerance of R4.2 is 0.25.

**R4.2**: the share of analysed frames whose plaque centre is within 0.25 eye distances of the reference forehead, among the frames with a whole face turned 15 degrees or less. Every frame of every video was analysed. The last column is `turn` again, over all its frames, up to 30 degrees.

| Model, and how it looks | Run on | `front` | `glasses` | `turn` | `near_far` | `leave` | `turn`, any angle |
|---|---|---|---|---|---|---|---|
| BlazeFace, whole frame at 128x128 | LiteRT | 100% | 75.4% | 100% | 64.4% | 100% | 95.8% |
| BlazeFace, whole frame | MediaPipe Tasks in Chrome | 100% | 42.1% | 100% | 65.9% | 95.2% | 94.6% |
| YuNet, whole frame at 160x120 | OpenCV | 100% | 76.2% | 100% | 59.5% | 99.0% | 100% |
| YuNet, whole frame at 320x256 | tract, ONNX Runtime Web | 100% | 100% | 100% | 99.0% | 99.0% | 100% |
| BlazeFace, search and follow | LiteRT | 100% | 100% | 100% | 100% | 100% | 66.7% |
| BlazeFace, search and follow | MediaPipe Tasks in Chrome | 100% | 99.6% | 100% | 100% | 100% | 71.2% |
| YuNet, search 320x256, follow 128x128 | ONNX Runtime Web in Chrome | 100% | 99.6% | 100% | 100% | 100% | 99.6% |
| YuNet, search 160x128, follow 128x128 | ONNX Runtime Web in Chrome | 100% | 99.2% | 100% | 100% | 100% | 100% |
| YuNet, search 320x256, follow 128x128 | tract | 100% | 100% | 100% | 100% | 100% | 99.6% |
| YuNet, search 160x128, follow 96x96 | tract | 100% | 99.6% | 100% | 100% | 100% | 97.5% |

Looking at the whole frame at a small size fails the smaller faces whatever the model. Following the face gives 99% or more on every video, with either model. With the head turned 30 degrees YuNet keeps the plaque on the forehead and BlazeFace lets it slide off in a third of the frames. tract gives the same numbers from the model file with the size notes removed.

**Time for one detection**, in milliseconds, median of three runs on this machine (8 cores, GTX 1070; load between 1.9 and 3.9 while they ran). Native engines on one thread, with the input ready; in Chrome, from the video element to the eyes, on the main thread.

| Engine | Search | Follow |
|---|---|---|
| Linux: tract, YuNet | 31.8 at 320x256, 7.7 at 160x128 | 6.3 at 128x128, 3.3 at 96x96 |
| Linux: OpenCV, YuNet | 6.3 at 320x240, 1.7 at 160x120 | 1.4 at 128x128, 0.9 at 96x96 |
| Linux: ONNX Runtime, YuNet (model alone) | 2.7 at 320x256, 0.8 at 160x128 | 0.7 at 128x128, 0.5 at 96x96 |
| Linux: LiteRT, BlazeFace | 1.8 | 2.8 |
| Chrome: ONNX Runtime Web, YuNet | 16.6 at 320x256, 6.7 at 160x128 | 6.0 at 128x128 |
| Chrome: MediaPipe Tasks, BlazeFace, CPU | 10.3 | 8.8 |
| Chrome: MediaPipe Tasks, BlazeFace, GPU | 13.9 | 9.8 |
| Chrome: tract in wasm, YuNet (model alone) | 71.2 at 320x256, 18.4 at 160x128 | 14.5 at 128x128 |
| Chrome: tract in wasm with SIMD (model alone) | 57.0 at 320x256, 14.8 at 160x128 | 11.0 at 128x128 |

R4.3 asks for eight videos at ten anchors a second each: 80 detections a second. Following, that is 0.26 s of one thread per second on Linux (tract, 96x96) and 0.48 s of a worker per second in Chrome (ONNX Runtime Web), off the thread that draws.

## What was refused

- **Tracking on the sender's device**: above.
- **tract in the browser**, which would have been one engine for three platforms: 11 ms a detection with SIMD, 0.9 s of a thread per second for eight videos, and nothing left for a slower machine.
- **MediaPipe Tasks in the browser**: slower end to end (8.8 ms against 6.0 ms), 4.2 MB gzipped, a second model to tune beside the desktop's, and BlazeFace loses the forehead when the head turns. Its GPU path is slower than its CPU path for a model this small.
- **Chrome's `FaceDetector`** (Shape Detection API): not there in Chrome on Linux (`'FaceDetector' in window` is false), nor in Firefox or Safari.
- **ONNX Runtime, LiteRT or OpenCV on the desktop**: four to ten times faster than tract, and a new native library to build, ship and license on two platforms (35 MB, 8 MB and 93 MB on Linux). tract is fast enough, is already in the library and builds the same on Windows.
- **ONNX Runtime on Android**, to keep YuNet everywhere: its library is 36 MB for arm64 (13.7 MB in the APK) against LiteRT's 4.3 MB.
- **ML Kit on Android**: it comes through Google Play services or drags them in, and it reports usage.
- **`android.media.FaceDetector`**: it gives the middle of the eyes and their distance, not each eye, so no tilt.
- **Turning on the Rust build for macOS and Android** to run tract there too: two build systems to change with no machine to try them on. Vision is already on every Mac, and LiteRT is one Gradle line.
- **Detecting on the whole frame at 320 pixels** instead of following: as accurate, 31.8 ms a detection on tract and 16.6 ms in Chrome, where following costs 3.3 ms and 6.0 ms.

## Consequences

- The browser downloads 3.8 MB more, once, when a game first needs a tracker. It is not in `index.html` and comes from the app's own files, never a CDN.
- Three engines and two models are in play, plus Apple's. They agree on the only thing the game reads, two eyes, and `FaceAnchor` is shared, so the plaque sits the same way on a face looking at the camera.
- Android is the weak one: BlazeFace is 100% on faces looking at the camera and 67% on a head turned 30 degrees, measured here on LiteRT for Linux. YuNet on LiteRT would need the model converted, which nobody has tried; until someone does, its task ships BlazeFace and says what it loses.
- The smallest face measured has 24 pixels between the eyes (a person 1.30 m from a 640x480 camera). Further than that is not measured.
- Each engine reads the frame code of the test videos when asked (`readFrameCode`), so every platform is measured the same way, by the frame.
- The browser timings were taken on the main thread; the worker is expected to cost the same per detection, and T0.3 measures it. The Linux tap, the track fed by a file and everything about Windows, macOS and Android are designs, not measurements.
