---
title: Hoist RegExp Creation
impact: LOW-MEDIUM
impactDescription: avoids recreation
tags: javascript, regexp, optimization
---

## Hoist RegExp Creation

For static RegExp patterns, hoist to module scope. React Compiler handles dynamic patterns automatically.

**Static patterns - hoist to module scope:**

```tsx
// ✅ Hoisted - created once
const EMAIL_REGEX = /^[^\s@]+@[^\s@]+\.[^\s@]+$/

function validateEmail(email: string) {
  return EMAIL_REGEX.test(email)
}
```

**Dynamic patterns - just write normal code:**

```tsx
// ✅ React Compiler optimizes this automatically
function Highlighter({ text, query }: Props) {
  const regex = new RegExp(`(${escapeRegex(query)})`, 'gi')
  const parts = text.split(regex)
  return <>{parts.map((part, i) => ...)}</>
}
```

> **Note**: Do NOT use `useMemo` for RegExp - React Compiler handles this automatically.

**Warning (global regex has mutable state):**

Global regex (`/g`) has mutable `lastIndex` state:

```typescript
const regex = /foo/g
regex.test('foo')  // true, lastIndex = 3
regex.test('foo')  // false, lastIndex = 0
```
