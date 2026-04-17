#!/usr/bin/env python3
"""
extend-timeline.py — stretch webreel HUD (caption) frames so captions stay
visible long enough to read.

Why this exists
---------------
webreel 0.1.4 hardcodes a ~800 ms HUD dwell on every `pressKey` step. A label
attached to a non-key step (click, moveTo, pause) is silently ignored at
composite time. So a `{ "action": "key", "key": "F13", "label": "..." }` beat
only shows its caption for ~800 ms, which isn't enough to read anything longer
than 2–3 words.

Fix: walk the timeline JSON webreel produces, find each contiguous run of
HUD-carrying frames, and copy the HUD payload forward into the following
frames until either (a) we hit the target dwell, or (b) the next HUD run
starts. Then re-composite — no re-record required.

Usage
-----
    extend-timeline.py <video-name> [--target-ms 2500] [--config webreel.config.json]

The script locates the timeline at:
    <config-dir>/.webreel/timelines/<video-name>.timeline.json

On first run it creates a `.bak` backup; subsequent runs always read from the
backup, so re-running is idempotent (you can bump `--target-ms` and re-run
without stacking extensions).

After running this, re-composite with:
    npx webreel composite <video-name>
"""

from __future__ import annotations

import argparse
import json
import os
import shutil
import sys
from pathlib import Path


def has_hud(frame: dict | None) -> bool:
    """Return True iff this frame carries a caption."""
    if not frame:
        return False
    hud = frame.get("hud")
    # Critical: webreel writes `null` (not `{}`) for non-HUD frames. Check
    # truthiness before indexing, or you'll hit AttributeError on None.
    if not hud:
        return False
    return bool(hud.get("labels"))


def find_hud_runs(frames: list[dict]) -> list[tuple[int, int, str]]:
    """Identify contiguous HUD-carrying frame ranges.

    Returns a list of (start_idx, end_idx_inclusive, first_label) tuples.
    """
    runs: list[tuple[int, int, str]] = []
    i = 0
    n = len(frames)
    while i < n:
        if has_hud(frames[i]):
            start = i
            while i < n and has_hud(frames[i]):
                i += 1
            labels = frames[start]["hud"]["labels"]
            first_label = labels[0] if labels else ""
            runs.append((start, i - 1, first_label))
        else:
            i += 1
    return runs


def extend_runs(frames: list[dict], runs: list[tuple[int, int, str]], target_frames: int) -> list[int]:
    """Extend each HUD run forward by copying its hud payload into subsequent
    non-HUD frames, stopping at either `target_frames` duration (from the
    run's start) or the start of the next run — whichever comes first.

    Returns a list of extension counts (one per run), matching runs[] order.
    """
    extensions: list[int] = []
    for idx, (start, end, _) in enumerate(runs):
        next_run_start = runs[idx + 1][0] if idx + 1 < len(runs) else len(frames)
        extend_to = min(start + target_frames - 1, next_run_start - 1, len(frames) - 1)
        hud_data = frames[end]["hud"]

        extended = 0
        for fi in range(end + 1, extend_to + 1):
            if not has_hud(frames[fi]):
                frames[fi]["hud"] = hud_data
                extended += 1
        extensions.append(extended)
    return extensions


def locate_timeline(config_path: Path, video_name: str) -> Path:
    """Given a webreel config and a video name, return the path to the
    corresponding timeline JSON."""
    config_dir = config_path.parent
    timeline = config_dir / ".webreel" / "timelines" / f"{video_name}.timeline.json"
    if not timeline.exists():
        raise FileNotFoundError(
            f"Timeline not found at {timeline}. "
            f"Run `npx webreel record {video_name}` first."
        )
    return timeline


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("video_name", help="Video name as defined in webreel.config.json")
    parser.add_argument("--target-ms", type=int, default=2500,
                        help="Target caption duration in milliseconds (default: 2500)")
    parser.add_argument("--config", default="webreel.config.json",
                        help="Path to webreel.config.json (default: ./webreel.config.json)")
    parser.add_argument("--fps", type=int, default=None,
                        help="Override FPS (default: read from timeline JSON)")
    args = parser.parse_args()

    config_path = Path(args.config).resolve()
    if not config_path.exists():
        print(f"Error: config not found at {config_path}", file=sys.stderr)
        return 1

    try:
        timeline_path = locate_timeline(config_path, args.video_name)
    except FileNotFoundError as exc:
        print(f"Error: {exc}", file=sys.stderr)
        return 1

    backup_path = timeline_path.with_suffix(timeline_path.suffix + ".bak")
    source_path = backup_path if backup_path.exists() else timeline_path
    if not backup_path.exists():
        shutil.copy2(timeline_path, backup_path)

    with open(source_path) as f:
        data = json.load(f)

    frames = data.get("frames")
    if not frames:
        print(f"Error: timeline has no 'frames' array", file=sys.stderr)
        return 1

    fps = args.fps or data.get("fps", 60)
    target_frames = int(fps * args.target_ms / 1000)

    runs = find_hud_runs(frames)
    if not runs:
        print("No HUD runs found in timeline. Did you include `key F13` steps?", file=sys.stderr)
        return 1

    print(f"Found {len(runs)} HUD run(s) in timeline:")
    for start, end, label in runs:
        native_ms = (end - start + 1) * 1000 // fps
        print(f"  frames {start}-{end} (~{native_ms}ms): {label[:70]}")

    print(f"\nExtending to {args.target_ms}ms (target: {target_frames} frames at {fps}fps)…")
    extensions = extend_runs(frames, runs, target_frames)

    for idx, (start, end, _) in enumerate(runs):
        next_run_start = runs[idx + 1][0] if idx + 1 < len(runs) else len(frames)
        extend_to = min(start + target_frames - 1, next_run_start - 1, len(frames) - 1)
        actual_ms = (extend_to - start + 1) * 1000 // fps
        print(f"  run {idx + 1}: +{extensions[idx]} frames → {actual_ms}ms visible")
        if actual_ms < args.target_ms:
            capped_by = "next caption" if next_run_start < len(frames) else "timeline end"
            print(f"    (capped early by {capped_by}; increase dwell between captions to get the full {args.target_ms}ms)")

    with open(timeline_path, "w") as f:
        json.dump(data, f)

    print(f"\nTimeline updated: {timeline_path}")
    print(f"Backup preserved:  {backup_path}")
    print(f"\nNow re-composite:  npx webreel composite {args.video_name}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
