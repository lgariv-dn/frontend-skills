---
title: Use Functional setState Updates
impact: MEDIUM
impactDescription: prevents stale closures
tags: react, hooks, useState, callbacks, closures
---

## Use Functional setState Updates

When updating state based on the current state value, use the functional update form of setState. This prevents stale closure bugs.

> **Note**: This rule is about **correctness**, not optimization. React Compiler doesn't change this - functional updates are still the right pattern.

**Incorrect (stale closure risk):**

```tsx
function TodoList() {
  const [items, setItems] = useState(initialItems)
  
  const addItems = (newItems: Item[]) => {
    // ❌ If called in async context, `items` may be stale
    setItems([...items, ...newItems])
  }
  
  const removeItem = (id: string) => {
    // ❌ Same stale closure risk
    setItems(items.filter(item => item.id !== id))
  }
  
  return <ItemsEditor items={items} onAdd={addItems} onRemove={removeItem} />
}
```

**Correct (always uses latest state):**

```tsx
function TodoList() {
  const [items, setItems] = useState(initialItems)
  
  const addItems = (newItems: Item[]) => {
    // ✅ Always operates on latest state
    setItems(curr => [...curr, ...newItems])
  }
  
  const removeItem = (id: string) => {
    // ✅ No stale closure risk
    setItems(curr => curr.filter(item => item.id !== id))
  }
  
  return <ItemsEditor items={items} onAdd={addItems} onRemove={removeItem} />
}
```

**When to use functional updates:**

- Any setState that depends on the current state value
- Event handlers that reference state
- Async operations that update state

**When direct updates are fine:**

- Setting state to a static value: `setCount(0)`
- Setting state from props/arguments only: `setName(newName)`
- State doesn't depend on previous value
