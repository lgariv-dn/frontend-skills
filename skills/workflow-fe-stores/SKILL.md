---
name: workflow-fe-stores
description: End-to-end workflow for changing @dap-workspace/workflow-fe-stores—adding state to the right Zustand store, slices, selectors (including computed/reselect), hooks, registry, exports, and consuming store hooks in UI. Use when adding workflow FE client state, new store, new preferences, execution inputs, builder state, or extending workflow-fe-stores; or when wiring useWorkflow*Store / selectors in workflow-fe-builder, workflow-fe-catalog, or apps.
---

# Workflow FE Stores (Zustand) — End-to-End

**Repository scope:** Paths, package names, and `.cursor/rules` references assume the **DAP** monorepo (`@dap-workspace/workflow-fe-stores`, `dap-workspace/libs/workflow/workflow-fe/...`). In other workspaces, map these paths to your layout and keep the same architectural steps.

## Before you start

1. Read **`.cursor/rules/workflow-fe-react-patterns.mdc`** (Zustand Store Conventions) in the DAP repo.
2. Open **`dap-workspace/libs/workflow/workflow-fe/workflow-fe-stores/.ai/IMPLEMENTATION.md`** (how to change, invariants). Use **`workflow-fe-stores/.ai/features/state-management-patterns.md`** for middleware and slice shape detail.
3. Confirm **TanStack Query** is not the right layer: server-fetched workflows/tasks/instances belong in **`@dap-workspace/workflow-fe-api`**, not Zustand.

## Step 1 — Pick the store

| Need | Store folder |
|------|----------------|
| Active workflow editor, canvas, save, validation | `workflow-builder` |
| Catalog list preferences, per-workflow execution inputs | `workflow-catalog` |
| Task list preferences, per-task execution inputs | `workflow-tasks` |
| Instance list preferences / filters | `workflow-instances` |
| Single task configuration panel session | `task-builder` |
| Boolean feature flag | `flags` (`flags.json` + `useFlag`) |

If nothing fits, plan a **new** store (Step 2b). Prefer extending an existing store over a new one when the state is clearly domain-local.

## Step 2a — Add or change state in an existing store

1. **Types:** Update `<store>.types.ts` (state shape, action signatures).
2. **Constants:** Add action labels to `<store>.consts.ts` for new `set()` paths.
3. **Slice:** Implement in `slices/<slice>.slice.ts` (or new slice file + export from `slices/index.ts`). Use Immer `draft` updates only inside `set`. Pass **action label** as third argument to `set`.
4. **Store root:** Spread the slice in `<store>.store.ts`; extend `reset()` / `partialize` / `onRehydrateStorage` if persistence changes.
5. **Selectors:**
   - Base: `selectors/<domain>.selectors.ts` — pure `(state) => ...`, name `select*`.
   - Derived: `selectors/computed.selectors.ts` — `createSelector` from `reselect`, composing base selectors.
6. **Shared (if multi-store):** If catalog, tasks, and instances (or two stores) need the same pure logic, add or extend **`src/lib/stores/shared/`** (`*.utils.ts`, types, consts); keep helpers **pure** (no Zustand hooks). Re-export from `shared/index.ts` and from **`src/index.ts`** only when other packages need the surface. See **Shared store utilities** in `workflow-fe-react-patterns.mdc`.
7. **Barrels:** Export new selectors from `selectors/index.ts` and store from `.../index.ts`.
8. **Action hook:** If components need new actions, extend the relevant `hooks/use-*-store-actions.ts` with `useShallow` (stable object of callbacks). Follow **Store and hook naming** in `workflow-fe-react-patterns.mdc`: store type `*Store`, hook `use*Store`, action hook `use*StoreActions`, accessor `get*StoreActions`, and `*Action` suffixes on mapped methods.
9. **Non-React access:** If services/tests need it, extend `actions/*-store-actions.ts` and export `get*StoreActions` pattern used by that store.
10. **Package API:** Add exports to **`workflow-fe-stores/src/index.ts`** for anything consumed outside the package.
11. **Tests** (paths are under `dap-workspace/libs/workflow/workflow-fe/workflow-fe-stores/src/lib/stores/`):
    - **`<store>/selectors/__tests__/`** — base and computed selectors when behavior is non-trivial.
    - **`shared/__tests__/`** — any new or changed **`shared/*.utils.ts`** helpers.
    - **`<store>/slices/__tests__/`** or store `*.spec.ts` — complex slice or rehydration behavior.
    - **`hooks/__tests__/`** — when verifying action hooks (`useShallow` wiring) or flag hooks; follow existing specs in the package.

## Step 2b — New store (only if required)

1. Create folder `workflow-fe-stores/src/lib/stores/<name>/` matching **workflow-fe-react-patterns** (omit **`persist` / `partialize`** when nothing should be persisted—see **`task-builder`**: devtools + immer only).
2. Register in **`workflow-fe-stores/src/lib/registry/workflow-store-registry.ts`:**
   - **`STORES`:** Add `{ name, init }` only if the store defines **`init()`** for startup. **`task-builder`** is intentionally **not** in `STORES` today; it still participates in **`resetAll`** / **`getSnapshot`** / re-exports. Align with your store’s real API.
   - **`resetAll`:** Invoke the correct method per store (`reset()`, `closeTask()`, …)—mirror existing calls.
   - **`getSnapshot`:** Add a property for the new store.
   - **Re-exports:** Extend the registry’s `export { use...Store }` block when non-React code imports stores from the registry module.
3. Export from **`workflow-fe-stores/src/index.ts`** so consumers use **`@dap-workspace/workflow-fe-stores`**.
4. If using **persist:** unique storage **`name`**, **`partialize`**, **`onRehydrateStorage`** when needed; **`init()`** must stay **idempotent** (module-level guard) if present.

## Step 3 — Wire UI (outside the stores package)

1. **Read state:** `useXxxStore(selectYyy)` — always pass a **selector** exported from `@dap-workspace/workflow-fe-stores`.
2. **Actions:** `useXxxStoreActions()` or domain-specific hook (e.g. `useWorkflowCatalogPreferencesStoreActions`); never rely on an unstable inline object without `useShallow` inside the hook implementation.
3. Ensure the workflow app mounts **`WorkflowStoreProvider`** so **`workflowStoreRegistry.initialize()`** runs on mount (existing workflow apps already do this). Builder subscriptions attach from the same provider when **`enableSubscriptions`** is true (default).

## Step 4 — Verify

```bash
pnpm --filter @dap-workspace/workflow-fe-stores test
```

Run affected app/lib tests or E2E if the change affects user-visible behavior.

## Checklist (quick)

- [ ] Correct store chosen (or new store justified)
- [ ] Types + consts + slice + store `reset` / persist rules
- [ ] Base + computed selectors; exported from package when needed
- [ ] Action hooks use `useShallow`
- [ ] Registry: `resetAll` + `getSnapshot` (+ `STORES` only if the store has `init`) + re-exports; `src/index.ts` updated for new public surface
- [ ] UI uses `useStore(selector)` + action hooks
- [ ] Tests: per-store `selectors/__tests__/`, `shared/__tests__/` if shared utils changed, slices/store/hooks specs if relevant
