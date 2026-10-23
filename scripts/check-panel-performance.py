#!/usr/bin/env python3
"""Profile real panel scrolling in an isolated Debug app, using synthetic data."""

import argparse
import csv
import io
import json
import pathlib
import subprocess
import tempfile
import time


NOTIFIER = """
import Foundation
let args = CommandLine.arguments
DistributedNotificationCenter.default().postNotificationName(
    Notification.Name("io.github.whitenwhiten.topophany-bar.debug"),
    object: "@" + args[1] + " " + args.dropFirst(2).joined(separator: " "),
    userInfo: nil, deliverImmediately: true)
"""
DEBUG_OUT = pathlib.Path("/tmp/topophany-bar-debug")


def wait_for_write(path, previous, process, timeout=10):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if process.poll() is not None:
            raise RuntimeError(f"test app exited with {process.returncode}")
        if path.exists() and path.stat().st_mtime_ns != previous:
            return path.read_text()
        time.sleep(0.04)
    raise RuntimeError(f"no new {path.name}; use a Debug build and keep a display awake")


def capture(app, notifier, temporary, output, theme, language, iterations, topo, input_mode):
    settings = temporary / f"{theme}.json"
    settings.write_text(json.dumps({
        "schema": 1, "openAtLogin": False, "language": language,
        "appearance": {"theme": theme, "panel": "dark", "panelHeight": 720},
        "sections": [
            {"id": "status", "pinned": True}, {"id": "attention", "limit": 5},
            {"id": "seen"}, {"id": "map", "locked": True}, {"id": "applications"},
            {"id": "services", "enabled": True, "ids": ["vless-entry", "main-site"]},
            {"id": "fleet"},
            {"id": "servers", "enabled": True, "nodes": ["oracle-ny", "bwh-la"]},
            {"id": "zones"}, {"id": "mac", "mode": "local", "every": "2s"},
        ],
    }))
    command = [str(app), "-settings", str(settings), "-direct-root", str(temporary / "direct")]
    command += ["-topo", str(topo), "-preview", "1"] if topo else ["-fixture", "incidents"]
    target = output / f"{theme}-{language}-{input_mode}"
    target.mkdir(parents=True, exist_ok=True)
    with (target / "app.log").open("w") as log:
        process = subprocess.Popen(command, stdout=log, stderr=subprocess.STDOUT)
        def send(*words):
            subprocess.run([str(notifier), str(process.pid), *words], check=True)

        def trace(delta=500):
            path = DEBUG_OUT / "leaptrace.csv"
            previous = path.stat().st_mtime_ns if path.exists() else 0
            if input_mode == "leap":
                send("leaptrace")
            elif input_mode == "wheel":
                send("wheeltrace", str(delta))
            else:
                send("maptrace", "in" if delta > 0 else "out")
            return wait_for_write(path, previous, process)

        try:
            # The driver registers after launch and the first rendering pass
            # creates the native scroll view. Neither belongs in steady motion.
            time.sleep(2)
            send("perf", "start")
            send("panel")
            time.sleep(1)
            trace()
            send("perf", "start")
            traces = []
            direction = 1
            last = None
            for index in range(iterations):
                if input_mode == "map":
                    direction = 1 if index % 6 < 3 else -1
                elif last is not None:
                    if last["offset"] >= last["content"] - last["visible"] - 1:
                        direction = -1
                    elif last["offset"] <= 1:
                        direction = 1
                data = trace(direction * 500)
                (target / f"{input_mode}-{index:02}.csv").write_text(data)
                rows = [{k: float(v) for k, v in row.items()} for row in csv.DictReader(io.StringIO(data))]
                if any(r.get("hostingWidth", 0) <= 0 or r.get("hostingHeight", 0) <= 0
                       or abs(r["hostingWidth"] - r["windowWidth"]) > 1
                       or abs(r["hostingHeight"] - r["windowHeight"]) > 1 for r in rows):
                    raise RuntimeError(f"{theme}: invalid hosting bounds; rebuild the Debug app before profiling")
                start, end = rows[0]["offset"], rows[-1]["offset"]
                last = rows[-1]
                if input_mode != "map" and abs(end - start) < 1:
                    raise RuntimeError(f"{theme}: scroll did not move; panel must overflow")
                gaps = [b["milliseconds"] - a["milliseconds"] for a, b in zip(rows, rows[1:])]
                changes = [b for a, b in zip(rows, rows[1:]) if a["offset"] != b["offset"]]
                traces.append({"from": start, "to": end, "updates": len(changes), "maximumGapMilliseconds": max(gaps)})
                print(f"{theme} {index + 1}/{iterations}: {start:.0f} -> {end:.0f}, max main gap {max(gaps):.1f} ms", flush=True)
            path = DEBUG_OUT / "performance.json"
            previous = path.stat().st_mtime_ns if path.exists() else 0
            send("perf", "stop")
            counters = json.loads(wait_for_write(path, previous, process))
            result = {"theme": theme, "language": language, "input": input_mode, "traces": traces, "counters": counters}
            (target / "summary.json").write_text(json.dumps(result, indent=2) + "\n")
            return result
        finally:
            if process.poll() is None:
                send("perf", "stop")
                process.terminate()
                try:
                    process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("app", type=pathlib.Path, help="path to a built Debug .app")
    parser.add_argument("--theme", action="append", help="repeat for several themes; default: native, terminal")
    parser.add_argument("--language", default="zh-Hans", choices=["en", "ja", "zh-Hans"])
    parser.add_argument("--iterations", type=int, default=10)
    parser.add_argument("--input", choices=["leap", "wheel", "map"], default="leap")
    parser.add_argument("--topo", type=pathlib.Path, help="optional topo binary for its synthetic preview network")
    parser.add_argument("--out", type=pathlib.Path, default=pathlib.Path("build/panel-performance"))
    parser.add_argument("--max-gap-ms", type=float, help="optional main-thread stall budget; exits nonzero if exceeded")
    args = parser.parse_args()
    app = args.app.resolve() / "Contents/MacOS/topophany-bar"
    if not app.is_file() or args.iterations < 2:
        parser.error("provide a built Debug app and at least two iterations")
    output = args.out.resolve()
    output.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="topophany-panel-perf-") as directory:
        temporary = pathlib.Path(directory)
        source, notifier = temporary / "notify.swift", temporary / "notify"
        source.write_text(NOTIFIER)
        subprocess.run(["xcrun", "swiftc", str(source), "-o", str(notifier)], check=True)
        results = [capture(app, notifier, temporary, output, theme, args.language, args.iterations,
                           args.topo.resolve() if args.topo else None, args.input) for theme in args.theme or ["native", "terminal"]]
    (output / "summary.json").write_text(json.dumps(results, indent=2) + "\n")
    if args.max_gap_ms is not None and any(t["maximumGapMilliseconds"] > args.max_gap_ms for r in results for t in r["traces"]):
        raise SystemExit(f"main-thread stall budget exceeded; see {output / 'summary.json'}")
    print(f"Saved scroll samples and drawing costs to {output}")


if __name__ == "__main__":
    main()
