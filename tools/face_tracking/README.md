# Measuring face tracking

Cock-a-Doodle-Who? pins a plaque to each player's forehead. How the face is
followed, on which engine and why: [ADR 0006](../../docs/adr/0006-face-tracking.md).
This folder is how a tracker is judged: test videos with a reference, a
frame code that ties an anchor to the frame it came from, and a script that
turns a run of the demonstration into numbers.

## The test videos

They are not in the repository (two are cuts of other people's videos). A
folder of them has, for each video:

- `<name>.mp4`: 640x480, 30 frames a second, with the frame code burned in.
- `<name>.reference.json`: for every frame, by frame code, where the face is:

  ```json
  {"video": "front.mp4", "width": 640, "height": 480, "fps": 30, "frames": [
    {"code": 0, "face": {"rightEye": [0.44, 0.42], "leftEye": [0.57, 0.41],
                         "forehead": [0.50, 0.33], "yaw": 2.9, "inFrame": true}},
    {"code": 1, "face": null}]}
  ```

  Points are fractions of the width and the height, from the top left.
  `rightEye` is the person's right eye, on the left of the picture.
  `forehead` is the middle of the forehead, where the plaque's centre
  belongs. `yaw` is how far the head is turned, in degrees. `inFrame` is
  false while part of the face is outside the picture; `face` is null when
  none of it is in.

The reference never comes from a detector being judged. Filmed videos are
annotated by MediaPipe's face mesh model (478 points) run on its own, with
OpenCV's Haar cascade finding the first crop; rendered ones have the points
projected from the 3D model.

| Video | What happens |
|---|---|
| `front` | a face looking at the camera, with a light head shake |
| `glasses` | glasses and a beard, on a hand-held phone, further away |
| `turn` | a head turning 30 degrees to each side |
| `near_far` | a head from 0.30 m to 1.30 m of the camera |
| `leave` | the face leaves the picture and comes back, twice |

## The frame code

`frame_code.py`: a strip across the bottom sixteenth of the frame, in 20
cells: white, black, the 16 bits of the frame number (most significant
first, white is 1), an even parity bit, black. A tracker started with
`readFrameCode` reads it from the frame it analysed, so its anchor is
compared with the reference of that very frame, whatever the delay.

## Measuring

Build the demonstration, run it in Chrome, measure the log:

```sh
cd rooster && flutter build web --release -t lib/face_tracking_demo_main.dart --dart-define PLATFORM=web
cd .. && NODE_PATH=<folder with playwright-core> node tools/face_tracking/capture_web.mjs \
  --build rooster/build/web --media <test videos> --out <folder> --query "tracker=device&tiles=8"
python3 -m tools.face_tracking.measure --media <test videos> <folder>/anchors.jsonl --min-r42 90
```

`measure.py` prints, for each video: R4.2, the share of analysed frames
whose plaque centre is within a quarter of the eye distance of the
reference forehead, among the frames where the reference has a whole face
turned 15 degrees or less; the same over any yaw; how often "no face" was
right; how many tiles showed the video, and the anchors per second of the
tile that got the fewest (with `tiles=8` a video is on screen twice, each
with its own tracker); and the interface's frames per second. For a video
the face leaves (`leave`), it also prints the longest the plaque took to go
once the face was gone, and to come back once the whole face was in again,
in seconds of video. Its docstring has the log's format.

`--min-r42 90` fails when a video is under 90%, and also when a video of the
folder has no anchor in the log or none of its frames with a face looking at
the camera was analysed: every video has to be on screen. `--max-lost 0.5`
fails when the plaque took longer than half a second to go or to come back
(R4.4), or never went.

`?tracker=replay` (the default) is a tracker that repeats the reference: it
measures 100%, and 0% with `&shift=0.5`. That is the check of the tool
itself, also as `python3 -m tools.face_tracking.measure --media <test videos> --replay [--shift 0.5]`.

### On Linux

The app has no page to load the videos into: the demonstration asks the
WebRTC plugin for a local video track that plays a `.y4m` file (raw 4:2:0
frames) next to each `.mp4`, and that track goes through the same renderer
and frame tap as a camera or a call's video. Make the `.y4m` files once,
into a folder with the references:

```sh
for v in front glasses turn near_far leave; do
  ffmpeg -i <test videos>/$v.mp4 -pix_fmt yuv420p -f yuv4mpegpipe <folder>/$v.y4m
  cp <test videos>/$v.reference.json <folder>/
done
```

Build the demonstration, run it off screen with
`rooster/scripts/headless-linux.sh` (no camera, no window on your screen),
measure the log it writes:

```sh
cd rooster && flutter build linux --release -t lib/face_tracking_demo_main.dart --dart-define PLATFORM=linux
FACE_TRACKING_DEMO="media=<folder>/&tracker=device&tiles=8&log=<out>/anchors.jsonl&seconds=40" \
  scripts/headless-linux.sh run --offline build/linux/x64/release/bundle
cd .. && python3 -m tools.face_tracking.measure --media <folder> <out>/anchors.jsonl --min-r42 90 --max-lost 0.5
```

`FACE_TRACKING_DEMO` takes the page's query (`media`, `videos`, `tiles`,
`tracker`, `shift`), plus `log=` (the record, written every second) and
`seconds=` (when to write it a last time and quit). Every second the app
prints, for each tile, how many frames its renderer handed to the tracker
and how many the tracker analysed.

The engine alone, outside the app, on every frame (accuracy, and the time
of one step): `cargo run --release -p face_tracking --example measure --
<folder> <out>/rust.jsonl`.

Tests: `python3 -m unittest tools.face_tracking.test_measure tools.face_tracking.test_frame_code`.
