#!/usr/bin/env python3
import argparse
import ast
import json
import re
from pathlib import Path


SECTION_RE = re.compile(
    r"^=== twq (?P<domain>dispatch|swift) (?P<label>.+) stats "
    r"(?P<phase>before|after) ===$"
)
SECTION_END_RE = re.compile(
    r"^=== twq (?P<domain>dispatch|swift) (?P<label>.+) stats "
    r"(?P<phase>before|after) end ===$"
)
SYSCTL_RE = re.compile(r"^(?P<key>kern\.twq\.[^:]+):\s*(?P<value>.+)$")
LIBDISPATCH_COUNTER_RE = re.compile(
    r"^\[libdispatch-twq-counters\]\s+(?P<body>.+)$"
)


def parse_args():
    parser = argparse.ArgumentParser(
        description="Extract a stable M13 benchmark baseline from a guest serial log."
    )
    parser.add_argument("--serial-log", required=True, help="Guest serial log to parse")
    parser.add_argument("--out", required=True, help="JSON output path")
    parser.add_argument("--label", default="m13-initial", help="Baseline label")
    parser.add_argument(
        "--dispatch-filter",
        default="",
        help="Comma-separated dispatch modes included in this run",
    )
    parser.add_argument(
        "--swift-profile",
        default="full",
        help="Swift guest profile used for this run",
    )
    parser.add_argument(
        "--swift-filter",
        default="",
        help="Comma-separated swift modes included in this run",
    )
    return parser.parse_args()


def normalize_mode(domain: str, label: str) -> str:
    normalized = label.strip().replace(" ", "-")
    if domain == "dispatch" and normalized == "burst":
        return "burst-reuse"
    if domain == "swift" and normalized == "dispatch":
        return "dispatch-control"
    return normalized


def parse_scalar(text: str):
    text = text.strip()
    if text.startswith("[") and text.endswith("]"):
        value = ast.literal_eval(text)
        if isinstance(value, list):
            return value
    if "," in text:
        parts = [part.strip() for part in text.split(",")]
        if parts and all(re.fullmatch(r"-?\d+", part) for part in parts):
            return [int(part) for part in parts]
    try:
        return int(text)
    except ValueError:
        return text


def subtract(after, before):
    if isinstance(after, int) and isinstance(before, int):
        return after - before
    if (
        isinstance(after, list)
        and isinstance(before, list)
        and len(after) == len(before)
        and all(isinstance(item, int) for item in after + before)
    ):
        return [a - b for a, b in zip(after, before)]
    return None


def parse_key_value_fields(text: str):
    values = {}
    for field in text.split():
        if "=" not in field:
            continue
        key, value = field.split("=", 1)
        values[key] = parse_scalar(value)
    return values


def sorted_round_events(events, phase):
    filtered = [
        event
        for event in events
        if event.get("phase") == phase and isinstance(event.get("round"), int)
    ]
    return sorted(filtered, key=lambda event: event["round"])


def collect_round_series(events, key):
    if not events:
        return None

    series = []
    for event in events:
        value = event.get(key)
        if not isinstance(value, int):
            return None
        series.append(value)
    return series


def build_round_metrics(events):
    if not events:
        return None

    round_start_events = sorted_round_events(events, "round-start-counters")
    round_ok_events = sorted_round_events(events, "round-ok-counters")
    metrics = {}

    if round_start_events:
        metrics["round_start_rounds"] = [event["round"] for event in round_start_events]
        metrics["round_start_completed_rounds"] = [
            event.get("completed_rounds", -1) for event in round_start_events
        ]
        for key in (
            "reqthreads_count",
            "thread_enter_count",
            "thread_return_count",
            "bucket_total",
            "bucket_idle",
            "bucket_active",
            "sysctl_error",
        ):
            series = collect_round_series(round_start_events, key)
            if series is not None:
                metrics[f"round_start_{key}"] = series

    if round_ok_events:
        metrics["round_ok_rounds"] = [event["round"] for event in round_ok_events]
        metrics["round_ok_completed_rounds"] = [
            event.get("completed_rounds", -1) for event in round_ok_events
        ]
        for key in (
            "reqthreads_count",
            "thread_enter_count",
            "thread_return_count",
            "bucket_total",
            "bucket_idle",
            "bucket_active",
            "reqthreads_delta",
            "thread_enter_delta",
            "thread_return_delta",
            "sysctl_error",
        ):
            series = collect_round_series(round_ok_events, key)
            if series is not None:
                metrics[f"round_ok_{key}"] = series

    return metrics or None


def main():
    args = parse_args()
    serial_log = Path(args.serial_log)
    output = Path(args.out)

    terminal_results = {"dispatch": {}, "swift": {}}
    progress_counts = {"dispatch": {}, "swift": {}}
    progress_events = {"dispatch": {}, "swift": {}}
    counter_sections = {"dispatch": {}, "swift": {}}
    libdispatch_counters = {"dispatch": {}, "swift": {}}
    metadata = {
        "serial_log": str(serial_log.resolve()),
        "label": args.label,
        "dispatch_filter": [item for item in args.dispatch_filter.split(",") if item],
        "swift_profile": args.swift_profile,
        "swift_filter": [item for item in args.swift_filter.split(",") if item],
    }

    current_section = None
    last_probe_key = None

    for raw_line in serial_log.read_text(encoding="utf-8", errors="replace").splitlines():
        line = raw_line.rstrip("\n")

        libdispatch_match = LIBDISPATCH_COUNTER_RE.match(line.strip())
        if libdispatch_match and last_probe_key is not None:
            domain, mode = last_probe_key
            libdispatch_counters[domain].setdefault(mode, []).append(
                parse_key_value_fields(libdispatch_match.group("body"))
            )
            continue

        match = SECTION_RE.match(line)
        if match:
            domain = match.group("domain")
            mode = normalize_mode(domain, match.group("label"))
            phase = match.group("phase")
            current_section = (domain, mode, phase)
            counter_sections.setdefault(domain, {}).setdefault(mode, {})[phase] = {}
            continue

        match = SECTION_END_RE.match(line)
        if match:
            current_section = None
            continue

        if current_section is not None:
            stat_match = SYSCTL_RE.match(line)
            if stat_match:
                domain, mode, phase = current_section
                counter_sections[domain][mode][phase][stat_match.group("key")] = parse_scalar(
                    stat_match.group("value")
                )
            continue

        stripped = line.strip()
        if not stripped.startswith("{"):
            continue

        try:
            payload = json.loads(stripped)
        except json.JSONDecodeError:
            continue

        kind = payload.get("kind")
        if kind not in ("dispatch-probe", "swift-probe"):
            continue

        domain = "dispatch" if kind == "dispatch-probe" else "swift"
        data = payload.get("data", {})
        mode = data.get("mode")
        status = payload.get("status")
        if not mode:
            continue
        if mode == "supported":
            continue

        if status == "progress":
            progress_counts[domain][mode] = progress_counts[domain].get(mode, 0) + 1
            phase = data.get("phase")
            if phase in ("round-start-counters", "round-ok-counters"):
                progress_events[domain].setdefault(mode, []).append(data)
            continue

        terminal_results[domain][mode] = payload
        last_probe_key = (domain, mode)

    benchmarks = {}
    for domain in ("dispatch", "swift"):
        all_modes = set(terminal_results[domain]) | set(counter_sections[domain])
        for mode in sorted(all_modes):
            before = counter_sections[domain].get(mode, {}).get("before", {})
            after = counter_sections[domain].get(mode, {}).get("after", {})
            delta = {}
            for key in sorted(set(before) | set(after)):
                if key in before and key in after:
                    delta_value = subtract(after[key], before[key])
                    if delta_value is not None:
                        delta[key] = delta_value

            result = terminal_results[domain].get(mode)
            benchmarks[f"{domain}.{mode}"] = {
                "domain": domain,
                "mode": mode,
                "status": None if result is None else result.get("status"),
                "probe": None if result is None else result.get("data"),
                "progress_events": progress_counts[domain].get(mode, 0),
                "round_metrics": build_round_metrics(
                    progress_events[domain].get(mode, [])
                ),
                "libdispatch_counters": libdispatch_counters[domain].get(mode, []),
                "twq_before": before,
                "twq_after": after,
                "twq_delta": delta,
            }

    summary = {
        "dispatch_modes": len([key for key in benchmarks if key.startswith("dispatch.")]),
        "swift_modes": len([key for key in benchmarks if key.startswith("swift.")]),
        "non_ok": sorted(
            key for key, value in benchmarks.items() if value["status"] not in (None, "ok")
        ),
    }

    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(
        json.dumps(
            {
                "schema_version": 2,
                "metadata": metadata,
                "summary": summary,
                "benchmarks": benchmarks,
            },
            indent=2,
            sort_keys=True,
        )
        + "\n",
        encoding="utf-8",
    )


if __name__ == "__main__":
    main()
