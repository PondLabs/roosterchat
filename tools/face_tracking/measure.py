"""Measures a face tracker against the reference points of the test videos.

    python -m tools.face_tracking.measure --media DIR LOG.jsonl [--min-r42 90]
    python -m tools.face_tracking.measure --media DIR --replay [--shift 0.5]

The log is what the demonstration (rooster/lib/face_tracking_demo_main.dart)
records, one JSON object per line:

    {"type": "anchor", "video": "front", "tile": 0, "code": 57, "t": 1234.5,
     "face": {"x": 0.51, "y": 0.33, "width": 0.3, "angle": 0.02}}
    {"type": "anchor", "video": "leave", "tile": 4, "code": 80, "t": 1301.0, "face": null}
    {"type": "frame", "t": 1240.1}

An anchor line is one analysed frame of one video: which tile of the
demonstration showed it (the same video can be on screen more than once,
each with its own tracker), the frame code read from that frame, when
(milliseconds, any origin) and where the plaque goes, as fractions of the
upright video's width and height, or null for no face. A frame line is one
frame the interface drew.

For each video it prints the share of analysed frames, among those where the
reference has a whole face looking at the camera, whose plaque centre is
within a quarter of the eye distance of the reference forehead point (R4.2);
the anchors per second of the tile that got the fewest (R4.3 is about each
plaque); and the interface's frames per second meanwhile. For a video where
the face leaves and comes back it also prints how long the plaque took to
go (R4.4: the first analysed frame without a face that says so) and to come
back (the first that has the whole face again and an anchor), the longest
of each, in seconds of video: the frames between, at the video's rate. It
leaves out the detection and the drawing after it, a few milliseconds.

With `--min-r42` it fails when a video is below that percentage, and also
when a video of the media folder has no anchor in the log or no frame with a
face looking at the camera was judged: a run that left a video out has not
passed. With `--max-lost` it fails when the plaque took longer than that to
go or to come back, or never went.

`--replay` writes the log of a tracker that repeats the reference, moved
sideways by `--shift` eye distances: 100% at 0, 0% at 0.5.
"""

from __future__ import annotations

import argparse
import json
import math
import sys
from dataclasses import dataclass, field
from pathlib import Path

TOLERANCE = 0.25  # of the eye distance (R4.2)
FRONTAL_YAW = 15.0  # degrees: beyond it the face is not "looking at the camera"


@dataclass
class VideoResult:
    video: str
    judged: int = 0  # analysed frames with a whole, frontal face in the reference
    within: int = 0
    faces: int = 0  # analysed frames with a whole face in the reference, any yaw
    faces_within: int = 0
    absent: int = 0  # analysed frames with no face in the reference
    absent_right: int = 0
    tiles: int = 0  # how many trackers followed this video
    anchors_per_second: float | None = None  # of the tile with the fewest
    frames_per_second: float | None = None
    # Seconds of video from the face leaving to the plaque going, one per
    # time it left in front of a tracker; None where it never went.
    lost_after: list[float | None] = field(default_factory=list)
    # Seconds from the whole face being back to an anchor, one per return.
    back_after: list[float] = field(default_factory=list)

    @property
    def r42(self) -> float | None:
        return 100 * self.within / self.judged if self.judged else None


def load_references(media: Path) -> dict[str, dict]:
    references = {}
    for path in sorted(media.glob("*.reference.json")):
        reference = json.loads(path.read_text())
        reference["byCode"] = {frame["code"]: frame["face"] for frame in reference["frames"]}
        references[path.name.removesuffix(".reference.json")] = reference
    if not references:
        raise SystemExit(f"no *.reference.json in {media}")
    return references


def _pixels(point: list[float], reference: dict) -> tuple[float, float]:
    return point[0] * reference["width"], point[1] * reference["height"]


def eye_distance(face: dict, reference: dict) -> float:
    return math.dist(_pixels(face["rightEye"], reference), _pixels(face["leftEye"], reference))


def error(anchor: dict, face: dict, reference: dict) -> float:
    """How far the plaque centre is from the reference forehead point, in eye
    distances of the reference."""
    centre = _pixels([anchor["x"], anchor["y"]], reference)
    return math.dist(centre, _pixels(face["forehead"], reference)) / eye_distance(face, reference)


def _rate(times: list[float]) -> float | None:
    if len(times) < 2 or times[-1] <= times[0]:
        return None
    return (len(times) - 1) * 1000 / (times[-1] - times[0])


def _state(reference: dict, code: int) -> str:
    """"none", "part" (some of the face outside the picture) or "whole"."""
    face = reference["byCode"].get(code)
    return "none" if face is None else ("whole" if face["inFrame"] else "part")


def _stretch_start(reference: dict, code: int, inside) -> int:
    """The first frame of the run of frames around `code` that `inside`
    holds for, going back across the end of the video (it loops)."""
    count = len(reference["frames"])
    start = code
    for _ in range(count - 1):
        before = (start - 1) % count
        if not inside(before):
            break
        start = before
    return start


def leaving_and_returning(anchors: list[dict], reference: dict) -> tuple[list[float | None], list[float]]:
    """How long the plaque took to go each time the face left, and to come
    back each time the whole face returned after the tracker had lost it, in
    seconds of video. `anchors` are one tile's, in the order analysed."""
    count, fps = len(reference["frames"]), reference["fps"]
    known = [a for a in anchors if a["code"] in reference["byCode"]]
    lost: list[float | None] = []
    back: list[float] = []
    previous: dict | None = None
    gone = False  # the tracker has said "no face" since the face last went
    waiting_lost: int | None = None  # first frame of the face's absence, until the plaque goes
    waiting_back: int | None = None  # first frame of the face's return, until an anchor
    for anchor in known:
        code, state = anchor["code"], _state(reference, anchor["code"])
        previous_state = None if previous is None else _state(reference, previous["code"])
        if previous is not None and state == "none" and previous_state != "none":
            if waiting_lost is not None:
                lost.append(None)
            waiting_lost = _stretch_start(reference, code, lambda c: _state(reference, c) == "none")
        if previous is not None and state == "whole" and previous_state != "whole" and gone:
            waiting_back = _stretch_start(reference, code, lambda c: _state(reference, c) == "whole")
            if previous["face"] is not None and previous_state == "part":
                back.append(0.0)  # found while coming in: there before the face was whole
                waiting_back = None
        if waiting_lost is not None:
            if anchor["face"] is None:
                lost.append(((code - waiting_lost) % count) / fps)
                waiting_lost = None
            elif state != "none":
                lost.append(None)  # the face came back before the plaque went
                waiting_lost = None
        if anchor["face"] is None:
            gone = True
        if waiting_back is not None:
            if anchor["face"] is not None:
                back.append(((code - waiting_back) % count) / fps)
                waiting_back = None
                gone = False
            elif state != "whole":
                waiting_back = None  # left again before it was found
        elif anchor["face"] is not None and state == "whole":
            gone = False
        previous = anchor
    if waiting_lost is not None:
        lost.append(None)
    return lost, back


def measure(records: list[dict], references: dict[str, dict]) -> list[VideoResult]:
    drawn = sorted(r["t"] for r in records if r["type"] == "frame")
    results = []
    for video, reference in references.items():
        anchors = [r for r in records if r["type"] == "anchor" and r["video"] == video]
        if not anchors:
            continue
        result = VideoResult(video)
        for record in anchors:
            if record["code"] not in reference["byCode"]:
                continue  # a frame without a readable code says nothing
            face, anchor = reference["byCode"][record["code"]], record["face"]
            if face is None:
                result.absent += 1
                result.absent_right += anchor is None
            elif face["inFrame"]:
                good = anchor is not None and error(anchor, face, reference) <= TOLERANCE
                result.faces += 1
                result.faces_within += good
                if abs(face["yaw"]) <= FRONTAL_YAW:
                    result.judged += 1
                    result.within += good
        times = sorted(r["t"] for r in anchors)
        by_tile: dict[int, list[float]] = {}
        for record in anchors:
            by_tile.setdefault(record.get("tile", 0), []).append(record["t"])
        rates = [_rate(sorted(tile)) for tile in by_tile.values()]
        result.tiles = len(by_tile)
        by_tile_anchors: dict[int, list[dict]] = {}
        for record in sorted(anchors, key=lambda r: r["t"]):
            by_tile_anchors.setdefault(record.get("tile", 0), []).append(record)
        for tile_anchors in by_tile_anchors.values():
            lost, back = leaving_and_returning(tile_anchors, reference)
            result.lost_after += lost
            result.back_after += back
        result.anchors_per_second = None if None in rates else min(rates)
        result.frames_per_second = _rate([t for t in drawn if times[0] <= t <= times[-1]])
        results.append(result)
    return results


def replay(references: dict[str, dict], shift: float = 0.0, rate: float = 15.0) -> list[dict]:
    """The log of a tracker that repeats the reference points, `rate` times a
    second, each anchor moved `shift` eye distances along the eye line."""
    records = []
    for video, reference in references.items():
        step = max(1, round(reference["fps"] / rate))
        for frame in reference["frames"][::step]:
            t = frame["code"] * 1000 / reference["fps"]
            face = frame["face"]
            anchor = None
            if face is not None:
                right, left = _pixels(face["rightEye"], reference), _pixels(face["leftEye"], reference)
                centre = _pixels(face["forehead"], reference)
                anchor = {
                    "x": (centre[0] + shift * (left[0] - right[0])) / reference["width"],
                    "y": (centre[1] + shift * (left[1] - right[1])) / reference["height"],
                    "width": 2.2 * math.dist(right, left) / reference["width"],
                    "angle": math.atan2(left[1] - right[1], left[0] - right[0]),
                }
            records.append({"type": "anchor", "video": video, "tile": 0, "code": frame["code"], "t": t, "face": anchor})
    # The interface of this make-believe run draws as often as the videos change.
    longest = max(references.values(), key=lambda r: len(r["frames"]) / r["fps"])
    records += [{"type": "frame", "t": i * 1000 / longest["fps"]} for i in range(len(longest["frames"]))]
    return records


def _number(value: float | None, unit: str = "") -> str:
    return "n/a" if value is None else f"{value:.1f}{unit}"


def report(results: list[VideoResult]) -> str:
    lines = [
        f"{'video':<10} {'R4.2':>7} {'frontal frames':>15} {'any yaw':>8} "
        f"{'no face right':>14} {'tiles':>6} {'anchors/s':>10} {'frames/s':>9}"
    ]
    for r in results:
        any_yaw = 100 * r.faces_within / r.faces if r.faces else None
        absent = f"{r.absent_right}/{r.absent}" if r.absent else "n/a"
        lines.append(
            f"{r.video:<10} {_number(r.r42, '%'):>7} {f'{r.within}/{r.judged}':>15} "
            f"{_number(any_yaw, '%'):>8} {absent:>14} {r.tiles:>6} "
            f"{_number(r.anchors_per_second):>10} {_number(r.frames_per_second):>9}"
        )
    comings = [r for r in results if r.lost_after or r.back_after]
    if comings:
        lines.append("")
        lines.append(f"{'video':<10} {'left':>5} {'no face after':>14} {'back':>5} {'anchors back after':>19}")
        for r in comings:
            never = sum(1 for s in r.lost_after if s is None)
            went = [s for s in r.lost_after if s is not None]
            longest = "never" if never else _number(max(went) if went else None, " s")
            lines.append(
                f"{r.video:<10} {len(r.lost_after):>5} {longest:>14} {len(r.back_after):>5} "
                f"{_number(max(r.back_after) if r.back_after else None, ' s'):>19}"
            )
    return "\n".join(lines)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("log", nargs="?", type=Path, help="the anchor log of a run of the demonstration")
    parser.add_argument("--media", required=True, type=Path, help="the folder of test videos and references")
    parser.add_argument(
        "--min-r42",
        type=float,
        help="fail when a video's R4.2 is below this percentage, or a video of the media folder was not measured",
    )
    parser.add_argument(
        "--max-lost",
        type=float,
        help="fail when the plaque took longer than this many seconds to go when the face left, or to come back",
    )
    parser.add_argument("--replay", action="store_true", help="write the log of a tracker that repeats the reference")
    parser.add_argument("--shift", type=float, default=0.0, help="with --replay: eye distances to move every anchor")
    args = parser.parse_args(argv)

    references = load_references(args.media)
    if args.replay:
        for record in replay(references, args.shift):
            print(json.dumps(record))
        return 0
    if args.log is None:
        parser.error("a log, or --replay")
    records = [json.loads(line) for line in args.log.read_text().splitlines() if line.strip()]
    results = measure(records, references)
    print(report(results))
    if not results:
        print("no anchor of a known video in the log", file=sys.stderr)
        return 1
    if args.min_r42 is not None:
        measured = {r.video for r in results}
        problems = {
            "no anchor in the log": [video for video in references if video not in measured],
            "no frame with a face looking at the camera was judged": [r.video for r in results if not r.judged],
            f"R4.2 below {args.min_r42}%": [r.video for r in results if r.r42 is not None and r.r42 < args.min_r42],
        }
        for problem, videos in problems.items():
            if videos:
                print(f"{problem}: {', '.join(videos)}", file=sys.stderr)
        if any(problems.values()):
            return 1
    if args.max_lost is not None:
        late = {
            f"no face after more than {args.max_lost} s": [
                r.video for r in results if any(s is None or s > args.max_lost for s in r.lost_after)
            ],
            f"anchors back after more than {args.max_lost} s": [
                r.video for r in results if any(s > args.max_lost for s in r.back_after)
            ],
        }
        for problem, videos in late.items():
            if videos:
                print(f"{problem}: {', '.join(videos)}", file=sys.stderr)
        if any(late.values()):
            return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
