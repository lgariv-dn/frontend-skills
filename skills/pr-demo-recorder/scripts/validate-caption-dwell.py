#!/usr/bin/env python3
"""
validate-caption-dwell.py — check caption dwell budget in a webreel config.

Why this exists
---------------
webreel captions (the `key` / F13 beat pattern) are visible for ~800 ms natively
and can be extended to N ms via extend-timeline.py. But the extension caps at
the next caption's start. If two captions are too close together, the first one
gets truncated — viewer can't read it.

This script walks a webreel.config.json, finds every F13 `key` step, and tallies
the post-caption step durations (delay, pause, moveTo/hover/click delay fields)
until the next F13 or end-of-video. It flags any caption under its required budget.

Budget rules (matching SKILL.md Phase 4 guidance):
    - Action captions (2–4 words)      → need ≥1500 ms post-caption dwell
    - Reveal captions (5–9 words)      → need ≥2500 ms post-caption dwell
    - Long reveal captions (>9 words)  → need ≥3000 ms post-caption dwell

Word count determines which budget applies. Override with --target-ms to check a
uniform budget for all captions.

Usage
-----
    validate-caption-dwell.py <config.json>                    # per-word-count budgets
    validate-caption-dwell.py <config.json> --target-ms 2500   # uniform budget
    validate-caption-dwell.py <config.json> --verbose          # show every caption + budget
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

# Default per-word-count budgets (ms)
BUDGET_ACTION_MS = 1500    # 2–4 words
BUDGET_REVEAL_MS = 2500    # 5–9 words
BUDGET_LONG_MS = 3000      # >9 words


def word_count(label: str) -> int:
    """Count words in a caption label."""
    return len([w for w in label.split() if w.strip()])


def budget_for(label: str, override_ms: int | None) -> int:
    """Return the dwell budget (ms) for a caption based on word count."""
    if override_ms is not None:
        return override_ms
    n = word_count(label)
    if n <= 4:
        return BUDGET_ACTION_MS
    if n <= 9:
        return BUDGET_REVEAL_MS
    return BUDGET_LONG_MS


def step_duration_ms(step: dict, default_delay_ms: int) -> int:
    """Approximate the real-time duration of a step in ms."""
    action = step.get("action")
    # `pause` uses `ms`; everything else uses a per-step `delay` plus the
    # default. The webreel CLI adds defaultDelay AFTER each step.
    if action == "pause":
        return int(step.get("ms", 0))
    # Per-step delay (after the action completes) plus default delay.
    delay = int(step.get("delay", 0))
    return delay + default_delay_ms


def is_key_step(step: dict) -> bool:
    """Is this step an F13 (or any key) caption trigger?"""
    return step.get("action") == "key"


def validate_video(video_name: str, video: dict, override_ms: int | None, verbose: bool) -> int:
    """Validate caption dwell for a single video. Returns count of failures."""
    steps = video.get("steps", [])
    default_delay = int(video.get("defaultDelay", 0))

    # Find indices of all key steps (captions).
    key_indices = [i for i, s in enumerate(steps) if is_key_step(s)]
    if not key_indices:
        if verbose:
            print(f"  [{video_name}] no key (caption) steps found — skipping")
        return 0

    failures = 0
    for idx, key_pos in enumerate(key_indices):
        label = steps[key_pos].get("label", "")
        if not label:
            continue  # no caption — nothing to validate

        # Find the next caption (or end of steps).
        next_key_pos = key_indices[idx + 1] if idx + 1 < len(key_indices) else len(steps)

        # Sum durations of steps AFTER this key up to (but not including) the next key.
        dwell_ms = sum(step_duration_ms(steps[i], default_delay) for i in range(key_pos + 1, next_key_pos))

        budget = budget_for(label, override_ms)
        words = word_count(label)
        status = "OK" if dwell_ms >= budget else "UNDER"

        if verbose or status == "UNDER":
            marker = "✓" if status == "OK" else "✗"
            label_short = label if len(label) <= 60 else label[:57] + "…"
            print(f"  [{video_name}] {marker} {dwell_ms:>5}ms / {budget}ms ({words}w) — {label_short}")

        if status == "UNDER":
            failures += 1
            shortfall = budget - dwell_ms
            print(f"      shortfall: {shortfall}ms. Add a trailing `pause` or bump delays before next caption.")

    return failures


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("config", help="Path to webreel.config.json")
    parser.add_argument("--target-ms", type=int, default=None,
                        help="Override — check every caption against a single ms budget (default: per-word-count rules)")
    parser.add_argument("--verbose", action="store_true", help="Show every caption, including passing ones")
    args = parser.parse_args()

    config_path = Path(args.config)
    if not config_path.exists():
        print(f"Error: config not found at {config_path}", file=sys.stderr)
        return 1

    with open(config_path) as f:
        config = json.load(f)

    videos = config.get("videos", {})
    if not videos:
        print("Error: no `videos` map in config", file=sys.stderr)
        return 1

    total_failures = 0
    for name, video in videos.items():
        total_failures += validate_video(name, video, args.target_ms, args.verbose)

    print()
    if total_failures == 0:
        print("All captions meet their dwell budget.")
        return 0
    else:
        print(f"{total_failures} caption(s) under budget. Fix before recording.", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
