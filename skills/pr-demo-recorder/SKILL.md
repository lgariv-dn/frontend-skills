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
7. **Delivery** — attach to PR description, Jira comment, Slack post, or leave on disk?

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
3. **Action captions stay the same across styles.** Regardless of PR type, action captions are 2–4 word imperatives: "Click Start", "Open the Completed tab", "Drag Branch 2". They anchor the viewer to what the cursor is about to do. The STYLE distinction lives in the **reveal captions** — the ones that announce what changed.

#### Bug-fix example (AR-55120 pattern) — use this for bug-fix PRs

```
Action:  "Click Start"                                              (2w)
Reveal:  "Before: 'No input data' → now: full workflow input."      (8w)
Action:  "Click Finish"                                             (2w)
Reveal:  "Before: 'No output data' → now: workflow output."         (7w)
```

The structure is **`Before: <literal UI string> → now: <new UI state>.`** Arrow + colon + quotes. Not negotiable.

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

**Below-the-fold sanity check** — after a config is written and before the first record run, think: *does every target element fit in the viewport when its parent panel is at its natural size?* Details panels and drawers often have internal `overflow-y: auto` that hides later sections behind scroll. For any step that relies on text or a node further down in a scrollable container, include an explicit scroll step:

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

Then ask which delivery channel: PR description attachment, Jira comment, Slack post, or disk only. Delegate the actual upload to existing commands (`/yeet`, `/pr-desc`, or manual `gh pr edit` / Jira MCP).

**CRITICAL — never commit video files to a branch.** Do NOT `git add` videos, do NOT push them, do NOT use the GitHub Contents API to upload them to a branch, and do NOT recreate deleted branches just to host assets. Every one of those approaches bloats the repo with multi-megabyte binaries that live forever in git history. This is non-negotiable even if the user earlier authorized "upload to the PR description" — "upload" means host the asset somewhere GitHub can stream it from, then embed a URL in the PR body. It does NOT mean "commit the video." Ever.

**Correct upload path — use the `gh-image` extension.** The community extension [drogers0/gh-image](https://github.com/drogers0/gh-image) extracts the browser's GitHub session cookie and hits the same `user-attachments` upload endpoint the web UI uses. Result: genuine `github.com/user-attachments/assets/<uuid>` URLs, identical to drag-drop — including the security property that the asset inherits the repo's visibility (private repo → private asset). Works for videos/MP4, not just images.

```bash
# One-time install
gh extension install drogers0/gh-image

# Upload (prints a markdown reference; the URL inside is what you embed)
gh image --repo <owner>/<repo> videos/foo.mp4
# => ![foo.mp4](https://github.com/user-attachments/assets/<uuid>)
```

Take the URL and embed it in the PR body. For videos on GitHub, a bare URL on its own line auto-renders as a playable `<video>` — no `<video>` tag or `<img>` wrapper needed:

```
Here's the demo:

https://github.com/user-attachments/assets/<uuid>
```

Note: the URL will return 404 on raw `curl` — these URLs are session-gated. They resolve correctly when rendered by github.com's authenticated pipeline. Don't verify via curl — view the PR in a browser to confirm rendering.

**Fallbacks if `gh-image` is unavailable (keep in mind, all are worse):**

- **GitHub Release asset** — `gh release create + upload`. Permanent public URL. Creates a release on the Releases page (draft releases are hidden from the public list but still discoverable by maintainers). Use only when a release makes sense for the PR's context (e.g., tagged deliverable).
- **Personal assets repo** — your own `username/pr-demos`-style repo on your account. Still a git commit, but on *your* account, not a shared one. Prefer release-asset over branch-commit even there.
- **`gh gist` is NOT an option** — `gh gist create` rejects binary files with "binary file not supported". Text-only.

Under no circumstances commit the asset to the PR's branch or the main repo.

**What to do when you hit a blocker** — if the Contents API returns `409 Repository rule violations found ... Commits must have verified signatures`, that is a **signal to stop, not a signal to sign-and-commit**. It means the repo is specifically configured to reject programmatic file uploads to branches. Back off to a non-branch hosting path (gist, release, user drag-drop) and report the constraint to the user. Never work around signed-commit rules by pushing signed commits that include demo assets.

**PR body edit hygiene** — when you *do* edit a PR description, edit only the description. Never land a commit on the branch "to host the asset" or "to update the commit that created the asset" as a side effect. Description edits are reversible with one more `gh pr edit`; pushed commits are not.

## Common pitfalls

- **Skipping Phase 2** — every PR needs a bespoke scope and format; planning takes minutes, re-recording takes much longer.
- **Text collisions** — the same visible text (e.g. "parent") can appear in sidebar, breadcrumb, and details panel. Prefer `aria-label` when in doubt.
- **CSS Module hashes** — always `[class*="fragment"]`, never the literal hashed class.
- **Stale repro instances** — workflow version bumps orphan instances. Visually verify the URL before scripting.
- **Branch drift** — the dev server reflects on-disk code. Confirm the running code has the fix via Chrome DevTools MCP before recording.
- **Over-narrating** — demos are short. Pick 3–5 moments that tell the story; skip assertions that add no visual signal.

## Files

- [references/selector-strategies.md](references/selector-strategies.md) — selector priority, antipatterns, collision detection
- [references/pom-to-webreel.md](references/pom-to-webreel.md) — Playwright POM → webreel step translation table
- [references/research-sources.md](references/research-sources.md) — git / PR / Jira MCP / catalog-API recipes
- [scripts/ensure-webreel.sh](scripts/ensure-webreel.sh) — CLI availability check + optional global install

