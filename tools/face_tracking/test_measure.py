from __future__ import annotations

import contextlib
import io
import json
import unittest
from pathlib import Path
from tempfile import TemporaryDirectory

from tools.face_tracking import measure


def _face(x: float = 0.5, yaw: float = 0.0, in_frame: bool = True) -> dict:
    """A face with eyes 64 pixels apart in a 640x480 video."""
    return {
        "rightEye": [x - 0.05, 0.5],
        "leftEye": [x + 0.05, 0.5],
        "forehead": [x, 0.4],
        "yaw": yaw,
        "inFrame": in_frame,
    }


def _references(faces: list[dict | None]) -> dict[str, dict]:
    reference = {
        "video": "clip.mp4",
        "width": 640,
        "height": 480,
        "fps": 30,
        "frames": [{"code": code, "face": face} for code, face in enumerate(faces)],
    }
    reference["byCode"] = {frame["code"]: frame["face"] for frame in reference["frames"]}
    return {"clip": reference}


def _anchor(code: int, x: float | None, t: float = 0.0, y: float = 0.4, tile: int = 0) -> dict:
    face = None if x is None else {"x": x, "y": y, "width": 0.22, "angle": 0.0}
    return {"type": "anchor", "video": "clip", "tile": tile, "code": code, "t": t, "face": face}


class MeasureTests(unittest.TestCase):
    def test_a_tracker_that_repeats_the_reference_scores_100(self) -> None:
        references = _references([_face(0.3 + i / 100) for i in range(60)])
        (result,) = measure.measure(measure.replay(references), references)
        self.assertEqual(result.r42, 100.0)
        self.assertEqual(result.judged, 30)

    def test_half_an_eye_distance_off_scores_0(self) -> None:
        references = _references([_face(0.3 + i / 100) for i in range(60)])
        (result,) = measure.measure(measure.replay(references, shift=0.5), references)
        self.assertEqual(result.r42, 0.0)
        self.assertEqual(result.judged, 30)

    def test_the_line_is_a_quarter_of_the_eye_distance(self) -> None:
        references = _references([_face()])
        # 64 pixels between the eyes: 16 pixels of tolerance, 0.025 of the width.
        (inside,) = measure.measure([_anchor(0, 0.5 + 0.0249)], references)
        (outside,) = measure.measure([_anchor(0, 0.5 + 0.0251)], references)
        (below,) = measure.measure([_anchor(0, 0.5, y=0.4 + 17 / 480)], references)
        self.assertEqual((inside.r42, outside.r42, below.r42), (100.0, 0.0, 0.0))

    def test_no_anchor_on_a_face_is_a_miss(self) -> None:
        references = _references([_face(), _face()])
        (result,) = measure.measure([_anchor(0, 0.5), _anchor(1, None)], references)
        self.assertEqual(result.r42, 50.0)

    def test_only_whole_faces_looking_at_the_camera_are_judged(self) -> None:
        references = _references([_face(), _face(yaw=30), _face(in_frame=False), None, None])
        records = [_anchor(0, 0.5), _anchor(1, 0.9), _anchor(2, 0.9), _anchor(3, None), _anchor(4, 0.5)]
        (result,) = measure.measure(records, references)
        self.assertEqual((result.judged, result.within), (1, 1))
        self.assertEqual((result.faces, result.faces_within), (2, 1))
        self.assertEqual((result.absent, result.absent_right), (2, 1))

    def test_a_frame_code_the_video_does_not_have_is_left_out(self) -> None:
        references = _references([_face()])
        (result,) = measure.measure([_anchor(0, 0.5), _anchor(7, 0.9)], references)
        self.assertEqual(result.judged, 1)

    def test_rates_come_from_the_times_in_the_log(self) -> None:
        references = _references([_face()])
        records = [_anchor(0, 0.5, t=1000 + i * 100) for i in range(21)]
        records += [{"type": "frame", "t": 1000 + i * 25} for i in range(81)]
        records += [{"type": "frame", "t": 5000 + i} for i in range(50)]  # after the video's run
        (result,) = measure.measure(records, references)
        self.assertAlmostEqual(result.anchors_per_second, 10.0)
        self.assertAlmostEqual(result.frames_per_second, 40.0)

    def test_a_video_on_two_tiles_gets_the_rate_of_the_slower_tile(self) -> None:
        references = _references([_face()])
        # Tile 0 at 15 anchors a second, tile 3 at 10: 25 a second between them.
        records = [_anchor(0, 0.5, t=i * 1000 / 15, tile=0) for i in range(31)]
        records += [_anchor(0, 0.5, t=i * 100, tile=3) for i in range(21)]
        (result,) = measure.measure(records, references)
        self.assertEqual(result.tiles, 2)
        self.assertAlmostEqual(result.anchors_per_second, 10.0)
        self.assertEqual(result.judged, 52, "every tile's frames are judged")

    def test_a_log_without_tiles_is_one_tile(self) -> None:
        references = _references([_face()])
        records = [{k: v for k, v in _anchor(0, 0.5, t=i * 100).items() if k != "tile"} for i in range(11)]
        (result,) = measure.measure(records, references)
        self.assertEqual(result.tiles, 1)
        self.assertAlmostEqual(result.anchors_per_second, 10.0)

    def test_how_long_the_plaque_takes_to_leave_and_come_back(self) -> None:
        # A face for 10 frames, none for 10, a face again for 10, at 30 a second.
        references = _references([_face()] * 10 + [None] * 10 + [_face()] * 10)
        # Every other frame analysed: the face is still seen on frame 12, gone on
        # 14, missed on 20 and back on 22.
        faces = {code: 0.5 for code in range(0, 13, 2)} | {code: 0.5 for code in range(22, 30, 2)}
        records = [_anchor(code, faces.get(code), t=code * 1000 / 30) for code in range(0, 30, 2)]
        (result,) = measure.measure(records, references)
        self.assertEqual(len(result.lost_after), 1)
        self.assertAlmostEqual(result.lost_after[0], 4 / 30)
        self.assertEqual(len(result.back_after), 1)
        self.assertAlmostEqual(result.back_after[0], 2 / 30)

    def test_a_plaque_that_never_leaves_is_counted(self) -> None:
        references = _references([_face()] * 4 + [None] * 4 + [_face()] * 4)
        records = [_anchor(code, 0.5, t=code * 100) for code in range(12)]
        (result,) = measure.measure(records, references)
        self.assertEqual(result.lost_after, [None])
        self.assertEqual(result.back_after, [], "it was never gone")

    def test_a_face_found_while_coming_in_is_back_at_once(self) -> None:
        # The face comes back halfway (not inFrame) before it is whole again.
        references = _references([_face()] * 4 + [None] * 4 + [_face(in_frame=False)] * 2 + [_face()] * 4)
        faces = {0: 0.5, 2: 0.5, 9: 0.6, 10: 0.5, 12: 0.5}
        records = [_anchor(code, faces.get(code), t=code * 100) for code in [0, 2, 4, 6, 9, 10, 12]]
        (result,) = measure.measure(records, references)
        self.assertEqual(result.back_after, [0.0])

    def test_a_stretch_across_the_end_of_the_video_is_one_stretch(self) -> None:
        # The video loops: frames 8, 9, 0 and 1 have no face.
        references = _references([None] * 2 + [_face()] * 6 + [None] * 2)
        t = iter(range(0, 10000, 100))
        codes = [2, 4, 6, 8, 9, 0, 1, 2, 4]
        faces = {2: 0.5, 4: 0.5, 6: 0.5, 8: 0.5, 9: 0.5}
        records = [_anchor(code, faces.get(code) if i < 7 else 0.5, t=next(t)) for i, code in enumerate(codes)]
        (result,) = measure.measure(records, references)
        self.assertEqual(len(result.lost_after), 1)
        self.assertAlmostEqual(result.lost_after[0], 2 / 30, msg="from frame 8 to frame 0")
        self.assertEqual(result.back_after, [0.0])

    def test_the_longest_wait_fails_the_command(self) -> None:
        faces = {"clip": [_face()] * 30 + [None] * 30 + [_face()] * 30}
        quick = [_anchor(c, None if 30 <= c < 60 else 0.5, t=c * 33) for c in range(0, 90, 2)]
        slow = [_anchor(c, None if 50 <= c < 78 else 0.5, t=c * 33) for c in range(0, 90, 2)]
        self.assertEqual(self._run(faces, quick, "--max-lost", "0.5")[0], 0)
        code, errors = self._run(faces, slow, "--max-lost", "0.5")
        self.assertEqual(code, 1)
        self.assertIn("no face after more than 0.5 s: clip", errors)
        self.assertIn("anchors back after more than 0.5 s: clip", errors)

    def _run(self, faces: dict[str, list[dict | None]], records: list[dict], *arguments: str) -> tuple[int, str]:
        """Runs the command over a media folder with these videos and this log."""
        with TemporaryDirectory() as folder:
            for video, frames in faces.items():
                reference = _references(frames)["clip"]
                del reference["byCode"]
                (Path(folder) / f"{video}.reference.json").write_text(json.dumps(reference))
            log = Path(folder) / "log.jsonl"
            log.write_text("".join(json.dumps(record) + "\n" for record in records))
            out, err = io.StringIO(), io.StringIO()
            with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
                code = measure.main(["--media", folder, str(log), *arguments])
            return code, err.getvalue()

    def test_the_minimum_fails_a_log_that_leaves_a_video_out(self) -> None:
        faces = {"clip": [_face()], "other": [_face()]}
        records = [_anchor(0, 0.5)]
        self.assertEqual(self._run(faces, records)[0], 0, "without a minimum it only reports")
        code, errors = self._run(faces, records, "--min-r42", "90")
        self.assertEqual(code, 1)
        self.assertIn("no anchor in the log: other", errors)

    def test_the_minimum_fails_a_video_with_no_frontal_frame_judged(self) -> None:
        faces = {"clip": [_face(), None, _face(yaw=40)]}
        records = [_anchor(1, None), _anchor(2, 0.5)]  # only the frames no face looks at the camera in
        code, errors = self._run(faces, records, "--min-r42", "90")
        self.assertEqual(code, 1)
        self.assertIn("no frame with a face looking at the camera was judged: clip", errors)

    def test_the_command_prints_a_row_per_video_and_fails_below_the_minimum(self) -> None:
        with TemporaryDirectory() as folder:
            media = Path(folder)
            references = _references([_face(0.3 + i / 100) for i in range(30)])
            del references["clip"]["byCode"]
            (media / "clip.reference.json").write_text(json.dumps(references["clip"]))
            log = media / "log.jsonl"

            def run(*arguments: str) -> tuple[int, str]:
                out = io.StringIO()
                with contextlib.redirect_stdout(out), contextlib.redirect_stderr(io.StringIO()):
                    code = measure.main(["--media", folder, *arguments])
                return code, out.getvalue()

            code, replayed = run("--replay")
            log.write_text(replayed)
            code, report = run(str(log), "--min-r42", "90")
            self.assertEqual(code, 0)
            self.assertRegex(report, r"clip\s+100\.0%\s+15/15")
            self.assertRegex(report, r"\s1\s+15\.0\s+30\.0\s*$")

            code, shifted = run("--replay", "--shift", "0.5")
            log.write_text(shifted)
            code, report = run(str(log), "--min-r42", "90")
            self.assertEqual(code, 1)
            self.assertRegex(report, r"clip\s+0\.0%\s+0/15")


if __name__ == "__main__":
    unittest.main()
