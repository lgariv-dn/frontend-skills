# Troubleshooting — symptom → cause → fix

Grep by symptom. Each entry is self-contained.

**All entries in this file are verified from real sessions.** Speculative "this might cause it" entries are deliberately excluded — an entry here is a claim about a known failure mode with a known fix, not a hypothesis. If a future session hits a symptom that isn't in this file, investigate from first principles and add a new entry only after confirming the cause with direct evidence.

**How to grow this file:** when you verify a new symptom, add a `## Symptom: …` block with the three-part shape: Cause → Check → Fix. One symptom per block, one block per symptom. Do not reorganize existing entries when you add new ones. Do not add entries you haven't observed yourself.

---

## Symptom: webreel times out on `waitFor`

### Cause A — URL doesn't render on hard navigation (SPA 404)

DAP's dashboard-fe uses TanStack Router + Vite. The Vite dev server does **not** configure `historyApiFallback` for deep paths. Only `/` and explicitly-registered routes serve `index.html`; everything else returns a bare "Not Found". Webreel does a hard `page.goto()` and lands on the 404 page, where your `waitFor` text never appears.

**Check:**
```bash
curl -s "$URL" | head -c 200
# If you see "Not Found" (no HTML), the route doesn't exist as a server-served path
```

**Fix:** find the URL that *does* hard-navigate (almost always the query-param form):
- Run `scripts/list-routes.py <Section>` to enumerate resolved URLs (outputs copy-pastable values you can drop straight into a webreel config).
- Look for a query-param variant (`?instanceId=…`, `?projectId=…`) — those hard-navigate fine because the path itself is a registered route.
- Example gotcha from AR-58199: `/workflow-management/instances/<id>` does not exist; the real route is `/workflow/instance-viewer?instanceId=<id>`.

### Cause B — `waitFor` text appears before content loads

`waitFor` can resolve on chrome (sidebar header, page title) while the actual data is still loading. The recording starts, the first caption fires, and the thumbnail at frame 0 shows a loading state.

**Check:** open `videos/<name>.png` (the thumbnail). If it shows a loading spinner, skeleton, or empty state, this is it.

**Fix:** use a content-level selector for `waitFor`, not a chrome-level one:
- Bad: `"waitFor": "Task overview"` (sidebar header renders before data)
- Good: `"waitFor": "[data-value='branch1']"` (specific tree item only renders once data loaded)
- Good: `"waitFor": "#embedded-workflows-sidebar [role='treeitem']"` (first tree row)

### Cause C — `waitFor` is an object, not a string

Docs say "selector or text". It's a **string**. Passing `{ "text": "…", "timeout": 15000 }` makes webreel's dry-run print `waitFor: [object Object]`. The custom timeout is silently ignored (falls back to 30 s default).

**Fix:** `"waitFor": "Task overview"` or `"waitFor": ".my-selector"`. Bare string only.

---

## Symptom: I don't know the URL for the target screen

The route config lives in two files and isn't obvious from the app UI.

**Fix:** use `scripts/list-routes.py <Section>`. It:
1. Extracts every `path:` reference from the section's `*.tsx` route config
2. Resolves constant references (`SECTION_PATHS.X`) by finding the definition block anywhere in apps/ or libs/ — works whether constants are inline in `Routes.tsx` (Inventory, AiOps) or in an external enum file (Workflow)
3. Substitutes template literals like `` `${BASE_PATH}/builder` `` with their resolved values
4. Prints copy-pastable final URLs (e.g. `http://localhost:4200/workflow/instance-viewer`)

For query-param routes (`?instanceId=...`), the param name isn't in the router config. The script surfaces `useSearch` / `useSearchParams` hits to point you at the component where the params are declared. As a last resort, navigate via the UI once and copy the URL from the address bar.

---

## Symptom: Thumbnail shows loading state / empty sidebar

See **"webreel times out on `waitFor`" → Cause B** above. `waitFor` resolved on chrome (header/title), not content.

---

## Symptom: Caption appears too briefly to read

webreel 0.1.4's `pressKey` implementation calls `showHud` → sleep 800 ms → `hideHud`. A `delay` on the `key` step doesn't extend HUD visibility. A `label` on `click` / `moveTo` / `pause` is silently ignored at composite time.

**Fix:** two-pass workflow (documented in SKILL.md "Phase 4"):
1. Record normally with `{ "action": "key", "key": "F13", "label": "…" }` beats.
2. Run `scripts/extend-timeline.py` to stretch each HUD run to 2500 ms.
3. Re-composite (not re-record): `npx webreel composite <name>`.

---

## Symptom: Caption got truncated (cut off by next caption)

`extend-timeline.py` caps each caption's extension at the start of the next HUD run. If your action steps between two `key`s total less than the target dwell (2500 ms for reveal, 1500 ms for action), the first caption gets truncated.

**Check:** run `scripts/validate-caption-dwell.py <config>` before recording.

**Fix:** add a trailing `{ "action": "pause", "ms": 600 }` or bump hover delays. Keep each reveal-caption window ≥ 2500 ms, each action-caption window ≥ 1500 ms.

---

## Symptom: `moveTo` doesn't reveal hover-gated UI

`moveTo` moves the cursor. DsTree items gate their action buttons (like the drill-down `outbound` button) behind CSS `:hover` / `mouseenter`. The `hover` action fires these reliably; `moveTo` may not trigger the same CSS/JS handlers in all cases.

**Fix:** when you need a hover-revealed element, use `hover` right before `click`:
```json
{ "action": "hover", "selector": "[data-value='…']" },
{ "action": "click", "selector": "[data-value='…'] button" }
```

---

## Symptom: Recording crashes with `TypeError: Cannot read properties of null (reading 'get')`

Inside a timeline-transform script, `frame.hud` is `null` (not `{}`) for frames with no caption. Code that assumes it's always a dict throws.

**Fix:**
```python
hud = frame.get('hud') or {}
# or
if frame and frame.get('hud') and frame['hud'].get('labels'):
    ...
```
The reference `scripts/extend-timeline.py` handles this correctly — copy its `has_hud()` helper if you're writing a new timeline transform.

---

## Adding a new entry

Copy this template:

```markdown
## Symptom: [one-line description of what the user sees]

[Explanation of the root cause, 1–3 sentences — what mechanism actually produces this symptom.]

**Check:** [one-liner command or signal that confirms this cause — something the reader can run to eliminate ambiguity.]

**Fix:** [exact steps or config change that you have verified works.]
```

**Hard rule:** do not add entries for failure modes you haven't observed yourself with direct evidence (a specific error message, a reproducible misbehaviour, a failed recording). Speculative entries — "this might happen if…" — are worse than no entry at all, because they launder guesses as authoritative guidance and waste downstream time on wrong-cause diagnoses. If you want to record a hypothesis, put it in a PR description or Jira comment, not in this file.
