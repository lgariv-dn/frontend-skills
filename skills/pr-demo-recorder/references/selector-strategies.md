# Selector strategies for webreel

Webreel's interactive steps (`click`, `wait`, `moveTo`, `hover`, `type`, `select`) accept either `text` (visible text) or `selector` (CSS). Both can be scoped with `within` (a CSS selector of a parent element). Pick the most stable strategy for each target.

## Priority order

1. **Unique visible text** — `text: "Branch 1", within: "#embedded-workflows-sidebar"`
   Cleanest for dev-readability. Safe when the text is unique within the scope.

2. **Accessibility anchors** — `selector: "button[aria-label=\"Navigate to root\"]"`
   Stable across i18n rephrasings and visual redesigns. Use for icon-only buttons, navigation controls, any element where visible text is absent or duplicated.

3. **Explicit test hooks** — `selector: "[data-testid=\"save-btn\"]"`
   If developers placed them, use them. They're a documented contract.

4. **Library primitives** — `selector: "[data-part=\"branch-trigger\"]"`
   Ark UI, Radix UI, Headless UI all emit `data-part` / `data-scope` / `data-state` attributes. These survive across versions better than class names.

5. **CSS Module fragments** — `selector: "[class*=\"itemAction\"]"`
   CSS Modules hash class names at build time (e.g. `hz88NG_itemAction`). The pre-hash fragment is stable; use `[class*="..."]` (attribute contains) to match it.

6. **DOM IDs** — `selector: "#details"`
   Use when developers explicitly set an ID. Rare in modern React codebases, but reliable when present.

## Antipatterns

- `selector: ".hz88NG_itemAction"` — matching a hashed class literally. Breaks on every rebuild that regenerates the hash. Use `[class*="itemAction"]` instead.
- `text: "Save"` at page scope when "Save" appears in three dialogs. Use `within` to scope, or pick an `aria-label`.
- `selector: ".MuiButton-root"` — library-internal classes; break on minor MUI version bumps. Use role/aria or `data-*` attributes.
- `:has-text("...")` — Playwright-specific pseudo-class; webreel uses plain CSS. Flatten the selector instead.
- `text: "parent"` when "parent" appears in the sidebar (workflow name), breadcrumb (root label), and details panel header. Use `aria-label="Navigate to root"` for the breadcrumb specifically.

## Scoping with `within`

`within` only accepts CSS selectors, not text. To narrow a text match to a region:

```json
{ "action": "click", "text": "Submit", "within": "[role=dialog]" }
```

If the scope itself needs text-matching, two-step it: `moveTo` the parent by text, then `click` the target by selector.

## Collision detection

Before committing to a `text:` match, query the live DOM via `mcp__chrome-devtools__evaluate_script`:

```js
() => {
  const matches = [...document.querySelectorAll('*')].filter(el => {
    const direct = [...el.childNodes].some(n => n.nodeType === 3 && n.textContent.trim() === 'Branch 1');
    return direct;
  });
  return matches.length;
}
```

If the count > 1, fall back to a `selector` strategy or add a `within`.

## DAP-specific notes

- Workflow canvas nodes: `.react-flow__node[data-id="..."]` with a text filter. React Flow keeps the `data-id` stable.
- Workflow sidebar items: `#embedded-workflows-sidebar` scope + `[role="treeitem"]` or `[data-part="branch-control"]`.
- Material icons render their icon name as text content (e.g. `<span>outbound</span>`). This is a free disambiguator — you can match the icon's name directly when the icon is unique in the scope.
- CSS Module fragments that appear in the DAP codebase: `[class*="nodeCompleted"]`, `[class*="embeddedWorkflowItem"]`, `[class*="itemAction"]`, `[class*="ioRowValue"]`, `[class*="workflowSectionRow"]`, `[class*="statusLegend"]`.
