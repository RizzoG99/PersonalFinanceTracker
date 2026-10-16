#!/usr/bin/env python3
"""Summarize the opt-in ViewModel harness; no device/frame latency claims."""
import argparse
import json
import statistics
from pathlib import Path


def distribution(values):
    return {"median": statistics.median(values), "min": min(values), "max": max(values)}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("log", type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--compare", type=Path, help="Require result/count parity with a previous JSON run")
    args = parser.parse_args()
    records = []
    for line in args.log.read_text().splitlines():
        if "PFT_ANALYTICS_BASELINE " in line:
            records.append(json.loads(line.split("PFT_ANALYTICS_BASELINE ", 1)[1]))
    actions = sorted({r["action"] for r in records})
    if len(records) != 70 or len(actions) != 10:
        raise SystemExit(f"Incomplete run: expected 70 records / 10 actions, got {len(records)} / {len(actions)}")
    summary = {}
    for action in actions:
        selected = [r for r in records if r["action"] == action]
        if sorted(r["round"] for r in selected) != list(range(-1, 6)):
            raise SystemExit(f"Missing or duplicate rounds for {action}")
        warm = [r for r in selected if r["round"] >= 1]
        service_names = sorted({s["name"] for r in warm for s in r["samples"]})
        summary[action] = {
            "wall_ms": distribution([r["wall_ms"] for r in warm]),
            # Synchronous scopes are disjoint; this is measured service CPU, not
            # all process CPU or an async interval's supposed CPU duration.
            "measured_main_cpu_ms": distribution([
                sum(s["threadCPUNanoseconds"] for s in r["samples"] if s["isMainThread"]) / 1e6 for r in warm
            ]),
            "fetch_counts": sorted({r["fetch_count"] for r in warm}),
            "services": {
                name: {
                    "wall_ms": distribution([s["wallNanoseconds"] / 1e6 for r in warm for s in r["samples"] if s["name"] == name]),
                    "thread_cpu_ms": distribution([s["threadCPUNanoseconds"] / 1e6 for r in warm for s in r["samples"] if s["name"] == name]),
                    "main_thread": sorted({s["isMainThread"] for r in warm for s in r["samples"] if s["name"] == name}),
                } for name in service_names
            },
        }
    output = {"kind": "simulator_viewmodel_service_baseline", "warm_rounds": [1, 2, 3, 4, 5],
              "summary": summary, "records": records}
    if args.compare:
        prior = json.loads(args.compare.read_text())
        prior_records = {(r["action"], r["round"]): r for r in prior["records"]}
        if len(prior_records) != len(records):
            raise SystemExit("Comparison run has a different sample count")
        for record in records:
            key = (record["action"], record["round"])
            previous = prior_records[key]
            for field in ["result", "input_count", "fetch_count", "timezone", "locale"]:
                if record[field] != previous[field]:
                    raise SystemExit(f"Comparison parity failed: {key}, {field}")
            if sorted((s["name"], s["isMainThread"]) for s in record["samples"]) != sorted(
                (s["name"], s["isMainThread"]) for s in previous["samples"]
            ):
                raise SystemExit(f"Comparison service/thread coverage differs: {key}")
        output["comparison"] = {"reference": args.compare.name, "matched_records": len(records),
                                "result_and_count_parity": True}
    args.output.write_text(json.dumps(output, indent=2, sort_keys=True) + "\n")
    for action, row in summary.items():
        print(f'{action}: wall {row["wall_ms"]} ms; measured main CPU {row["measured_main_cpu_ms"]} ms')


if __name__ == "__main__":
    main()
