# Frontend Skills

This repository contains reusable "skills" that can be loaded into AI agents to guide how they write, review, and refactor frontend code.

## Installation

From the root of this repo, you can install the skills into your agent environment.


```bash
npx add-skill lgariv-dn/frontend-skills
```

## Available Skills

### `vercel-react-best-practices`

**Description:** React performance optimization guidelines adapted from `vercel-labs/agent-skills` repo - without all of their extra next.js optimization and focused on react 19 best practices. This skill should be automatically used when writing, reviewing, or refactoring React code to ensure optimal performance patterns.

It provides a comprehensive set of **30 rules across 7 categories**, prioritized by impact:

1. **Eliminating Waterfalls (CRITICAL)** — Avoiding sequential async waterfalls, using `Promise.all` for independent work, and structuring components with Suspense boundaries.
2. **Bundle Size Optimization (CRITICAL)** — Avoiding barrel imports, loading large modules conditionally, and preloading based on user intent.
3. **Client-Side Patterns (MEDIUM-HIGH)** — Safer, more efficient patterns for things like `localStorage` and scroll/touch event listeners.
4. **Re-render Optimization (MEDIUM)** — Deferring state reads, narrowing effect dependencies, using functional `setState`, lazy state initialization, and transitions for non-urgent updates.
5. **Rendering Performance (MEDIUM)** — Techniques like animating wrapper elements, `content-visibility` for long lists, SVG size optimizations, and safer conditional rendering.
6. **JavaScript Performance (LOW-MEDIUM)** — Micro-optimizations in hot paths such as batching DOM changes, using Maps/Sets, caching expensive computations, and avoiding unnecessary sorts.
7. **Advanced Patterns (LOW)** — Patterns like storing event handlers in refs to keep subscriptions stable.

Each rule has its own markdown file in `skills/vercel-react-best-practices/rules/` with:
- A short explanation of why the rule matters
- An incorrect example and a corrected version
- Additional notes and references

Note that some of these skills rely on the usage of a minimum react 19.2.x version and react compiler enabled.