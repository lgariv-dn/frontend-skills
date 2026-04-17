# Iteration economy — cheapest-tool-first

Every iteration has a cost. Pick the cheapest tool that will tell you what you need to know.

## Time budget per iteration tool

| Tool                               | Time    | What it tells you                                          |
|------------------------------------|---------|------------------------------------------------------------|
| `validate-caption-dwell.py`        | <1 s    | Will any caption get truncated?                            |
| `npx webreel record --dry-run`     | ~2 s    | Does the config parse? Are selectors well-formed?          |
| `npx webreel preview --verbose`    | ~10 s   | Does each step actually find its element? (visible browser)|
| `extend-timeline.py`               | ~2 s    | Timeline updated (no re-record needed)                     |
| `npx webreel composite`            | ~5–10 s | Re-renders video from existing frames + modified timeline  |
| Thumbnail inspection (`.png`)      | ~1 s    | What state is the page in at frame 0?                      |
| Full re-record (`npx webreel record`)| ~30–90 s | Everything above + captures new frames                   |

The economics: **a full re-record is 30–90× more expensive than a dry-run.** Burn the cheap tools first.

## Decision tree — "my recording looks wrong, what now?"

```
What's wrong?
│
├── Config won't parse (syntax error)
│   → npx webreel record --dry-run   [2 s]
│
├── Selector didn't match at step N
│   → npx webreel preview --verbose   [10 s, shows visible browser]
│   → Use Chrome DevTools MCP to inspect the element and pick a better selector
│   → Does `moveTo` reveal the hover state? Try `hover` instead (see troubleshooting.md)
│
├── Caption wrong text
│   → Edit the "label" in the config
│   → npx webreel composite <name>   [5–10 s, no re-record]
│
├── Caption timing wrong (too short / truncated)
│   → extend-timeline.py <name> --target-ms <N>   [2 s]
│   → npx webreel composite <name>   [5–10 s]
│
├── Thumbnail shows loading state / wrong page state
│   → waitFor is resolving too early; tighten it to a content selector
│   → Full re-record   [30–90 s]
│
├── Cursor lands in wrong position
│   → Selector is ambiguous or element moved between steps
│   → Debug in preview mode, then full re-record
│
├── Viewport issue (target below fold)
│   → Change viewport in config
│   → Full re-record
│
└── Video file too big for PR attachment
    → Adjust quality/fps/duration in config
    → Re-composite if frames already captured, else re-record
```

## The rule

**Always ask:** "can `composite` answer this, or do I need new frames?"

- If the question is about pixel output, overlays, captions, cursor theme — `composite` can answer it.
- If the question is about cursor motion, page state, timing — you need new frames.

## Pre-record ritual (before `npx webreel record`)

In order, under 15 s total:

```bash
# 1. Dry-run to confirm config parses
npx webreel record --dry-run <name>

# 2. Caption dwell check
scripts/validate-caption-dwell.py webreel.config.json

# 3. Preflight — URL, env, tokens
scripts/preflight-check.sh "$URL" --expect "<content text>"
```

Then record.

## Post-record ritual (after `npx webreel record`)

```bash
# 1. Inspect frame 0 (fastest sanity check)
open videos/<name>.png

# 2. Extend caption dwell to readable length
scripts/extend-timeline.py <name> --target-ms 3000

# 3. Re-composite
npx webreel composite <name>
```

## When to use `preview` vs `record`

Use `preview` when:
- You're building a new flow and don't know if the selectors match
- You changed a selector and want to verify the interaction still works
- You want to watch the steps execute at human speed (visible browser)

Use `record` when:
- You're confident the flow works and want the final MP4
- You've used `preview` once and everything worked

**Don't skip preview.** A 10-second preview catches selector issues a 60-second record would also catch — for 1/6th the time.

## Frame-0 thumbnail as the first signal

Every `record` produces `<videos>/<name>.png` — a thumbnail from frame 0. Open it before you even watch the MP4:

- Loading state? → `waitFor` needs tightening
- Wrong URL? → You're on the SPA 404 page
- Cursor in wrong place? → The starting cursor position may be misconfigured
- Page looks right? → Now check the MP4

## The meta-rule

**The cost of "I should probably just re-record" compounds.** Eight iterations at 60 s each is 8 minutes wasted. Eight iterations of `composite` is 40 s total. Default to the cheap tool; escalate only when it genuinely can't answer the question.
