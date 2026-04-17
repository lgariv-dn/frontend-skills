# Translating Playwright POMs to webreel

Playwright Page Object Model (POM) classes encode the exact selectors and flows that already verify the feature. Use them as the primary source for webreel configs — they're tested, stable, and reflect reality.

## One-to-one action mapping

| Playwright (POM or spec) | Webreel step |
|--------------------------|--------------|
| `await page.goto(url)` | `"url"` field on the video + `"waitFor"` |
| `await locator.click()` | `{ "action": "click", ... }` |
| `await locator.hover()` | `{ "action": "hover", ... }` or `moveTo` |
| `await locator.fill(text)` | `{ "action": "type", "text": "...", "selector": "..." }` |
| `await page.keyboard.press("Enter")` | `{ "action": "key", "key": "enter" }` |
| `await expect(locator).toBeVisible()` | `{ "action": "wait", "selector": "..." }` |
| `await expect(locator).toContainText("x")` | `{ "action": "wait", "text": "x" }` |
| `await page.waitForURL(re)` | `{ "action": "pause", "ms": 500 }` + next step proves state |
| `await locator.scrollIntoViewIfNeeded()` | `{ "action": "scroll", "selector": "..." }` |
| `await locator.selectOption(value)` | `{ "action": "select", "selector": "...", "value": "..." }` |

## Reading a POM

Look for two code shapes:

1. **Locator declarations** (`readonly foo: Locator`) — stable selectors.
2. **Action methods** (`async clickFoo()`, `async expectBar()`) — intended flow semantics.

Example:

```ts
// pages/instance_viewer_page.ts
this.embeddedWorkflowsSidebar = this.page.locator('#embedded-workflows-sidebar');
// → { "selector": "#embedded-workflows-sidebar" }

async drillDownIntoWorkflow(workflowName: string) {
  const btn = this.embeddedWorkflowsSidebar
    .locator('[class*="embeddedWorkflowItem"]')
    .filter({ hasText: workflowName })
    .getByRole('button', { name: this.t('workflow.embeddedWorkflows.viewDetails') });
  await btn.click();
}
```

Translates to:

```json
{ "action": "click", "selector": "#embedded-workflows-sidebar button[class*=\"itemAction\"]" }
```

Note: Playwright's `.filter({ hasText })` + `.getByRole({ name })` chain has no single CSS equivalent. Flatten by finding a unique terminal selector (here, the `outbound` icon's button class).

## When the POM selector won't work in webreel

Webreel is plain CSS; Playwright has a richer locator engine. When chains don't translate:

1. Open the live page via `mcp__chrome-devtools__navigate_page`.
2. Run `mcp__chrome-devtools__evaluate_script` to query the DOM and find a flat selector:
   ```js
   () => {
     const nodes = document.querySelectorAll('#embedded-workflows-sidebar button');
     return [...nodes].map(b => ({
       aria: b.getAttribute('aria-label'),
       dataPart: b.getAttribute('data-part'),
       cls: b.className.toString(),
       text: b.textContent.trim().slice(0, 30),
     }));
   }
   ```
3. Pick the highest-priority stable selector (aria-label > data-part > `[class*="..."]`).
4. Verify uniqueness with `document.querySelectorAll(selector).length === 1`.

## i18n resolution

POMs often call `this.t('key.path')` for visible text. To resolve, `rg` the locale JSON:

```bash
rg '"deepestKey":' dap-workspace/libs/workflow/workflow-fe/workflow-fe-i18n/src/locales/en/workflow.json
```

The resolved string is what webreel's `text` selector will match. If the key doesn't exist in the JSON, `t()` returns the key itself — aria-labels emitted from missing keys are brittle. Skip them and use a CSS selector.

## Mapping E2E specs to a demo narrative

An E2E spec typically asserts 5–15 states. A demo shouldn't show them all. Pick 3–5 demo-critical moments:

- Entry state (what the user sees first)
- The trigger action (button click, navigation)
- The change (the state that regressed/broke)
- The restored/added state (the fix in action)
- A final reinforcement (second verification, hover-to-reveal)

Drop pure-assertion waits that don't produce new visual state.

## Example: E2E spec → demo config

Spec excerpt:

```ts
test('drill-back preserves status badges', async ({ instanceViewerPage }) => {
  await instanceViewerPage.gotoInstance(instanceId);        // → url + waitFor
  await instanceViewerPage.waitForEmbeddedSidebar();         // → wait
  await instanceViewerPage.drillDownIntoWorkflow('child');   // → click drill-in button
  await instanceViewerPage.expectBreadcrumbsVisible();       // → wait for breadcrumb
  await instanceViewerPage.clickBreadcrumbRoot();            // → click Navigate to root
  await instanceViewerPage.waitForEmbeddedSidebar();         // → wait
  await expect(sidebar.locator('[class*="completed"]')).toHaveCount(6); // skip (non-visual)
});
```

Demo config excerpt:

```json
{
  "url": "http://localhost:4200/workflow/instance-viewer?instanceId=...",
  "waitFor": "#embedded-workflows-sidebar",
  "steps": [
    { "action": "wait", "text": "Task overview" },
    { "action": "pause", "ms": 900 },
    { "action": "moveTo", "text": "child", "within": "#embedded-workflows-sidebar" },
    { "action": "click", "selector": "#embedded-workflows-sidebar button[class*=\"itemAction\"]" },
    { "action": "wait", "selector": "button[aria-label=\"Navigate to root\"]" },
    { "action": "pause", "ms": 1100 },
    { "action": "click", "selector": "button[aria-label=\"Navigate to root\"]" },
    { "action": "wait", "text": "Task overview" },
    { "action": "pause", "ms": 1200 }
  ]
}
```

The final long pause lets the reviewer visually confirm the status badges are still present after drill-back — the whole point of the fix.
