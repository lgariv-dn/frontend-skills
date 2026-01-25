# Frontend Skills

This repository contains reusable "skills" that can be loaded into AI agents to guide how they write, review, and refactor frontend code.

## Installation

From the root of this repo, you can install the skills into your agent environment.


```bash
npx add-skill lgariv-dn/frontend-skills
```

## Available Skills

### `react-best-practices`

**Description:** React performance optimization guidelines adapted from `vercel-labs/agent-skills` repo - without all of their extra next.js optimization and focused on react 19 best practices. This skill should be automatically used when writing, reviewing, or refactoring React code to ensure optimal performance patterns.

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
- **Service Reference** — Complete list of service URLs, infrastructure ports, and database access details in `workflow-local-dev/reference.md`

**Covered Services:** `workflow-catalog`, `workflow-executions-api`, `workflow-engine-worker`, `workflow-consumer`, `workflow-validator`, `workflows-worker`, `standalone-tasks-worker`