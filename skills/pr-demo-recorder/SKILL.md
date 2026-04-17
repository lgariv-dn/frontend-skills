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

1. **webreel CLI** — installed globally via `npm` or project-local via `npx`. If missing, prompts to run `npm install -g webreel`.
2. **Companion webreel Claude skill** at `~/.claude/skills/webreel/`. If missing, offers to fetch it from `vercel-labs/webreel`.
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
7. **Delivery** — ALWAYS ask as a **multi-select `AskUserQuestion`** (set `multiSelect: true`) with exactly these three options — the user may pick any combination:
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

**Captions only render on `key` action steps — and last only 800 ms unless you extend them.** Despite what the webreel docs suggest, in webreel 0.1.4 the HUD caption is drawn only when `pressKey` fires, and `pressKey` calls `showHud` → sleep 800 ms → `hideHud` — hardcoded. `label` on `click`, `moveTo`, `pause` etc. is **silently ignored at composite time**. A `delay` on the `key` step doesn't extend HUD visibility either — it only delays the next step. So the native output of a `key F13 + label "foo"` step gives you a caption visible for ~0.8 s, which is unreadable.

**Use the two-pass workflow: record, then extend-and-composite.**

1. **Record pass** — include a `{ action: "key", key: "F13", label: "..." }` step at each narrative beat. F13 is the chosen benign key (modifier-only keys like `Shift` are rejected with "pressKey requires a non-modifier key"). The `key` step anchors a caption entry in the timeline at a precise timestamp. Keep the immediately-following action steps (`click`, `moveTo`, etc.) short with minimal `delay`s — the long visible window comes from the timeline pass, not from `pause`s between steps. Example beat:
   ```jsonc
   { "action": "key",   "key": "F13", "label": "Click Start \u2192 see the workflow input" },
   { "action": "click", "selector": ".react-flow__node[data-id=\"start-state\"]", "delay": 800 },
   { "action": "wait",  "text": "Input", "within": "#details", "timeout": 10000 },
   { "action": "pause", "ms": 600 }
   ```

2. **Timeline-extend pass** — webreel writes a timeline JSON to `.webreel/timelines/<video-name>.timeline.json` with a `frames` array, one entry per recorded frame. Each frame has an optional `hud: { labels: [...] }`. Native recording populates ~48 consecutive frames per caption (~800 ms at 60 fps). Walk the timeline, detect each run of contiguous HUD frames, and **copy the label across subsequent frames up to the target duration, or until the next HUD run starts, whichever comes first**. Default target: **2500 ms (150 frames at 60 fps)** — verified readable for 6–10 word captions without bloating runtime. Bump to 3000–4500 ms only for verbose labels (>12 words). This stretches the caption's visibility without re-encoding or re-recording. Implementation: a Python script that backs up the timeline to `.json.bak` on first run, always reads from the backup for idempotency, and writes the extended timeline back.

3. **Composite pass** — `npx webreel composite <video-name>`. Re-runs only the overlay compositor using the modified timeline + the raw frames (already stored under `.webreel/raw/`). Takes ~5–10 s per video instead of 30–60 s for a full re-record. This is the step that actually produces the user-visible MP4 with the extended captions burned in.

**Why this is the right pattern:**
- Captions appear during the cursor movement and click — exactly what the user originally asked for — because the timeline extension overlaps the caption with the post-`key` action steps.
- 2500 ms is the sweet spot: long enough to read, short enough to keep the video moving.
- No ffmpeg post-processing, no repeated recording, no reliance on docs claims that don't hold in 0.1.4.

**Prove the value, don't just click.** After a beat's click reveals content, follow with **short `moveTo` hovers (700–1000 ms each) over the specific values that demonstrate the fix**. The click tells "what I did"; the hovers show "what this produced." Keep hover dwell short — once the cursor lands and the viewer registers the value for ~1 s, move on. Long hover dwell adds no signal.

### Caption writing — phrase every label on purpose

Captions are the spine of the demo. Vague labels like "Task input we passed in" waste screen time. Every caption must satisfy these rules:

1. **Length: ≤9 words, one line.** Any longer and it wraps at 1600px wide or can't be read in the 2500 ms window. A 6-word caption is a great target; 9 words is the hard ceiling. If your draft is longer, cut qualifiers before shortening vocabulary.
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

### Timing guarantee: each caption needs ≥2500 ms of post-caption dwell

Because the timeline-extend pass caps each caption at the NEXT caption's start time, a caption whose `key` step is followed by <2500 ms of steps (cursor travel + clicks + pauses) before the next `key` step gets truncated. Engineer the config so:

- Action captions (2–4 words): the following `click` + `wait` + `pause` total ≥1500 ms. Action captions are short — they don't need the full 2500 ms.
- Reveal captions (5–9 words): the following `moveTo`s / `pause`s total ≥2500 ms. If you've got 3 value hovers at ~700 ms each, that's 2100 ms + a 500 ms trailing pause = 2600 ms ✓.

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
- [scripts/extend-timeline.py](scripts/extend-timeline.py) — stretch caption HUD dwell to ≥2500 ms before re-compositing
- [scripts/validate-caption-dwell.py](scripts/validate-caption-dwell.py) — check caption dwell budget against word-count rules
- [scripts/upload-to-pr.sh](scripts/upload-to-pr.sh) — end-to-end upload via `gh image` + prepend embed to PR body (preserves existing content, idempotent guard against duplicates)

