# Frontend Skills

This repository contains reusable "skills" that can be loaded into AI agents to guide how they write, review, and refactor frontend code.

## Installation

From the root of this repo, you can install the skills into your agent environment.


```bash
npx skills add lgariv-dn/frontend-skills
```

## Available Skills

### `react-best-practices`

**Description:** React performance optimization guidelines adapted from `vercel-labs/agent-skills` (last updated Sunday, 25th of January 2026) repo - without all of their extra next.js optimization and focused on react 19 best practices. This skill should be automatically used when writing, reviewing, or refactoring React code to ensure optimal performance patterns.

It provides a comprehensive set of **30 rules across 7 categories**, prioritized by impact:

1. **Eliminating Waterfalls (CRITICAL)** — Avoiding sequential async waterfalls, using `Promise.all` for independent work, and structuring components with Suspense boundaries.
2. **Bundle Size Optimization (CRITICAL)** — Avoiding barrel imports, loading large modules conditionally, and preloading based on user intent.
3. **Client-Side Patterns (MEDIUM-HIGH)** — Safer, more efficient patterns for things like `localStorage` and scroll/touch event listeners.
4. **Re-render Optimization (MEDIUM)** — Deferring state reads, narrowing effect dependencies, using functional `setState`, lazy state initialization, and transitions for non-urgent updates.
5. **Rendering Performance (MEDIUM)** — Techniques like animating wrapper elements, `content-visibility` for long lists, SVG size optimizations, and safer conditional rendering.
6. **JavaScript Performance (LOW-MEDIUM)** — Micro-optimizations in hot paths such as batching DOM changes, using Maps/Sets, caching expensive computations, and avoiding unnecessary sorts.
7. **Advanced Patterns (LOW)** — Patterns like storing event handlers in refs to keep subscriptions stable.

Each rule has its own markdown file in `skills/react-best-practices/rules/` with:
- A short explanation of why the rule matters
- An incorrect example and a corrected version
- Additional notes and references

Note that some of these skills rely on the usage of a minimum react 19.2.x version and react compiler enabled.

### `workflow-local-dev`

**Description:** Support local workflow platform development in the DAP workspace across frontend, backend, and infra teams. Provides access to Kubernetes (Kind), Tilt service management, database queries, and troubleshooting. Use when building UI or API features, adjusting infra configurations, checking logs, running tests, or debugging issues against locally deployed workflow engine components.

It provides:

- **Quick Reference Commands** — Common kubectl, Tilt, and test commands for daily development
- **Utility Scripts** — Ready-to-use scripts for checking pod status, restarting services, tailing logs, and querying the database
- **Development Workflow** — Step-by-step guidance for the code-build-test cycle
- **Testing Protocol** — Instructions for running unit tests (via Nx) and E2E tests (via pytest)
- **Troubleshooting Guides** — Commands for debugging pods, Temporal workflows, database state, and Pulsar messages
- **Service Reference** — Complete list of service URLs, infrastructure ports, and database access details in `skills/workflow-local-dev/reference.md`

**Covered Services:** `workflow-catalog`, `workflow-executions-api`, `workflow-engine-worker`, `workflow-consumer`, `workflow-validator`, `workflows-worker`, `standalone-tasks-worker`

### `e2e-ci-debug`

**Description:** Debug CI E2E failures from pull requests by inspecting GitHub checks, downloading Playwright reports, and mapping failures to local Nx commands. Use when debugging failed E2E tests in PR workflows.

It provides:

- **Automated Artifact Download** — Download Playwright test artifacts from GitHub Actions for the current PR or a specific run
- **Intelligent JUnit Parsing** — Parse JUnit XML results to extract structured failure information with file locations, error messages, and stack traces
- **Screenshot Analysis for AI** — Extract absolute paths to failure screenshots so AI models can visually analyze where tests failed using the Read tool
- **Local Reproduction Guidance** — Generate ready-to-run commands for reproducing failures locally with Nx and Playwright
- **Failure Pattern Recognition** — Common patterns for timeouts, selector issues, setup failures, and flaky tests with solutions
- **CI Workflow Context** — Understanding of the PR workflow chain (`dispatcher.yml` → `pr-core.yaml` → `pr-processor.yml`)

**Utility Scripts:**
- `download-artifacts.sh` — Download Playwright artifacts from GitHub Actions
- `parse-junit.py` — Parse JUnit XML, extract failures, and find screenshot/trace/video paths (supports `--json` and `--screenshots`)
- `find-failing-job.sh` — Find failing E2E jobs in PR workflows
- `cleanup-artifacts.sh` — Remove downloaded artifacts after debugging

**Supported Test Suites:**
- Main Workflow E2E Tests (`dap-workspace/tests/workflow/typescript/`)
- Component-Level E2E Tests (`dap-workspace/libs/workflow/workflow-fe/workflow-fe-e2e/`)

### `yeet`

**Description:** End-to-end Git flow skill for when the user explicitly asks to stage, commit, push, and open a GitHub pull request with `gh` in one streamlined sequence.

It provides:

- **Prerequisite Checks** — Verifies `gh` is installed and authenticated before proceeding
- **Naming Conventions** — Branch, commit, and PR title conventions aligned to workflow/Jira style
- **Commit Message Rules** — Structured commit formatting guidance with type prefixes and bullet style
- **Safe Git Workflow** — Clear sequence for branch creation, staging, committing, and push with tracking
- **PR Creation Guidance** — Draft PR creation with detailed markdown body requirements

### `pr-demo-recorder`

**Description:** Records scripted webreel demos of a PR's changes using the current branch's PR description, linked Jira ticket, reproduction artifacts, and newly-added Playwright E2E tests as the source of truth. Use when the user asks to "create a demo for this PR", "record a webreel for AR-XXXXX", "demo this fix/feature", "generate a demo video", or similar. Handles single-concern PRs, large multi-concern PRs, and epic-level demos. Always plans scope, flow, data source, and format with the user via `AskUserQuestion` before recording — never records unprompted.

It provides:

- **Prerequisite Checks** — Verifies the `webreel` CLI, the companion `~/.claude/skills/webreel/` skill, the `gh` CLI (authenticated), and the `drogers0/gh-image` extension are all installed before any other work proceeds (`scripts/ensure-webreel.sh`).
- **Research Workflow** — Parallel extraction of PR body, Jira ticket (via Atlassian MCP), diff filter for `*.e2e.spec.ts` / `*.seed.ts`, POM selector mining, and repro-artifact discovery.
- **Interactive Planning** — Structured `AskUserQuestion` prompts covering scope (one video vs many), flow-per-video, data source (seed vs reuse vs API-exec), viewport, caption style, and delivery channels.
- **Config Generation** — Selector-priority rules (text > aria-label > data-testid > CSS-Module `[class*="..."]` > `#id`), POM → webreel step translation table, pacing defaults (`defaultDelay: 400`, `fps: 60`, `quality: 85`), and a below-the-fold check that handles nested scroll containers or falls back to `zoom`.
- **Scroll Patterns** — Full reference for window scroll, negative-`y` scroll-up, component-specific scroll via `selector`, identifying the right scroll container when the obvious parent doesn't move, and chaining with `wait` for lazy-loaded content — built from the official [`examples/page-scrolling`](https://github.com/vercel-labs/webreel/tree/main/examples/page-scrolling) config.
- **Caption System (two-pass record + composite)** — Documents webreel 0.1.4's hardcoded 800 ms HUD behavior and the Python timeline-extend workaround that stretches each caption to ~3000 ms by editing `.webreel/timelines/*.timeline.json` and re-running `webreel composite` (~9 s for two videos, no re-record, no ffmpeg).
- **Caption Writing Rules** — Action captions are **OPTIONAL** (drop when the cursor motion and click are self-evident — don't narrate what the pixels already show). Reveal captions default to **natural-prose sentences** using connectives like *used to / previously / no longer / now*; the `Before: <literal UI> → now: <state>.` arrow template is reserved for beats where a literal UI string makes the contrast sharp. A **caption-state matching rule** enforces that each reveal caption fires at the beat where the "after" state is newly visible — a research table maps each fix → old-code trigger → first visible "after" beat before captions are drafted, preventing t=0 summary captions over UI the viewer sees as fine. `≤9` words hard cap; superlatives forbidden. Rejected-patterns table with UI-quoted replacements for the common failure modes.
- **Asset Upload** — `gh image` (via the `drogers0/gh-image` extension) uploads demo MP4s to native `github.com/user-attachments/assets/<uuid>` URLs with session-gated visibility. **Never commits videos to a branch** — the skill contains explicit guardrails and a memory entry against repo bloat. The `upload-to-pr.sh` script is portable across bash 3.2+ (uses `tr` for lowercasing, not bash-4 `${VAR,,}`).
- **PR Body Embedding** — Bare `user-attachments` URL on its own line auto-renders as a playable `<video>` in GitHub-rendered PR descriptions; the skill preserves existing screenshots/copy when prepending the demo section.
- **Multi-Channel Delivery** — Post-record `AskUserQuestion` is **multi-select** with three stable options: prepend to GitHub PR description, post as a comment on the linked Jira ticket, save a copy to `~/Downloads/`. User may tick any combination in one click.
- **Frame Verification** — Post-record sampling via ffmpeg with explicit instruction to read each frame with the `Read` tool, confirming the cursor landed where expected and the HUD is visible during each narrative beat.
- **Repo Cleanup (Phase 7)** — After every selected delivery channel succeeds, the skill deletes the current video's artifacts from the working tree (`videos/<name>.{mp4,png}`, `.webreel/raw/<name>.mp4`, `.webreel/timelines/<name>.timeline.json{,.bak}`) to prevent multi-MB binary accumulation. Scoped to the current video only — sibling videos are left alone. `webreel.config.json` is preserved as the declarative re-record source.
