#!/usr/bin/env python3
"""Summarize the isolated synthetic transform harness attachment (not device traces)."""
import argparse
import hashlib
import json
import statistics
from pathlib import Path


def summarize(records, single_pass=False):
    names = {"up.noQuad", "right.noQuad", "up.full", "right.full", "left.partial",
             "down.diamond", "right.invalid", "up.edge"}
    if len(records) != 56 or {r["case"] for r in records} != names:
        raise ValueError("Expected all 56 records from the eight-case harness")
    result = {}
    for name in sorted(names):
        rows = [r for r in records if r["case"] == name]
        if sorted(r["round"] for r in rows) != list(range(-1, 6)):
            raise ValueError(f"Missing/duplicate round for {name}")
        signatures = {r["pixel_signature"] for r in rows}
        if len(signatures) != 1:
            raise ValueError(f"Instrumentation pixel parity failed for {name}")
        for field in ("source_pixels", "crop_pixels", "ocr_pixels"):
            if len({tuple(r[field]) for r in rows}) != 1:
                raise ValueError(f"Unstable {field} for {name}")
        control = next(r for r in rows if r["round"] == -1)
        if control["samples"]:
            raise ValueError("Disabled control unexpectedly recorded samples")
        expected = {"Receipt.ocr.prepare"}
        if not name.endswith("noQuad"):
            expected.add("Receipt.crop.total")
            # Rotated opaque scale-1 inputs draw directly into the crop canvas.
            # Upright inputs retain the cheap orientation boundary (no rasterization).
            if not single_pass or name.startswith("up."):
                expected.add("Receipt.orientation")
            if name != "right.invalid":
                expected.add("Receipt.crop.render")
        for row in rows:
            if not row["main_actor_harness"] or max(row["ocr_pixels"]) > 2000:
                raise ValueError("Unexpected harness/input")
            if row["round"] < 0:
                continue
            if (len(row["samples"]) != len(expected)
                    or {s["name"] for s in row["samples"]} != expected
                    or not all(s["isMainThread"] for s in row["samples"])):
                raise ValueError(f"Unexpected stage/thread coverage for {name}")
        stages = {}
        for stage in sorted(expected):
            values = [s for r in rows if r["round"] >= 1 for s in r["samples"] if s["name"] == stage]
            first = next(s for r in rows if r["round"] == 0 for s in r["samples"] if s["name"] == stage)
            stages[stage] = {}
            for field, label in [("wallNanoseconds", "wall_ms"), ("threadCPUNanoseconds", "thread_cpu_ms")]:
                ms = [s[field] / 1e6 for s in values]
                stages[stage][label] = {"first": first[field] / 1e6, "warm_median": statistics.median(ms),
                                       "warm_min": min(ms), "warm_max": max(ms), "warm_n": len(ms)}
        result[name] = {"source_pixels": rows[0]["source_pixels"], "crop_pixels": rows[0]["crop_pixels"],
                        "ocr_pixels": rows[0]["ocr_pixels"], "instrumentation_pixel_parity": True, "stages": stages}
    return {"kind": "synthetic_simulator_main_actor_transform_harness", "record_count": len(records),
            "pipeline": "single_pass_camera_crop" if single_pass else "pre_single_pass",
            "physical_latency_proven": False, "device_peak_memory_available": False,
            "all_stage_samples_on_main": True,
            "process_lifetime_maxrss_bytes": max(r["process_lifetime_maxrss_after_bytes"] for r in records),
            "memory_limit": "Cumulative test-host high-water; includes fixtures/runtime; not a stage peak or device footprint",
            "nested_interval_warning": "crop.total includes its orientation/render children; do not sum them",
            "epoch_range": [min(r["epoch"] for r in records), max(r["epoch"] for r in records)], "cases": result}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("records", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--recognizer", type=Path, help="Actual async recognizer smoke-test attachment")
    parser.add_argument("--single-pass", action="store_true", help="Require the optimized camera crop stage coverage")
    args = parser.parse_args()
    raw = args.records.read_bytes()
    result = summarize(json.loads(raw), single_pass=args.single_pass)
    result["source_attachment_sha256"] = hashlib.sha256(raw).hexdigest()
    if args.recognizer:
        raw_recognizer = args.recognizer.read_bytes()
        recognizer = json.loads(raw_recognizer)
        if not recognizer.get("synthetic_only") or {s["name"] for s in recognizer["samples"]} != {"Receipt.ocr.prepare", "Receipt.ocr.enhance"}:
            raise ValueError("Expected the isolated synthetic async recognizer attachment")
        result["actual_async_recognizer_single_synthetic_run"] = recognizer
        result["recognizer_attachment_sha256"] = hashlib.sha256(raw_recognizer).hexdigest()
    args.output.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n")
    print(f"Validated {result['record_count']} records; wrote {args.output}")


if __name__ == "__main__":
    main()
