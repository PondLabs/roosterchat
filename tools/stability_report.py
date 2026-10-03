"""Collect real test results and workload measurements without inferring a pass."""

import argparse
from collections import Counter
import json
from pathlib import Path


def collect(paths):
    outcomes = Counter()
    measurements = []
    missing = []
    completed = []
    for path in paths:
        if not path.is_file():
            missing.append(str(path))
            continue
        for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
            message = line
            try:
                event = json.loads(line)
            except (ValueError, TypeError):
                event = None
            if isinstance(event, dict):
                if event.get("type") == "testDone" and not event.get("hidden"):
                    outcomes["skipped" if event.get("skipped") else event["result"]] += 1
                elif event.get("type") == "done":
                    completed.append({"file": str(path), "success": event.get("success")})
                message = event.get("message", line)
            if "STABILITY_METRIC " in message:
                payload = message.split("STABILITY_METRIC ", 1)[1]
                try:
                    measurements.append(json.loads(payload))
                except ValueError:
                    outcomes["invalid_measurement"] += 1
    return {
        "schema_version": 1,
        "test_outcomes": dict(outcomes),
        "completed_test_runs": completed,
        "measurements": measurements,
        "missing_inputs": missing,
        "limits": "RSS and JS heap samples are diagnostics; they do not prove absence of leaks. "
        "Widget host elapsed time is not a rendering or startup benchmark.",
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--platform", required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("logs", nargs="+", type=Path)
    args = parser.parse_args()
    report = collect(args.logs)
    report["platform"] = args.platform
    args.output.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
