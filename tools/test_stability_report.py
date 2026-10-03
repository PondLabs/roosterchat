import json
from pathlib import Path
import tempfile
import unittest

from tools.stability_report import collect


class StabilityReportTest(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.log = Path(self.directory.name) / "tests.jsonl"

    def write(self, events):
        self.log.write_text("\n".join(json.dumps(event) for event in events))

    def test_failed_and_skipped_tests_are_not_counted_as_passes(self):
        self.write([
            {"type": "testDone", "result": "success", "hidden": False},
            {"type": "testDone", "result": "error", "hidden": False},
            {"type": "testDone", "result": "success", "skipped": True},
            {"type": "testDone", "result": "success", "hidden": True},
            {"type": "done", "success": False},
        ])
        report = collect([self.log])
        self.assertEqual(report["test_outcomes"], {"success": 1, "error": 1, "skipped": 1})
        self.assertFalse(report["completed_test_runs"][0]["success"])

    def test_reads_json_runner_and_plain_profile_measurements(self):
        self.write([{"type": "print", "message": 'STABILITY_METRIC {"host_elapsed_ms": 42}'}])
        with self.log.open("a") as stream:
            stream.write('\nSTABILITY_METRIC {"timeline_daily_use": {"average_frame_build_time_millis": 3}}\n')
        report = collect([self.log])
        self.assertEqual(len(report["measurements"]), 2)
        self.assertEqual(report["measurements"][0]["host_elapsed_ms"], 42)

    def test_incomplete_run_and_missing_file_do_not_imply_success(self):
        self.write([{"type": "start"}])
        report = collect([self.log, self.log.with_name("absent.log")])
        self.assertEqual(report["completed_test_runs"], [])
        self.assertEqual(len(report["missing_inputs"]), 1)

    def test_invalid_measurement_is_reported(self):
        self.log.write_text("STABILITY_METRIC invalid\n")
        self.assertEqual(collect([self.log])["test_outcomes"], {"invalid_measurement": 1})


if __name__ == "__main__":
    unittest.main()
