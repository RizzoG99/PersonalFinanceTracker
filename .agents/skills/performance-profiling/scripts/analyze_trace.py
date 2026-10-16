#!/usr/bin/env python3
"""Read saved xctrace runs and summarize PFT markers and main-thread CPU weights."""

import argparse
from collections import Counter
import json
import math
from pathlib import Path
import re
import subprocess
import sys
import xml.etree.ElementTree as ET


class TraceError(ValueError):
    pass


class XMLRefs:
    def __init__(self, root):
        self.ids = {node.get("id"): node for node in root.iter() if node.get("id")}

    def resolve(self, node):
        if node is None or node.tag == "sentinel":
            return None
        if node.get("ref"):
            try:
                return self.ids[node.get("ref")]
            except KeyError as error:
                raise TraceError(f"Unresolved XML reference: {node.get('ref')}") from error
        return node

    def text(self, node, default=None):
        resolved = self.resolve(node)
        return resolved.text if resolved is not None else default


def parse_toc(xml):
    root = ET.fromstring(xml)
    runs = []
    for run in root.findall("run"):
        target = run.find("info/target")
        summary = run.find("info/summary")
        device = target.find("device")
        process = target.find("process")
        runs.append({
            "run": int(run.get("number")),
            "date": summary.findtext("start-date"),
            "duration_seconds": float(summary.findtext("duration")),
            "platform": device.get("platform"),
            "device": device.get("model"),
            "os": device.get("os-version"),
            "process": process.get("name"),
            "pid": process.get("pid"),
            "tables": sorted({table.get("schema") for table in run.findall("data/table")}),
        })
    if not runs:
        raise TraceError("No runs found in the saved trace")
    return runs


def parse_events(xml):
    root = ET.fromstring(xml)
    refs = XMLRefs(root)
    events = []
    for row in root.iter("row"):
        metadata = refs.resolve(row.find("os-log-metadata"))
        if metadata is None:
            continue
        message = metadata.get("fmt", "")
        if not message.startswith("PFT_PERF "):
            continue
        name = re.search(r"\bname=(\S+)", message)
        kind = re.search(r"\bkind=(\S+)", message)
        timestamp = refs.text(row.find("event-time"))
        if not name or not kind or timestamp is None:
            continue
        event = {"time_seconds": int(timestamp) / 1e9, "name": name[1], "kind": kind[1]}
        for field in ("sequence", "main", "outcome"):
            match = re.search(rf"\b{field}=(\S+)", message)
            if match:
                event[field] = match[1]
        duration = re.search(r"\bduration_ns=([\d.,]+)", message)
        if duration:
            event["duration_ms"] = int(re.sub(r"[.,]", "", duration[1])) / 1e6
        if "metadata=" in message:
            event["metadata"] = message.split("metadata=", 1)[1]
        events.append(event)
    return events


def choose_window(run, events, *, start=None, marker=None, occurrence=None, tail=None,
                  pre=0, duration=1):
    recording_end = run["duration_seconds"]
    if occurrence is not None and (occurrence < 1 or marker is None):
        raise TraceError("--occurrence requires --marker and a positive integer")
    if tail is not None:
        if pre:
            raise TraceError("--pre applies to --start/--marker, not --tail")
        lower, upper = max(0, recording_end - tail), recording_end
    else:
        if marker is not None:
            matches = [event for event in events if event["name"] == marker and event["kind"] == "event"]
            if not matches:
                raise TraceError(f"No PFT event {marker!r} in run {run['run']}")
            if len(matches) > 1 and occurrence is None:
                raise TraceError(f"{marker!r} occurs {len(matches)} times; select --occurrence N")
            index = (occurrence or 1) - 1
            if not 0 <= index < len(matches):
                raise TraceError("Marker occurrence is outside the available events")
            anchor = matches[index]["time_seconds"]
        else:
            anchor = start
        lower, upper = max(0, anchor - pre), min(recording_end, anchor + duration)
    if not 0 <= lower < upper <= recording_end:
        raise TraceError("Requested window is outside the recording or has no duration")
    return lower, upper


def top(counter, limit=12):
    ordered = sorted(counter.items(), key=lambda item: (-item[1], item[0]))
    return [{"frame": name, "sampled_ms": weight / 1e6} for name, weight in ordered[:limit]]


def summarize_cpu(xml, lower, upper, process, pid, bucket=0.5):
    root = ET.fromstring(xml)
    refs = XMLRefs(root)
    leaf, inclusive, app = Counter(), Counter(), Counter()
    total = samples = unknown_stacks = unknown_threads = unknown_weights = 0
    buckets = [0] * math.ceil((upper - lower) / bucket)
    exported_samples = 0
    for row in root.iter("row"):
        timestamp = refs.text(row.find("sample-time"))
        if timestamp is not None:
            exported_samples += 1
        if timestamp is None or not lower <= int(timestamp) / 1e9 < upper:
            continue
        thread = refs.resolve(row.find("thread"))
        if thread is None:
            unknown_threads += 1
            continue
        if "Main Thread" not in thread.get("fmt", ""):
            continue
        owner = refs.resolve(thread.find("process"))
        owner_pid = refs.text(owner.find("pid")) if owner is not None else None
        if owner_pid is not None and owner_pid != str(pid):
            continue
        weight = refs.text(row.find("weight"))
        if weight is None:
            unknown_weights += 1
            continue
        weight = int(weight)
        total += weight
        samples += 1
        index = min(len(buckets) - 1, int((int(timestamp) / 1e9 - lower) / bucket))
        buckets[index] += weight
        backtrace = refs.resolve(row.find("tagged-backtrace"))
        frames = [refs.resolve(node) for node in backtrace.findall("frame")] if backtrace is not None else []
        frames = [node for node in frames if node is not None]
        if not frames:
            unknown_stacks += 1
            continue
        leaf[frames[0].get("name", "<unnamed>")] += weight
        for name in {frame.get("name", "<unnamed>") for frame in frames}:
            inclusive[name] += weight
        for frame in frames:
            binary = refs.resolve(frame.find("binary"))
            if binary is not None and binary.get("name") == process:
                app[frame.get("name", "<unnamed>")] += weight
                break
    return {
        "cpu_evidence_available": exported_samples > 0,
        "exported_sample_count": exported_samples,
        "main_sampled_ms": total / 1e6 if exported_samples else None,
        "main_sample_count": samples,
        "samples_without_stack": unknown_stacks,
        "window_samples_without_thread": unknown_threads,
        "main_samples_without_weight": unknown_weights,
        "leaf_top": top(leaf),
        "inclusive_top": top(inclusive),
        "nearest_app_top": top(app),
        "buckets": [{"start_seconds": lower + i * bucket,
                     "end_seconds": min(upper, lower + (i + 1) * bucket),
                     "main_sampled_ms": weight / 1e6} for i, weight in enumerate(buckets)] if exported_samples else [],
    }


def summarize_events(events, lower, upper):
    selected = [event for event in events if lower <= event["time_seconds"] < upper]
    active = {}
    intervals = []
    for event in events:
        sequence = event.get("sequence")
        if event["kind"] == "begin" and sequence is not None:
            active[sequence] = event
        elif event["kind"] == "end" and sequence in active:
            begin = active.pop(sequence)
            if begin["time_seconds"] < upper and event["time_seconds"] > lower:
                intervals.append({"name": event["name"], "sequence": sequence,
                                  "start_seconds": begin["time_seconds"],
                                  "end_seconds": event["time_seconds"],
                                  "duration_ms": event.get("duration_ms"),
                                  "outcome": event.get("outcome"),
                                  "begin_main": begin.get("main"), "end_main": event.get("main"),
                                  "begin_metadata": begin.get("metadata", ""),
                                  "end_metadata": event.get("metadata", "")})
    unfinished = [event for event in active.values() if event["time_seconds"] < upper]
    return {"pft_events_available": bool(events), "events_in_window": selected,
            "overlapping_intervals": intervals, "unfinished_intervals": unfinished}


def export(trace, *, run=None, schema=None):
    args = ["rtk", "proxy", "xcrun", "xctrace", "export", "--input", str(trace)]
    if run is None:
        args += ["--toc"]
    else:
        args += ["--xpath", f'/trace-toc/run[@number="{run}"]/data/table[@schema="{schema}"]']
    try:
        result = subprocess.run(args, capture_output=True, text=True, timeout=60, check=False)
    except subprocess.TimeoutExpired as error:
        raise TraceError("xctrace export exceeded 60 seconds; no recording was changed") from error
    if result.returncode:
        detail = result.stderr
        if len(detail) > 2200:
            detail = detail[:1600] + "\n[...trimmed...]\n" + detail[-600:]
        raise TraceError(f"xctrace export failed ({result.returncode}): {detail}")
    return result.stdout


def positive(value):
    parsed = float(value)
    if not math.isfinite(parsed) or parsed <= 0:
        raise argparse.ArgumentTypeError("Expected a finite positive number")
    return parsed


def nonnegative(value):
    parsed = float(value)
    if not math.isfinite(parsed) or parsed < 0:
        raise argparse.ArgumentTypeError("Expected a finite nonnegative number")
    return parsed


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    subcommands = parser.add_subparsers(dest="command", required=True)
    inspect = subcommands.add_parser("inspect")
    inspect.add_argument("trace", type=Path)
    analyze = subcommands.add_parser("analyze")
    analyze.add_argument("trace", type=Path)
    analyze.add_argument("--run", type=int, required=True)
    selection = analyze.add_mutually_exclusive_group(required=True)
    selection.add_argument("--start", type=nonnegative)
    selection.add_argument("--marker")
    selection.add_argument("--tail", type=positive)
    analyze.add_argument("--occurrence", type=int)
    analyze.add_argument("--pre", type=nonnegative, default=0)
    analyze.add_argument("--duration", type=positive, default=1)
    analyze.add_argument("--bucket", type=positive, default=0.5)
    args = parser.parse_args()
    try:
        runs = parse_toc(export(args.trace))
        if args.command == "inspect":
            output = {"runs": runs}
        else:
            run = next((run for run in runs if run["run"] == args.run), None)
            if run is None:
                raise TraceError(f"Run {args.run} is absent; saved runs: {[run['run'] for run in runs]}")
            if "time-profile" not in run["tables"]:
                raise TraceError("Selected run has no time-profile table; CPU evidence is unavailable")
            events = parse_events(export(args.trace, run=args.run, schema="os-log")) if "os-log" in run["tables"] else []
            lower, upper = choose_window(run, events, start=args.start, marker=args.marker,
                                         occurrence=args.occurrence, tail=args.tail,
                                         pre=args.pre, duration=args.duration)
            output = {"provenance": run, "window": {"start_seconds": lower, "end_seconds": upper},
                      **summarize_events(events, lower, upper),
                      "cpu": summarize_cpu(export(args.trace, run=args.run, schema="time-profile"),
                                           lower, upper, run["process"], run["pid"], args.bucket)}
        print(json.dumps(output, indent=2))
    except (TraceError, ET.ParseError, OSError, TypeError) as error:
        print(f"trace-analysis: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
