---
name: pr-demo-recorder
description: Records scripted webreel demos of a PR's changes using the current branch's PR description, linked Jira ticket, reproduction artifacts, and newly-added Playwright E2E tests as the source of truth. Use when the user asks to "create a demo for this PR", "record a webreel for AR-XXXXX", "demo this fix/feature", "generate a demo video", "make a video of the E2E flow", "demo this epic", or "record a visual for this change". Handles single-concern PRs, large multi-concern PRs, and epic-level demos with one or many videos. Always plans scope, flow, data source, and format with the user via AskUserQuestion before recording — never records unprompted.
---

# PR Demo Recorder

Records scripted webreel demos from PR context. Pulls research from the PR description, Jira ticket, reproduction artifacts, and newly-added Playwright E2E specs. Plans the flow interactively with the user, then generates `webreel.config.json`(s) and records MP4/GIF/WebM.

## Prerequisites

Before anything else, run the environment check:

```bash
bash dap-workspace/.claude/skills/pr-demo-recorder/scripts/ensure-webreel.sh
```

The script verifies four things in order and exits non-zero at the first failure:

1. **webreel CLI** — installed globally via `npm` or project-local via `npx`. If missing, prompts to run `npm install -g @lgariv/webreel` (a scoped fork of vercel-labs/webreel that adds cinematic autozoom; the binary is still invoked as `webreel`).
2. **Companion webreel Claude skill** at `~/.claude/skills/webreel/`. If missing, offers to fetch it from `lgariv-dn/webreel` (the same fork — its companion skill documents the `autoZoom` field).
3. **`gh` CLI** — required for PR metadata and asset upload. If missing, the script **prints install instructions and exits** (user must install + authenticate before retrying). There is no auto-install for `gh` because it's an OS-level package manager install.
4. **`gh-image` extension** (`drogers0/gh-image`) — required to upload demo videos to GitHub user-attachments programmatically. If missing, **auto-installs silently** via `gh extension install drogers0/gh-image`. If install fails, the script exits non-zero.

Do not proceed past a non-zero exit. The script is the sole source of truth for "is this skill's runtime ready?" — every later phase assumes all four dependencies are present.

## Workflow

Run every phase in order. Do not skip to recording.

### Phase 1 — Research (no user prompts yet)

Gather context in parallel:

```bash
git branch --show-current
gh pr view --json number,title,body,headRefName,baseRefName
gh pr diff --name-only
```

Then, from those outputs:

- **Extract the Jira ticket** — e.g. branch `lgariv/ar-58199/fix-...` → `AR-58199`, or pluck from PR title.
- **Fetch the Jira issue** via `mcp__claude_ai_Atlassian__getJiraIssue` — read description, acceptance criteria, recent comments, linked issues.
- **Detect epic scope** — if the ticket has an `Epic Link` or child stories, note the epic key and fetch children via `mcp__claude_ai_Atlassian__searchJiraIssuesUsingJql` with `parent = EPIC-KEY`.
- **Filter the diff** for `*.e2e.spec.ts`, `*.seed.ts`, and seed YAML files — these encode the exact verified flow.
- **Read the new E2E specs** — each `await x.click()` / `await expect(...)` is a future webreel step.
- **Read referenced Page Object Models** — POMs hold the authoritative selectors. See [references/pom-to-webreel.md](references/pom-to-webreel.md).
- **Find repro artifacts** — `/tmp/<ticket>_*.yaml`, instance IDs mentioned in PR body or Jira comments, screenshots.

Produce a short internal summary: what the PR changes, what the E2Es exercise, what demo-worthy moments exist. Keep it for yourself; don't dump it on the user.

### Phase 2 — Plan with the user (AskUserQuestion)

Never assume. Ask about every non-obvious decision. Batch 1–3 related questions per `AskUserQuestion` call, and iterate — when an answer opens a new decision, ask it next. Asking is cheaper than re-recording.

**Minimum decisions to elicit:**

1. **Scope** — one video or several? If several: grouped by (a) PR concern, (b) E2E spec file, or (c) epic child story?
2. **Flow per video** — what must the cursor tour show? Offer concrete options derived from the research: "bug-fix before/after", "feature walkthrough", "critical E2E path", "full user journey". Include a short preview of each in the question's `description`.
3. **Data source** — reuse the repro instance (paste the ID you found), seed a fresh instance via API, or let the user execute interactively in the browser first?
4. **Environment** — confirm dev server is on the fix branch. If `git branch --show-current` doesn't match the fix branch, flag it and ask whether to switch.
5. **Viewport + format** — desktop preset (`1920×1080`, `1600×900`, `macbook-pro`)? Output: MP4 / GIF / WebM? Duration target (short <10s / standard 15–30s / detailed 30–60s)?
6. **Captions / HUD** — include keystroke overlays, custom cursor theme, or annotation callouts?
7. **Autozoom** — the `@lgariv/webreel` fork ships an opt-in cinematic zoom that eases the camera into each interaction target, holds through the action, and releases to the full viewport. It dramatically improves readability of small UI (form fields, icon buttons, dropdown options) and gives the video a produced, Cursor-walkthrough-style feel. Ask the user:
   - **If the plan is ONE combined video** — use a **single-select `AskUserQuestion`** with exactly two options: `Enable autozoom` (recommended when the demo hits any form input, dropdown, small icon button, or modal; the fork's default tuning works well — no config needed) and `Disable autozoom` (recommended when the demo is mostly large UI areas, full-page content, or long scrolls where a zoomed frame would crop important context). Pick the first option by default in the `AskUserQuestion`'s list if any action target is <40% of the viewport; pick the second default if the flow is dominated by full-page views.
   - **If the plan is MULTIPLE videos** — use a **multi-select `AskUserQuestion`** (`multiSelect: true`) listing every planned video by its `name` with a short one-line description, and let the user pick which subset should have autozoom enabled. Videos NOT selected stay on the default (no autozoom). Phrase the question as: *"Which of these videos should use the cinematic autozoom? (uncheck any that are mostly full-page / large-UI flows.)"*

   When autozoom is enabled for a video, set `"autoZoom": true` at the video level in `webreel.config.json`. For fine control, an object can override defaults (`approachS`, `sessionGapS`, `minZoomRatio`, etc.) — but default to `true` unless the user explicitly asks to tune.
8. **Delivery** — ALWAYS ask as a **multi-select `AskUserQuestion`** (set `multiSelect: true`) with exactly these three options — the user may pick any combination:
   - **Prepend to GitHub PR description** — upload via `gh image`, then `gh pr edit` to prepend the embed while preserving every byte of existing body content.
   - **Post as a comment on the linked Jira ticket** — upload once (reuse the `gh image` URL if already uploaded; otherwise upload separately for Jira) and post a comment on the Jira issue from branch/title (e.g. `AR-58199`) via the Atlassian MCP `addCommentToJiraIssue`.
   - **Save to the user's Downloads folder** — copy the MP4 (and thumbnail PNG if present) to `~/Downloads/` and report the absolute paths. No network upload.

   Do NOT offer Slack, disk-only-in-repo, gist, or other channels — keep this question stable and minimal. The user can always type custom text into the "Other" field if they need something else.

For **epic-level demos**: plan one video per child story, plus an optional "epic summary" video for the end-to-end user journey. Ask which subset of children to cover before you generate configs.

### Phase 3 — Verify environment

Before writing any config:

1. `curl -s -o /dev/null -w "%{http_code}" http://localhost:4200/` → expect `200`.
2. If reusing an instance ID, navigate to its URL via `mcp__chrome-devtools__navigate_page` and confirm key fix-related elements are present. Workflow definitions change; an instance that matched the repro yesterday may be stale today.
3. If the user's current checkout ≠ the fix branch, switch. Watch for untracked `.agents/skills/`* symlink conflicts — they're regenerable, safe to `rm` selectively before checkout.
4. If seeding fresh, use the DAP catalog API. See [references/research-sources.md](references/research-sources.md) for upload → approve → execute → poll recipes.

### Phase 3.5 — Lock captions BEFORE building the config

Captions anchor the demo's narrative. Every beat that follows — which element to hover, where the camera should zoom, what "evidence" to show — exists to support the caption's claim. If the user rejects a caption in favor of a different angle on the fix, the flow restructures with it: different hover targets, different zoom regions, possibly different beats. Doing caption review *after* the config is written means every caption change ripples into config edits you'd have to throw away.

Lock captions first. Build the config to serve them.

**Draft captions from the Phase 1 research + Phase 2 flow plan.** At this point you know the PR's fix(es), which E2E specs encode the verified flow, and how the user wants the video scoped. That's enough to draft 1–2 narrative captions per video without having touched a selector or written a config.

**Present variants per caption via `AskUserQuestion`.** The drafts you wrote are your recommendations; the user is the one shipping the demo. Offer 2–4 meaningfully-different takes — don't produce synonym-swapped near-duplicates. The templates in the caption-writing section above give you three voices:

- **Before/after arrow** — quotes literal UI strings: `"Before: 'No input data' → now: full workflow input."`
- **Natural prose with connectives** — uses `used to / now / no longer / previously`: `"Drill-back no longer resets the sidebar."`
- **Keynote declarative** — present-tense benefit-forward: `"Status icons persist through drill-back."`

**Example** for a bug-fix caption about a state-preservation fix:

```
Q: "Pick a caption for the post-drill-back moment, or write your own:"
  1. "Icons and expansion survive drill-back." (Recommended — natural prose, 39 ch, 6 w)
  2. "Before: state reset → now: fully preserved." (arrow template, 45 ch, 7 w)
  3. "Drill-back no longer resets the sidebar." (natural prose, 40 ch, 7 w)
```

Always include "Other" implicitly (auto-added). One "Recommended" per question (your best pick first, per global user instructions).

**Iterate each caption separately** — don't batch all captions into one question. Each caption gets dedicated attention.

Keep option labels to the caption text itself (≤ ~45 chars fits the question UI). Use the `description` field to tag voice style: `"Arrow template — quotes literal UI"`, `"Natural prose"`, `"Keynote declarative"`.

**If the user picks "Other" and their write-in implies a DIFFERENT fix or angle**, that's a flow-level change, not a caption-level change. For example, if your draft caption was "Branches nest under the split" and the user writes "Search now filters branch children", that's a completely different fix being showcased. Stop caption review, loop back to Phase 2's flow question, and re-plan the video. This is the catch the early caption review is designed to enable — cheap to fix here, expensive to fix after the config is built.

**After the final caption for a video is locked, move to Phase 4** and build the config with those captions baked in. The hover targets, zoom moments, and beat ordering all serve the approved captions.

### Phase 4 — Generate config(s)

Write `webreel.config.json` (one file can hold multiple named videos via the `videos` map; split into separate files only when format or base URL differs substantially).

**Selector priority** — pick the first strategy that matches uniquely:


| Priority | Example                                               | When                                      |
| -------- | ----------------------------------------------------- | ----------------------------------------- |
| 1        | `text: "Save", within: "#modal"`                      | Visible text that's unique within a scope |
| 2        | `selector: "button[aria-label=\"Navigate to root\"]"` | Icon buttons; i18n-robust                 |
| 3        | `selector: "[data-testid=\"...\"]"`                   | Explicit test hooks                       |
| 4        | `selector: "[data-part=\"branch-trigger\"]"`          | Ark UI / Radix primitives                 |
| 5        | `selector: "[class*=\"itemAction\"]"`                 | CSS Modules — match the pre-hash name     |
| 6        | `selector: "#details"`                                | Developer-assigned DOM IDs                |


**Never** use hashed CSS-Module class names literally (`.hz88NG_itemAction`). **Never** use Playwright-specific combinators (`:has-text(...)`). See [references/selector-strategies.md](references/selector-strategies.md).

**Map E2E steps directly** from the spec: `await x.click()` → `click`, `await expect(y).toBeVisible()` → `wait`, `await page.goto(url)` → the video's `url` + `waitFor`. See [references/pom-to-webreel.md](references/pom-to-webreel.md) for the full translation table.

**Pacing defaults**: `defaultDelay: 400`, 600–900ms `pause` between actions, 1000–1200ms at demo-critical moments (drill-back, status reveal, before/after state changes). `fps: 60`, `quality: 85`.

**Autozoom (`@lgariv/webreel` fork)**: for every video the user opted into autozoom (see Phase 2 item 7), add `"autoZoom": true` as a sibling of `url` / `viewport` / `steps` inside the video's object in `webreel.config.json`. Example:

```jsonc
"videos": {
  "my-video": {
    "url": "...",
    "viewport": { "width": 1920, "height": 1080 },
    "waitFor": ".app",
    "autoZoom": true,          // ← opt in
    "steps": [ /* ... */ ]
  }
}
```

- `true` uses the fork's tuned defaults (approach 0.5 s, release 0.5 s, minZoomRatio 0.6, sessionGapS 4.0) — these match Cursor's documentation walkthrough feel on form-style UI.
- The fork also runs a `MutationObserver` during click/drag steps so dropdowns, modals, and tooltips that open in response to a click get framed with their trigger in one shot (no lateral pan to re-center on the menu option).
- Use an object only when the user explicitly asks to tune: e.g. `{ "enabled": true, "minZoomRatio": 0.75 }` to cap peak zoom at ~1.33× for ultra-wide UI, or `{ "enabled": true, "sessionGapS": 2.5 }` to force more rest-at-wide between unrelated actions. Consult the fork's companion skill at `~/.claude/skills/webreel/SKILL.md` (already fetched by `ensure-webreel.sh`) for the full knob table.

**`sessionGapS` tuning for navigation-heavy flows.** The default `sessionGapS: 4.0` is calibrated for "click a trigger, see the response" patterns (button + modal, tab + panel) where all interactions cluster within 4 s. Drill-in / drill-back flows routinely exceed this: the drill click fires, the new view loads for ~2–3 s, then the breadcrumb click fires — total gap often ~4–5 s, just over the default threshold. Autozoom then splits the navigation into TWO sessions, producing a visible **zoom-in → zoom-out → zoom-in → zoom-out** double-pulse around what the viewer perceives as a single "go in, come back" action. This looks jittery and draws attention to navigation chrome instead of evidence.

**Diagnosis:** after recording with default autoZoom, inspect the `webreel record` stdout — it logs each autozoom event's timestamp (`t=5.27s`, `t=9.33s`, …). If any two consecutive events targeting navigation controls (drill button, breadcrumb, tab trigger, modal close) are **between 4.0 and ~6.5 s apart**, you'll see the double-pulse. Confirm by sampling frames at the gap midpoint — if the camera is wide when it logically should still be holding, you've hit this.

**Fix:** bump `sessionGapS` just enough to absorb the gap, e.g. `{ "enabled": true, "sessionGapS": 6.0 }`. This keeps the camera zoomed through the loading + drill-back, producing a single clean pulse around the whole navigation. Don't go much higher than ~7.0 — unrelated clusters later in the video (e.g. a second caption's hovers) need their own session to feel distinct, and at 8.0+ you risk fusing them with the navigation session into one sprawling hold.

**Alternative:** tighten the flow itself. Reducing the post-drill-in `pause` from ~1200 ms → ~600 ms, or dropping the explicit `hover` before a drill click (if the previous `moveTo` already put the cursor on the row and CSS `:hover` fires from the mouse position), can bring the gap under 4.0 s without any config knob. Faster navigation means fewer pauses means naturally merged sessions. Prefer this over `sessionGapS` tuning when the flow's pacing was already too slow anyway.

**Caption-after-zoom ordering — reveal captions must fire AFTER the camera settles, not before.** When autozoom is on, the camera needs ~500 ms to approach from wide → target crop before it "arrives" at the zoomed-in view. If the reveal `key` step fires while the camera is still wide (or mid-approach), the viewer reads the caption against an uninformative wide frame, then the camera zooms in right as the caption is fading. The viewer's eye is drawn away from the caption mid-read, and the punchline lands over a now-irrelevant wide shot. The correct pattern is "camera arrives first, caption appears on top of the zoomed evidence."

Mechanism: autozoom generates a zoom event for each `moveTo` / `hover` / `click` step. The camera approach is scheduled to **settle 0.15 s before the event's timestamp**, so the camera is already at the target crop by the time the cursor physically arrives. If the `key` step comes AFTER the `moveTo`, the caption naturally fires on the settled view. If the `key` step comes BEFORE the `moveTo`, the caption fires while the camera is still wide (or mid-approach).

**The rule — reorder reveal beats to put `moveTo` BEFORE the `key`:**

❌ **Wrong** (caption fires wide, camera zooms in while caption is mid-read):
```jsonc
{ "action": "key",    "key": "F13", "label": "Branches nested under the split." },
{ "action": "moveTo", "selector": "#sidebar [data-value='branch-1']" },
{ "action": "pause",  "ms": 2700 }
```

✅ **Right** (camera zooms in first, caption appears as zoom completes — no dead time):
```jsonc
{
  "defaultDelay": 0,                                                    // strip all inter-step padding
  "videos": {
    "my-video": {
      "autoZoom": { "enabled": true, "sessionGapS": 6.0 },
      "steps": [
        /* ... */
        { "action": "moveTo", "selector": "#sidebar [data-value='branch-1']", "delay": 0 },
        { "action": "key",    "key": "F13", "label": "Branches nested under the split." },
        { "action": "pause",  "ms": 2400 }                              // caption dwell budget
      ]
    }
  }
}
```

**Three pieces, all required:**

1. **Top-level `defaultDelay: 0`** — kills the implicit 400 ms padding webreel inserts after every step. Without this, a 400 ms gap opens up after the `moveTo` that can't be eliminated by any per-step setting.
2. **`"delay": 0` on the `moveTo` step** — overrides any step-level delay that would otherwise run AFTER the moveTo completes and before the next step starts.
3. **No `pause` step between `moveTo` and `key`** — any pause here directly adds dead-time to "camera settled but caption hasn't fired yet."

With all three, the HUD fires essentially the instant the cursor arrives at the target. Autozoom's approach settles 0.15 s **before** cursor arrival, so the caption appears ~150 ms after the zoom visually completes — close enough that the viewer perceives it as one motion: "camera arrives AND caption appears," no dead beat in between. Adding even a 300 ms pause here opens a visible gap; an 800 ms pause produces a full second of dead zoomed-but-silent frame before the HUD appears, which the viewer reads as "why are we waiting?"

**Caveats of `defaultDelay: 0`:**
- Every inter-step beat becomes tight. If you rely on implicit padding between, say, `click` and a subsequent `wait` for rendered content, the flow may race. Add **explicit `pause` steps** wherever the UI genuinely needs time to react (post-drill-in, post-route-change, modal-open animations). Think of pauses as a budget you now allocate manually instead of getting implicitly.
- Total video runtime drops noticeably — my AR-58199 demo fell from ~25 s to ~15 s after switching to `defaultDelay: 0`. This is a feature, not a bug: dead time was being padded into the recording even when nothing was happening.

For caption 2 of a two-caption demo, apply the same pattern: `moveTo (delay: 0) → key → pause dwell`. In practice this pairs cleanly with the "one hover to name the finding" rule — that single hover *is* the `moveTo` that triggers the zoom, and the `key` follows immediately after.

**Action captions (as opposed to reveal captions) don't need this ordering** — a 2-word imperative like "Click Start" is short enough that it's readable during the approach-phase without the reader noticing. Only reveal captions (5–7 words naming a fix) are long enough that the ordering matters.

**Keep the cursor moving during the caption dwell — don't freeze it for the full 3 s.** A reveal caption's full 3000 ms window is too long to sit on a static cursor. Viewers read the 5–7 words in ~1500 ms, then their eyes scan back to the scene. If the cursor is frozen on the initial target, the frame feels "paused" — the viewer has nothing to track while the caption is still up, and when the cursor finally moves *after* the caption fades, it feels like the demo "waited" for them.

The correct pattern walks the cursor through the evidence *during* the caption window, so the caption narrates what the viewer is actively watching:

```jsonc
{ "action": "moveTo", "selector": "<first-evidence-target>", "delay": 0 },   // hover 1 → triggers zoom
{ "action": "key",    "key": "F13", "label": "..." },                          // caption fires on zoomed view
{ "action": "pause",  "ms": 1000 },                                            // let caption register (~1 s)
{ "action": "moveTo", "selector": "<adjacent-evidence-target>" },              // hover 2 while caption still visible
{ "action": "pause",  "ms": 1400 }                                             // rest of caption dwell
```

**This is NOT a violation of the hover-count rule** — the second hover illustrates the SAME claim by walking through it (e.g., hovering the `Branch 2` wrapper, then hovering the `child` workflow nested inside it, both illustrating "nested under the split"). It's visual continuity for a single evidence point, not two separate findings.

Self-test: during the caption dwell, is the cursor *doing* anything the viewer can track? If it's static for >1 s while the caption is up, add a hover. Watch the clip and notice: when does the cursor start moving relative to when the caption appears? If the cursor only moves *after* the caption disappears, the viewer reads about something they can't see being pointed to.

The caption-2 pattern naturally satisfies this when the caption bundles two facts (e.g., "icons and expansion survive") because you already have two hovers showing each fact. Single-claim captions (caption-1) need the extra hover added explicitly.

**Captions only render on `key` action steps — and last only 800 ms unless you extend them.** Despite what the webreel docs suggest, in webreel 0.1.4 the HUD caption is drawn only when `pressKey` fires, and `pressKey` calls `showHud` → sleep 800 ms → `hideHud` — hardcoded. `label` on `click`, `moveTo`, `pause` etc. is **silently ignored at composite time**. A `delay` on the `key` step doesn't extend HUD visibility either — it only delays the next step. So the native output of a `key F13 + label "foo"` step gives you a caption visible for ~0.8 s, which is unreadable.

**Use the two-pass workflow: record, then extend-and-composite.**

1. **Record pass** — include a `{ action: "key", key: "F13", label: "..." }` step at each narrative beat. F13 is the chosen benign key (modifier-only keys like `Shift` are rejected with "pressKey requires a non-modifier key"). The `key` step anchors a caption entry in the timeline at a precise timestamp. Keep the immediately-following action steps (`click`, `moveTo`, etc.) short with minimal `delay`s — the long visible window comes from the timeline pass, not from `pause`s between steps. Example beat:
   ```jsonc
   { "action": "key",   "key": "F13", "label": "Click Start \u2192 see the workflow input" },
   { "action": "click", "selector": ".react-flow__node[data-id=\"start-state\"]", "delay": 800 },
   { "action": "wait",  "text": "Input", "within": "#details", "timeout": 10000 },
   { "action": "pause", "ms": 600 }
   ```

2. **Timeline-extend pass** — webreel writes a timeline JSON to `.webreel/timelines/<video-name>.timeline.json` with a `frames` array, one entry per recorded frame. Each frame has an optional `hud: { labels: [...] }`. Native recording populates ~48 consecutive frames per caption (~800 ms at 60 fps). Walk the timeline, detect each run of contiguous HUD frames, and **copy the label across subsequent frames up to the target duration, or until the next HUD run starts, whichever comes first**. Default target: **3000 ms (180 frames at 60 fps)** — verified readable for 6–10 word captions without bloating runtime. Bump to 3500–4500 ms only for verbose labels (>12 words). This stretches the caption's visibility without re-encoding or re-recording. Implementation: a Python script that backs up the timeline to `.json.bak` on first run, always reads from the backup for idempotency, and writes the extended timeline back.

3. **Composite pass** — `npx webreel composite <video-name>`. Re-runs only the overlay compositor using the modified timeline + the raw frames (already stored under `.webreel/raw/`). Takes ~5–10 s per video instead of 30–60 s for a full re-record. This is the step that actually produces the user-visible MP4 with the extended captions burned in.

**Why this is the right pattern:**
- Captions appear during the cursor movement and click — exactly what the user originally asked for — because the timeline extension overlaps the caption with the post-`key` action steps.
- 3000 ms is the sweet spot: long enough to read comfortably (covers 6–10-word captions), short enough to keep the video moving.
- No ffmpeg post-processing, no repeated recording, no reliance on docs claims that don't hold in 0.1.4.

**Prove the value, don't just click.** After a beat's click reveals content, follow with **short `moveTo` hovers (700–1000 ms each) over the specific values that demonstrate the fix**. The click tells "what I did"; the hovers show "what this produced." Keep hover dwell short — once the cursor lands and the viewer registers the value for ~1 s, move on. Long hover dwell adds no signal.

**Hover COUNT is as important as hover duration — one hover per distinct evidence point, not one per visible element.** Walking the cursor through sibling items in a tight cluster ("Branch 1 → Branch 2 → child" in a 200-px-tall sidebar) is a time tax when each item carries the same evidence the caption just announced. The viewer absorbs the tree shape at a glance once the caption frames it; pointing at every row replays information they've already read.

Budget per reveal caption:
- **One hover** to name the finding the caption describes (e.g., hover the nested branch that proves "nested under the split").
- **Optionally a second hover** if — and only if — it names a DIFFERENT fact the caption bundles together. Example: "Icons and expansion survive drill-back." genuinely combines two fixes, so hovering the status icon (proof of icons) AND the nested grandchild (proof of expansion) is legitimate.
- **Three or more hovers on siblings in <200 px of viewport space is a red flag.** Collapse to the one hover that tells the viewer something they can't read from the caption plus the still frame. If you can't name a distinct fact each extra hover reveals, cut it.

**Self-test before adding each extra hover:** "If I removed this hover, would the viewer lose evidence, or just lose a repeat of the caption?" If the latter, cut it. Extra hovers inflate runtime and train the viewer to tune out — the demo feels slow and the punchline lands softer.

### Caption writing — phrase every label on purpose

Captions are the spine of the demo. Vague labels like "Task input we passed in" waste screen time. Every caption must satisfy these rules:

1. **Length: ≤7 words AND ≤45 characters, one line.** Both limits are load-bearing and both must hold:
   - Words drive read time — >7 words is unreadable in the 3000 ms window.
   - Characters drive HUD pixel width. At `DEFAULT_HUD_THEME.fontSize=56`, each caption char is ~34 px. A 50-char caption is ~1680 px wide — already larger than a 1600×900 frame. The `@lgariv/webreel-core` clamp (≥ `0.1.4-beta-20260418T145700Z`) now shrinks oversized HUDs to fit via SVG `viewBox`, but the shrunk text reads worse than a caption written short to begin with. On older webreel without the clamp, oversized HUDs crash the compositor and hang ffmpeg — see `references/troubleshooting.md § Image to composite`.

   **5–6 words / ~30–40 chars is the sweet spot; 7 words / 45 chars is the hard ceiling.** If your draft exceeds either, cut qualifiers before shortening vocabulary. Example: "Branches nest under the split, in execution order." (50 ch, 8 w) → "Branches nest under the split." (30 ch, 5 w) — the hovers below already demonstrate the order nuance; the caption doesn't need to carry it.
2. **Pick a style based on PR type:**
   - **Bug-fix PRs → Before→After contrast** (changelog voice). Use an arrow (`→`) to make the delta explicit. The viewer is typically a reviewer who needs to see the fix.
   - **New-feature PRs → Keynote reveal** (Apple-keynote voice). Declarative, present-tense, benefit-forward. The viewer wants the capability, not the bug story.
   - **Infra / refactor / perf PRs → Keynote reveal** with a metric instead of a benefit when available ("10× faster", "5 fewer renders", "No more network roundtrip").
3. **Action captions are OPTIONAL — drop them when the cursor action is self-evident.** Regardless of PR type, when an action caption is used it's a 2–4 word imperative ("Click Start", "Open the Completed tab", "Drag Branch 2"). But captions must *earn* their screen time — if the cursor visibly lands on the obvious target and the UI immediately responds, the caption just echoes the pixels and trains the viewer to skim-read. **Default to no caption on such beats.** Spend captions on (a) before/after state reveals, (b) behaviors the viewer would miss without annotation ("Embedded tree expanded by default"), (c) values-on-hover that name what's being shown. The STYLE distinction lives in the **reveal captions** — the ones that announce what changed.

   **Self-test before adding an action caption:** "If I remove this caption, does the viewer lose information or just lose a redundant echo?" If the latter, drop it. Captions like "Drill into child", "Back via breadcrumb", "Open the panel" — where the cursor motion + click fully communicate the action — are the common failure mode. When unsure, consult the user with concrete options (including one that drops the caption entirely) rather than shipping a narrating caption.

#### Bug-fix example (AR-55120 pattern) — use this for bug-fix PRs

```
Action:  "Click Start"                                              (2w)
Reveal:  "Before: 'No input data' → now: full workflow input."      (8w)
Action:  "Click Finish"                                             (2w)
Reveal:  "Before: 'No output data' → now: workflow output."         (7w)
```

The arrow template `Before: <literal UI string> → now: <new UI state>.` is ONE tool — it shines when you can quote literal UI text on both sides. It is NOT the default voice for every bug-fix caption. When there's no literal string to quote on the "before" side, the template collapses into telegram-speak ("Before: status icons disappeared → now: stay present.") that reads like machine translation. In those cases, **write a natural-prose sentence instead** using connectives like *used to / previously / no longer / now / instead of*:

```
Natural prose (preferred when no literal UI string to quote):
  "Branches were flat; now nested under the split."            (8w)
  "Drill-back used to drop status icons; now they persist."    (9w)
  "The sidebar no longer resets on return."                    (7w)

Arrow template (preferred when quoting a literal UI placeholder):
  "Before: 'No input data' → now: full workflow input."        (8w)
  "Before: 'No output data' → now: workflow output."           (7w)
```

Read every caption aloud. If it sounds stilted — comma-arrow-fragment, verb tenses that don't match, missing connective words — rewrite as a single natural sentence. The caption should read like a reviewer describing the fix in one breath, not like a template filled in by a script.

##### Why this specific shape beats the variants that keep failing review

Every alternative phrasing that a reasonable-looking draft reaches for — and that a reviewer will bounce — fails for the same underlying reason: **it describes the bug from the engineer's perspective, not the reviewer's.** The reviewer lived with the bug as visible UI. The engineer fixed the bug as code. A caption that reads like the commit message is invisible; a caption that reads like the bug report hits.

Rejected patterns, why they fail, and the quote-the-UI replacement:

| Rejected caption | What went wrong | Replacement |
|------------------|-----------------|-------------|
| `"Task input we passed in"` | First-person + no before-state + no evidence. Just narration. | `"Before: 'No input data' → now: full workflow input."` |
| `"Was empty → now shows workflow input."` | "Empty" is an abstract qualifier — empty what? The input section? The page? A value? Forces the viewer to interpret. | `"Before: 'No input data' → now: full workflow input."` |
| `"Hardcoded empty → real values."` | "Hardcoded" is a code concept the viewer can't see. "Real" is a meaningless contrast word (vs fake?). | Quote the placeholder string the hardcoded-empty rendered as. |
| `"Cleared selection before → now opens output."` | "Selection" is an engineering abstraction. Users don't think in selections; they think "I clicked and nothing useful happened." | `"Before: 'No output data' → now: workflow output."` |
| `"Blanked the panel"` / `"Panel went blank"` | Awkward verbs. "Blank" isn't a common verb. Descriptive of the *effect* rather than the *thing the viewer saw*. | Quote the placeholder or the actual empty-state text. |
| `"Click did nothing"` | Accurate but too abstract. Gives the viewer nothing to anchor on visually. | Quote what was on the screen during the "nothing" state. |
| `"Always empty"` / `"Full workflow input"` | Abstract qualifiers without an anchor. "Always empty" of what? "Full" of what? | Name the specific UI string that proved it was empty. |
| `"Real values. Every field."` | "Real" is a weak contrast. "Every field" hand-waves — which fields? | The hover beats already show the fields. Don't narrate what the cursor is about to demonstrate. |
| `"Before: status icons disappeared → now: stay present."` | Forced arrow template applied where no literal UI string is quoted. Grammatically inconsistent fragments ("disappeared" past-tense verb vs "stay" bare infinitive) welded by an arrow. Reads caveman-like. | Drop the template; write natural prose: `"Status icons used to vanish on drill-back; now they persist."` |

**The rule that makes the right phrasing fall out automatically:** *Before a reveal caption is finalized, grep the codebase for the user-facing placeholder string that rendered in the buggy state.* If you can find it (via `t('...noInput')`, `noData`, `emptyState`, `placeholder`, or a hardcoded string in the component), quote it. If you can't find one (the bug was behavioral, not a placeholder), describe what the viewer saw at the viewport level — "Page wouldn't load past row 20", "Save button stayed grey" — with quotes around anything literal.

##### The quotes are the evidence mark

Quotation marks in a caption signal "this is what was on screen, verbatim." They do two things at once:
- Compress the before-state to a recognizable trigger — any reviewer who lived with the bug recognizes the placeholder instantly.
- Create the contrast visually — the quoted string on the left of the arrow looks like a UI artifact; the unquoted phrase on the right looks like a description of the new reality. The typography itself carries the before/after distinction before the words do.

Treat the quotes as load-bearing punctuation, not decoration. Drop them and the caption stops landing.

##### When no placeholder exists

If the before-state had no visible text (e.g., a crash, a missing element, a silent failure), the fallback is a short concrete UI-level observation in quotes:

- `"Before: click did nothing → now: opens the details."` — if the bug was a dead click with no visible feedback
- `"Before: panel never updated → now: reflects the new state."` — if the bug was stale UI

Still prefer quoting anything literal you CAN quote (a tooltip, an aria-label, a confirmation dialog title) before reaching for abstract descriptions.

#### New-feature example — use this for feature-launch PRs

```
Action:  "Click Start"                                 (2w)
Reveal:  "Workflow input shows in the Overview."       (6w)
Reveal:  "All fields populated."                       (3w)
Action:  "Click Finish"                                (2w)
Reveal:  "Workflow output shows in the Overview."      (6w)
Reveal:  "Start and Finish are now clickable."         (6w)
```

Short present-tense statements of the new behavior. No contrast with the old state. Name what's on screen; don't editorialize it. Skip superlatives and emphasis flourishes — "always there", "right here", "every time", "now clickable" all read like marketing copy and undermine the caption's credibility. Em-dashes are allowed only when they add a specific location or qualifier, not for rhythm or emphasis. The caption should sound like a line in a Linear changelog, not a keynote tagline.

#### What to avoid in every caption

- Filler verbs ("we can see", "you'll notice", "this shows"). The viewer sees the screen; don't narrate.
- Adjectives without evidence ("proper", "correct", "improved"). Show the value, don't editorialize it.
- Superlatives and emphasis flourishes ("always there", "right here", "every time", "just works"). They sound like marketing. State the fact plainly: "shows in the Overview", "populated" — without the selling. *Exception:* "now" is fine as a temporal marker when the caption is pointing at something that genuinely just became true ("Start and Finish are now clickable") — it signals newness, not emphasis.
- First-person possessives ("our", "we passed"). The viewer isn't on your team.
- Repeating the section header ("The Input section shows input"). Caption should add something the section header doesn't already say.
- Three-clause sentences. If you need a comma AND a dash AND an arrow, you're writing documentation, not a caption.

### Caption-state matching: place each reveal caption where its "after" state is newly visible

A reveal caption claims a transition — "X used to be broken; it's now fixed." The viewer believes the claim only if, at the moment the caption appears, they can see evidence of the new state that contradicts the claimed old state. If the UI at caption time is **identical in the broken and fixed builds** (because the bug hasn't triggered yet in this flow), the caption is misplaced — the viewer sees a normal-looking UI with a caption asserting it used to be broken, and the credibility gap makes every other caption suspect.

**Research rule (do this BEFORE drafting captions):**

For each fix in the PR, map it to the specific user-flow trigger where the old code would have rendered the broken UI. A fix for "sidebar collapses on drill-back" is only visible at the post-drill-back beat; a fix for "Save button disabled with valid input" is only visible after the user types valid input. A fix for "branches flat at root instead of nested" is visible at initial render.

Build a table like this in your research scratchpad:

| Fix | Old-code trigger | First visible "after" beat in recording |
|-----|------------------|-----------------------------------------|
| Branch nesting under split | Initial page load | Beat 1 (page load) |
| Status icons survive drill-back | After drill-back completes | Beat N (post-breadcrumb-click) |
| Expansion state preserved | After drill-back completes | Beat N (post-breadcrumb-click) |

Captions go on the "first visible 'after' beat" row for each fix. Fixes that share a trigger (rows 2 + 3 above) combine into one caption at that beat — don't fire two separate captions claiming the same transition at the same moment.

**Anti-pattern:** A single summary caption at t=0 listing every symptom in the PR. The viewer sees a clean sidebar and hears "status icons used to vanish" — but the icons are right there. The caption describes a future state (after drill-back in the old code) while the viewer is looking at a state that's identical across builds. Don't do it.

**Self-check for each caption:** "If the old (broken) code were running at this exact beat, what would the viewer see that's different from the current frame?" If the answer is "nothing different," the caption does not belong here — move it to the beat where the answer becomes concrete.

### Timing guarantee: each caption needs ≥3000 ms of post-caption dwell

Because the timeline-extend pass caps each caption at the NEXT caption's start time, a caption whose `key` step is followed by <3000 ms of steps (cursor travel + clicks + pauses) before the next `key` step gets truncated. Engineer the config so:

- Action captions (2–4 words): the following `click` + `wait` + `pause` total ≥1500 ms. Action captions are short — they don't need the full 3000 ms.
- Reveal captions (5–9 words): the following `moveTo`s / `pause`s total ≥3000 ms. If you've got 3 value hovers at ~800 ms each, that's 2400 ms + a 700 ms trailing pause = 3100 ms ✓.

The Python extend-script caps at the next HUD run, so over-allocating dwell is harmless — under-allocating truncates silently.

**What not to do:**

- Don't attach `label` to `click` / `moveTo` / `pause` steps expecting a caption — webreel 0.1.4 drops it silently.
- Don't pad `pause`s after a `key` step hoping the HUD stays up — it doesn't; `hideHud` has already fired by then.
- Don't reach for ffmpeg `drawtext` post-processing — it re-encodes the whole video for 30+ s and duplicates functionality webreel's own compositor already has.
- Don't attach the same caption to three consecutive beats — one caption per narrative moment.

**Below-the-fold sanity check** — after a config is written and before the first record run, think: *does every target element fit in the viewport when its parent panel is at its natural size?* Details panels and drawers often have internal `overflow-y: auto` that hides later sections behind scroll. For any step that relies on text or a node further down in a scrollable container, include an explicit scroll step. See **[references/common-interactions.md § Scroll the page or a specific component](references/common-interactions.md)** for the full scroll patterns — window vs. container scroll, negative `y` to go back up, picking the right scroll container when the obvious parent doesn't move, and chaining scrolls with `wait` for async content. Quick shape:

```json
{ "action": "scroll", "selector": "#details", "y": 300 },
{ "action": "pause", "ms": 600 }
```

If scrolling the obvious outer element (e.g. `#details`) doesn't produce visible movement across frame samples, the overflow is on an inner wrapper — target `#details > div`, `[class*="content"]` within the panel, or the specific CSS-Module class that carries `overflow-y: auto` in the component's stylesheet. Verify the scroll landed by sampling a post-scroll frame and reading it back. If the panel genuinely can't fit the content at any scroll position (rare — but some flex layouts cap visible height), fall back to a taller `viewport` or `zoom: 0.75–0.85` on that specific video rather than shipping a demo where critical content never appears.

### Phase 4.25 — Self-audit the config (before the user sees it)

You just wrote a config. Before you show the user anything — even the plain-English flow summary in Phase 4.5 — audit it yourself. The user shouldn't be the one who catches that you used a hashed CSS-Module class, or that caption 2 fires before its zoom settles, or that the "status icons survive" claim doesn't actually have a beat demonstrating status icons. That's YOUR job.

Two passes, in order:

#### Pass 1 — Re-read the source of truth, check evidence coverage

Open the Jira ticket and the PR description **fresh**. You read these in Phase 1 but your drafting attention has been on selectors and step shapes since — re-read now with a user's eye, skipping anything code-adjacent. Specifically:

- **PR body "The Problem" / "What happens" section** — the user-facing symptoms. Not "the tree rebuild produces nodes without instance_status" (that's code). Look at bullets like "Status badges disappear on drill-back" or "Branches are flat at root".
- **PR body "Solution" / "What now happens" section** — the user-facing new behaviors. Not "withResolvedInstanceStatus thread through recursive builder" (that's code). Look at "Branches now nest under the split" or "Status badges persist across drill-back".
- **Jira ticket Description + Acceptance Criteria** — these are what QA verifies against. Anything in AC should be demonstrated.

For **each user-facing bullet**, find the beat in your config that showcases it. Write it out as a mental table:

```
PR symptom / AC item                             → Config beat / caption
"Branches flat at root"                          → moveTo branch-1 + caption 1 "nested under the split"
"Status badges disappear on drill-back"          → moveTo completedIcon + caption 2 "icons and expansion survive"
"Embedded child's expanded state collapses"      → moveTo grandchild + caption 2 (same)
"Task order wrong"                               → ??? ← gap
```

If any row has `???` on the right, you have an evidence gap. Either:
- Add a beat (hover, click, or dedicated caption) that showcases the missing symptom, OR
- Decide explicitly that this symptom is out of scope for this demo and note it (e.g. "task order is implicitly proven by the nested structure — the viewer sees the correct order visually from the tree").

Do not ship a demo where a PR bullet has no corresponding beat. If the fix fixes three things and the video only shows one, reviewers will notice.

#### Pass 2 — Rule compliance checklist

Walk the config top-to-bottom and verify each rule. This is mechanical; do not skip steps.

**Captions:**
- [ ] Every reveal caption is ≤ 7 words AND ≤ 45 characters.
- [ ] Every reveal caption matches the "after" state visible at the frame it fires (not a symptom visible only in a different beat).
- [ ] For bug-fix PRs: captions use before→after arrow template (when a literal UI string is quotable) or natural prose with connectives (when not). Not forced arrow templates on non-quotable states.
- [ ] For feature PRs: keynote declarative voice, no before-state contrast.
- [ ] Action captions are dropped when the cursor motion is self-evident. If present, ≤ 4 words.

**Caption + zoom ordering:**
- [ ] For each reveal caption, the preceding `moveTo` fires BEFORE the `key` step (caption appears on zoomed view, not wide).
- [ ] The `moveTo` has `"delay": 0`, OR there is no intervening `pause` that would delay the `key`.
- [ ] Top-level `"defaultDelay": 0` is set so implicit 400 ms inter-step padding doesn't add dead time.

**Hovers:**
- [ ] Each reveal caption has at least one `moveTo` DURING the caption dwell (not frozen cursor for the full 3 s).
- [ ] No redundant hovers — no three-or-more hovers on sibling elements within < 200 px of each other unless each names a distinct evidence point the caption bundles.
- [ ] The "continuity hover" during dwell illustrates the caption's claim (same evidence region), not a separate finding.

**Selectors (every `moveTo`, `click`, `wait`, `hover`):**
- [ ] No hashed CSS-Module class names (`.hz88NG_itemAction`) — use `[class*="itemAction"]` instead.
- [ ] No Playwright-specific combinators (`:has-text(...)`) — use `text:` + `within:` or `getByRole` patterns.
- [ ] Selectors follow the priority table: visible text > aria-label > data-testid > data-part > fragment class match > DOM id.
- [ ] Every selector is scoped — `#embedded-workflows-sidebar [data-value=...]` not a bare `[data-value=...]`.

**Autozoom:**
- [ ] If enabled: `sessionGapS` set appropriately for the flow's navigation pacing (default 4 s, bump to ~6 s for drill-in/drill-back flows to avoid double-pulse zooms).
- [ ] Autozoom is NOT zooming on pure navigation clicks that don't reveal evidence (if it is, that's a sessionGapS or step-structure issue).

**Viewport + layout:**
- [ ] Every evidence target fits in the chosen viewport at its natural size.
- [ ] For any target in a scrollable container, there's an explicit `scroll` step before the beat.
- [ ] Caption width fits the viewport (ceiling-checked via the 45-char rule above).

**Timing:**
- [ ] Each reveal caption has ≥ 3000 ms of post-`key` dwell time budget (so extend-timeline can stretch it fully without truncation).
- [ ] Action captions have ≥ 1500 ms of dwell.

#### If anything fails, fix it in the config yourself and re-run the audit. Only when both passes are clean, proceed to Phase 4.5 (user confirmation).

### Phase 4.5 — Flow summary & go/no-go

Captions were locked in Phase 3.5 before the config was written. Now the config is built around them. The final gate before `webreel record` is a plain-English walkthrough of the flow — catches structural issues (wrong beats, missing moments, wrong order) cheaply, before recording + extend-timeline + composite + visual verification burns tokens and minutes.

Describe the final flow to the user in **plain English** — no JSON, no selectors, no step counts, no `moveTo` / `key` tokens. Think of it as the beat sheet a video editor would write. Then confirm with a single `AskUserQuestion`.

**What to include in the summary:**
- Where the video opens (screen name, what's visible)
- Each narrative beat as a sentence: what the cursor does, what the viewer sees change, what the caption says
- Any zoom-in moments (e.g. "camera zooms into the sidebar here")
- Approximate duration ("roughly 15 seconds")

**What to NOT include:**
- File paths, selectors, step indices
- `action: moveTo`, `key F13`, `pause 1200`
- Any mention of webreel internals

**Example summary:**

```
Here's the flow I'll record (~17 s):

1. Opens on the AR-58199 instance viewer, showing the full workflow canvas
   with the Task overview sidebar on the left.
2. Cursor moves up to the Branch 2 wrapper; camera zooms in on the sidebar.
3. Caption appears: "Flat before; now nested under the split."
4. While the caption is visible, cursor moves down to the child workflow
   nested inside Branch 2 — illustrates the depth of the nesting.
5. Cursor drills into the child workflow. Pause briefly inside.
6. Cursor clicks the breadcrumb to return to parent. Camera releases wide.
7. Camera zooms into the sidebar again for the second beat.
8. Caption appears: "Icons and expansion survive drill-back."
9. Cursor hovers the status icon (proving icons survived), then the nested
   grandchild (proving expansion survived). Caption stays visible for both.
10. Camera releases wide, end.
```

Then ask:

```
Q: "Ready to record, or do you want to adjust anything?"
  1. Record it (Recommended)
  2. Change a caption
  3. Adjust the flow (pacing, hover targets, extra beats)
  4. Different viewport / autoZoom setting
```

If they pick 2 or 3 or 4, loop back to the relevant step and re-confirm with Step B again before moving to Phase 5. Do NOT proceed to `webreel record` until the user says "record it."

**Why this gate matters.** The flow summary catches structural issues cheaply — wrong beats, missing moments, wrong order — before you spend tokens on recording + compositing. Captions were already locked in Phase 3.5, so by the time you hit this phase the only things left to adjust are flow-level (pacing, hover targets, extra beats) or viewport/autoZoom settings. Together, Phase 3.5 + Phase 4.5 cost ~30 seconds of user attention and eliminate the most common "shipped a demo, user asked for changes, re-recorded" cycle.

### Phase 5 — Record & verify

```bash
npx webreel validate
npx webreel record <video-name> --verbose
```

After recording — **always** verify visually:

1. Sample 4 frames across the video:
  ```bash
   ~/.webreel/bin/ffmpeg/ffmpeg -y -v error -i videos/<name>.mp4 \
     -vf "select='eq(n\,180)+eq(n\,600)+eq(n\,900)+eq(n\,1200)'" \
     -vsync vfr /tmp/frame_%02d.png
  ```
2. Read each frame via the `Read` tool (images render inline). Confirm the cursor landed where expected and the critical UI state is visible at each checkpoint.
3. If any step failed (element not found, wrong state captured), open the live page via Chrome DevTools MCP, query the DOM for a stable selector, patch the config, re-record. Never ship a demo that doesn't visually prove the fix.

### Phase 6 — Deliver

Report to the user:

- Absolute path(s) to MP4/GIF + thumbnail PNG
- Duration, file size, viewport per video
- One-line summary per video describing what it shows

Then ask — via a **multi-select `AskUserQuestion`** — which delivery channels to use. The options are fixed: **Prepend to GitHub PR description**, **Post as a comment on the linked Jira ticket**, **Save to the user's Downloads folder**. The user may pick any combination. Execute each selected channel in turn: `scripts/upload-to-pr.sh` for the PR body, `mcp__claude_ai_Atlassian__addCommentToJiraIssue` with the same uploaded URL embedded in the comment body for Jira, and `cp videos/<name>.mp4 ~/Downloads/` (plus the thumbnail `.png` if it exists) for the Downloads copy.

**CRITICAL — never commit video files to a branch.** Upload = host the asset somewhere GitHub can stream it from, then embed a URL in the PR body. It does NOT mean `git add` the video, push it, use the Contents API to commit it, or recreate deleted branches to host assets. Every one of those approaches bloats the repo with multi-megabyte binaries that live in git history forever. This is non-negotiable even if the user authorized "upload to the PR description" — that wording does not override the no-commit rule.

**Use `scripts/upload-to-pr.sh`.** It handles the whole flow correctly: verifies the `gh-image` session token, uploads via `gh image` to GitHub user-attachments (no git commit), extracts the returned URL, emits the right embed form per file type (bare URL for MP4/WebM/MOV — which is what auto-renders as a video player — or markdown image syntax for GIF/PNG/JPG), fetches the existing PR body, prepends the embed while preserving every byte of existing content, and refuses to re-run against a body that already has a user-attachments URL (use `--replace` to override). Modes: default (upload + edit body), `--upload-only` (upload + print URL, skip body edit), `--dry-run` (validate env without uploading).

If `gh-image` itself is unavailable and you genuinely can't install it, fall back in this order (each worse than the last): `gh release create + upload` for a tagged deliverable, a personal `username/pr-demos` repo on your own account. Do **not** use `gh gist` (rejects binaries) and do **not** commit to the PR branch.

**PR body edit hygiene** — when you edit the PR description, edit only the description. Never land a commit on the branch as a side effect. Description edits are reversible with another `gh pr edit`; pushed commits are not.

### Phase 7 — Clean up repo-level video artifacts

After every selected delivery channel has succeeded, delete this video's artifacts from the repo working tree. Webreel outputs are hefty (1–4 MB per MP4 plus raw frames and timelines) and accumulating them across sessions is pure waste — the deliverable is already on GitHub user-attachments, in a Jira comment, or in `~/Downloads/` per the user's choices.

Delete **only the current video's** files; leave other videos in the same folders untouched (they may belong to in-flight work or prior sessions). Paths to remove for `<video-name>`:

```bash
rm -f videos/<video-name>.mp4 videos/<video-name>.png
rm -f .webreel/raw/<video-name>.mp4
rm -f .webreel/timelines/<video-name>.timeline.json .webreel/timelines/<video-name>.timeline.json.bak
```

Do **not** delete `webreel.config.json` — it's the declarative source that lets the user re-record later. Do **not** delete other videos' artifacts. Do **not** delete anything before all chosen delivery channels have confirmed success (an upload that failed mid-flight means the only copy is still on disk).

Mention the cleanup in the final summary so the user knows the repo is clean. If the user declined all upload channels and only wanted "Save to `~/Downloads`", still delete the `videos/` copy after the copy succeeds — the Downloads copy IS the deliverable now, and the repo copy is pure duplication.

## Common pitfalls

- **Skipping Phase 2** — every PR needs a bespoke scope and format; planning takes minutes, re-recording takes much longer.
- **Text collisions** — the same visible text (e.g. "parent") can appear in sidebar, breadcrumb, and details panel. Prefer `aria-label` when in doubt.
- **CSS Module hashes** — always `[class*="fragment"]`, never the literal hashed class.
- **Stale repro instances** — workflow version bumps orphan instances. Visually verify the URL before scripting.
- **Branch drift** — the dev server reflects on-disk code. Confirm the running code has the fix via Chrome DevTools MCP before recording.
- **Over-narrating** — demos are short. Pick 3–5 moments that tell the story; skip assertions that add no visual signal.

## When things go wrong

The cheap first move for any failure is `references/troubleshooting.md` — a symptom → cause → fix lookup. If webreel times out on `waitFor`, if `gh image` prints a URL that 404s, if the thumbnail shows a loading state, if a selector fails, that file has the fix. Add new entries when you hit a symptom that isn't there.

Before recording, run the pre-flight scripts (below) — they catch the most common environment issues (wrong URL, SPA routing, stale token) in under 5 seconds.

## Files

### References (read as needed)
- [references/troubleshooting.md](references/troubleshooting.md) — symptom → cause → fix table; check here first when something breaks
- [references/common-interactions.md](references/common-interactions.md) — recipe book for webreel step patterns (hover-and-click, typing, drag, modals, etc.)
- [references/iteration-economy.md](references/iteration-economy.md) — cheapest-tool-first decision tree; when to re-composite vs re-record
- [references/selector-strategies.md](references/selector-strategies.md) — selector priority, antipatterns, collision detection
- [references/pom-to-webreel.md](references/pom-to-webreel.md) — Playwright POM → webreel step translation table
- [references/research-sources.md](references/research-sources.md) — git / PR / Jira MCP / catalog-API recipes

### Scripts (run directly)
- [scripts/ensure-webreel.sh](scripts/ensure-webreel.sh) — webreel CLI + dependencies availability check + install
- [scripts/preflight-check.sh](scripts/preflight-check.sh) — validate URL, dev server, gh-image token, disk before recording
- [scripts/list-routes.py](scripts/list-routes.py) — enumerate and **resolve** DAP frontend routes into copy-pastable URLs (handles any section's convention: inline `const X = {...}` or external enum)
- [scripts/extend-timeline.py](scripts/extend-timeline.py) — stretch caption HUD dwell to ≥3000 ms before re-compositing
- [scripts/validate-caption-dwell.py](scripts/validate-caption-dwell.py) — check caption dwell budget against word-count rules
- [scripts/upload-to-pr.sh](scripts/upload-to-pr.sh) — end-to-end upload via `gh image` + prepend embed to PR body (preserves existing content, idempotent guard against duplicates)

