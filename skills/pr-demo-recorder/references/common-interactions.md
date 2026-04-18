# Common interactions — recipe book

Each recipe shows a typical UI interaction pattern as a webreel-config snippet, with known gotchas and links to troubleshooting entries.

**How to grow this file:** when a future demo needs an interaction type that isn't here, add a new `## <Interaction>` block. Each recipe needs: purpose, canonical snippet, gotchas. Entries marked ✅ are from real sessions; ⚠️ are extrapolated from docs/codebase inspection.

---

## Hover-and-click (reveal-gated button) ✅

Many DAP components gate action buttons on CSS `:hover`. The DsTree row's "outbound" drill-down button only renders on mouse-over. `moveTo` alone is unreliable; use `hover` right before `click`.

```json
{ "action": "hover", "selector": "[data-value='<tree-item-id>']" },
{ "action": "click", "selector": "[data-value='<tree-item-id>'] button" }
```

**Gotchas:**
- If the button is still invisible after `hover`, the reveal is driven by something other than CSS `:hover` (e.g. `mouseenter` handler). Try adding a tiny `{ "action": "pause", "ms": 200 }` between `hover` and `click`.
- Playwright-style strict mode: scope the button selector with the parent's `data-value` so you hit the right row's button, not the first matching button on the page.

---

## Typing into an input field ⚠️

```json
{ "action": "click", "selector": "input[placeholder='Search']" },
{ "action": "type", "text": "parent", "charDelay": 40 }
```

**Gotchas:**
- React controlled inputs update via synthetic events. Raw keyboard-level typing usually works, but for stubborn cases you may need a click first to ensure focus.
- `charDelay: 40` feels natural; `20` feels fast; `80` feels slow-deliberate.
- For search-as-you-type UIs, add `{ "action": "pause", "ms": 500 }` after typing so the filter result renders before the next step.

---

## Native `<select>` dropdown ⚠️

```json
{ "action": "select", "selector": "#country-select", "value": "us" }
```

**Gotchas:**
- Webreel's `select` action only works on real `<select>` elements. Custom Ark/Radix selects are clickable, not `<select>` — use the custom-dropdown recipe below.

---

## Custom dropdown (Ark UI / Radix / headless) ⚠️

Ark Select and similar headless libraries render the open options into a **portal** attached to `document.body`, not to the trigger's parent. Selectors scoped with `within` to the trigger's parent won't find the options.

```json
{ "action": "click", "selector": "[data-part='trigger']", "delay": 400 },
{ "action": "click", "text": "United States" },
{ "action": "pause", "ms": 300 }
```

**Gotchas:**
- The `text` match on the second click reaches the portaled option because it's at the document level.
- If multiple elements on the page contain the same text, tighten with `selector: "[data-part='item'][data-value='us']"` or `within: "[role='listbox']"`.

---

## Drag and drop ⚠️

```json
{
  "action": "drag",
  "from": { "selector": "[data-id='task-card-1']" },
  "to":   { "selector": "[data-id='column-done']" },
  "delay": 600
}
```

**Gotchas:**
- HTML5 drag-and-drop (draggable="true" + ondragstart) works; CSS-transform-based drags (e.g. react-dnd with mouse events only) may not trigger reliably. If the drop target doesn't register, try a longer `delay` or insert a midway `moveTo`.
- For React Flow node rearrangement: drag the node *handle*, not the node body.

---

## Keyboard shortcut ⚠️

```json
{ "action": "key", "key": "cmd+s", "label": "Save with cmd+S" }
```

**Gotchas:**
- Use `cmd+` on mac recordings, `ctrl+` on linux/CI recordings. No cross-platform auto-mapping.
- Any non-modifier key works. For caption beats specifically, `F13` is preferred because it's guaranteed to have no app-level handler.

---

## Modal open + interact + dismiss ⚠️

```json
{ "action": "click", "text": "Delete" },
{ "action": "wait", "selector": "[role='dialog']", "timeout": 5000 },
{ "action": "click", "text": "Confirm", "within": "[role='dialog']" },
{ "action": "wait", "selector": "[role='dialog']", "timeout": 5000, "invert": true }
```

**Gotchas:**
- webreel 0.1.4 doesn't support `invert: true` — workaround is a `pause` long enough for the modal exit animation (~300–500 ms), then proceed.
- For focus-trap modals, `Escape` always works: `{ "action": "key", "key": "Escape" }`.
- Portaled dialog: the `role="dialog"` element is at `document.body`, not inside the trigger's parent. Don't scope with `within` a parent.

---

## Scroll the page or a specific component ✅

Reference: the [`examples/page-scrolling`](https://github.com/lgariv-dn/webreel/tree/main/examples/page-scrolling) config demonstrates every pattern below — a blog-post layout that scrolls the page, scrolls back up, and scrolls a sidebar container internally. An `examples/autozoom` config in the same repo demonstrates the cinematic-zoom behavior on a form (name, email, role dropdown, save).

### Full-page (window) scroll — no `selector`

```json
{ "action": "scroll", "y": 400 }
```

- `y: 400` → scroll **down** 400 pixels (relative to current position, not absolute).
- Defaults to the window scroll. Omit `selector` entirely.
- Chain multiple scrolls for bigger jumps: two consecutive `y: 400` steps scroll 800 px total, with the `defaultDelay` between them acting as the pacing gap.

### Scroll back up — negative `y`

```json
{ "action": "scroll", "y": -300 }
```

- Negative `y` scrolls **up**. Works for window scroll and container scroll alike.
- Handy at the end of a long flow to reset the page before a reveal, or between demo segments when you want to re-show the header.

### Scroll a specific component — pass `selector`

```json
{ "action": "scroll", "y": 200, "selector": ".sidebar", "delay": 1000 }
```

- When the container has its own `overflow-y: auto` (drawers, details panels, sidebars, virtualized lists), window scroll does **nothing visible** — you must target the scrollable element directly.
- `delay` after the scroll gives the viewer time to register the new content before the next action fires.
- Selector priority is the same as clicks: prefer `#id`, then `aria-label`, then `[data-testid]`, then `[class*="fragment"]` for CSS-Modules. Never hash-literal class names.

### Combining scroll with `wait` for async content

```json
{ "action": "scroll", "y": 800, "selector": "#details" },
{ "action": "wait",   "text": "Output",   "within": "#details", "timeout": 5000 },
{ "action": "pause",  "ms": 600 }
```

- Infinite-scroll lists, lazy-loaded rows, and details panels that fetch on scroll need an explicit `wait` for the new content — don't assume it appears synchronously.
- The `within: "#details"` scopes the wait to the panel so matches elsewhere on the page don't trick you into proceeding early.

### Identifying the right scroll container

If `scroll` with the obvious parent (e.g. `#details`) produces no visible movement across frame samples, the overflow is on an inner wrapper. Common culprits:

- `[class*="panelContent"]` / `[class*="bodyScroll"]` — React panel libraries often put `overflow-y` on an inner div.
- Ark UI / Radix / Dialog primitives usually expose `[data-part="content"]` as the scroll region.
- DevTools shortcut: select the target element, then walk up the DOM tree with Computed Styles visible, looking for the nearest ancestor with `overflow-y: auto` or `overflow-y: scroll`. That's your selector.

### Gotchas

- **Relative, not absolute.** `scroll` always moves **from the current position**. There's no "scroll to top" / "scroll to y=0" — use a large negative `y` (e.g. `-10000`) to reset a container to the top.
- **Window vs. container.** Omit `selector` for the window; include it for any container with its own scroll. Mixing them up produces silent no-ops.
- **Pacing.** Fast consecutive scrolls (<400 ms apart) look jumpy. Put a `pause` of 300–600 ms between scroll steps in the same direction so the viewer can track motion.
- **Below-the-fold reveals.** If a reveal caption needs a section that's off-screen, script the `scroll` step BEFORE the `key` caption — captions timed to an off-screen element confuse the viewer ("the caption mentions status icons, I can't see any icons").
- **Pair with `zoom` carefully.** If the video uses `zoom: 0.75` or similar, the CSS-transformed page scrolls at the zoomed pixel scale, not the logical one. Test scroll distances after zoom is applied.

---

## Multi-page flow (navigate via router click) ✅

DAP's dashboard-fe is an SPA. Internal links trigger client-side routing; hard `navigate` actions to deep paths return 404 (see `troubleshooting.md` → "webreel times out on waitFor").

```json
{ "action": "click", "text": "Workflow automation" },
{ "action": "wait",  "text": "Catalog", "timeout": 10000 }
```

**Gotchas:**
- Prefer clicking visible navigation text over `action: "navigate"` — client-side routing works, hard nav doesn't.
- If you must hard-nav, only the routes returned by `scripts/list-routes.py` will serve an `index.html`.

---

## File upload ⚠️

Webreel 0.1.4 has **no native file-upload action**. If you need to demo a file upload:

**Option A — mock the file selection via DOM:** some apps expose a file-picker that you can bypass by directly setting the `<input type="file">` .files. This requires JavaScript injection, which webreel doesn't support directly. Skip this demo step and narrate around it.

**Option B — pre-upload the file before recording**, so the demo starts post-upload. Rewrite the flow to skip the upload step.

**Option C — switch to Playwright** for this specific demo; webreel isn't the right tool.

---

## Waiting for animation to finish ⚠️

CSS transitions/animations can leave elements mid-move when webreel captures the next frame. The visible glitch isn't dramatic but shows up on slow fades/slides.

```json
{ "action": "click", "selector": ".menu-trigger" },
{ "action": "pause", "ms": 500 }   // let the fade-in settle
```

**Gotchas:**
- Rule of thumb: 300–500 ms covers most DS transitions. Longer if the component uses spring physics or staggered children.
- For long dropdowns/lists that fade-in row-by-row, `pause` until the last row is visible (or use `wait` on a last-row selector).

---

## Handling a cookie banner / first-visit overlay ⚠️

webreel's fresh browser has no prior cookies — banners reappear every session. Factor the dismissal into a shared steps file:

```json
// steps/dismiss-banner.json
{
  "steps": [
    { "action": "wait",  "selector": ".cookie-banner", "timeout": 5000 },
    { "action": "click", "selector": ".cookie-banner button[aria-label='Accept']", "delay": 300 }
  ]
}
```

Then in the main config:

```json
{
  "include": ["./steps/dismiss-banner.json"],
  "videos": { ... }
}
```

**Gotchas:**
- If the banner doesn't appear (e.g. cookies already set for other reasons), the `wait` times out and the whole video fails. Make the wait short (≤5 s) so a missing banner doesn't cascade.

---

## Adding a new recipe

Template:

```markdown
## <Interaction name> ✅|⚠️

<1–2 sentence description of the pattern and when to use it.>

[canonical snippet]

**Gotchas:**
- <Known failure mode and workaround>
- <Another known failure mode and workaround>
```

Mark ✅ once verified in a real recording; ⚠️ for extrapolated/untested recipes.
