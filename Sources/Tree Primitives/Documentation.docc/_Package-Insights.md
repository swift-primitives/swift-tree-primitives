# Tree Primitives Insights

<!--
---
title: Tree Primitives Insights
version: 1.0.0
last_updated: 2026-01-22
applies_to: [swift-tree-primitives]
normative: false
---
-->

@Metadata {
    @TitleHeading("Tree Primitives")
}

Design decisions, implementation patterns, and lessons learned specific to this package.

## Overview

This document captures insights that emerged during development of swift-tree-primitives. These are not API requirements—they are recorded decisions and patterns that inform future work on this package.

**Document type**: Non-normative (recorded decisions, not requirements).

**Consolidation source**: Reflection entries tagged with `[Package: swift-tree-primitives]`.

---

## The Typealias Migration Pattern

**Date**: 2026-01-20

**Context**: Refactoring Tree.Binary to be a typealias for Tree.N<Element, 2>, completing the migration from specialized binary tree to parameterized n-ary tree.

When consolidating specialized types into parameterized generics, the typealias provides a clean migration path:

```swift
extension Tree {
    public typealias Binary<Element: ~Copyable> = Tree.N<Element, 2>
}
```

This preserves all existing `Tree.Binary<Int>` usage while the underlying implementation moves to `Tree.N<Element, 2>`. The typealias is resolved at compile time—no runtime cost, no wrapper overhead.

### Position Types Require Migration

Nested types don't alias automatically. `Tree.Binary<Int>.Position` doesn't exist after migration because `Position` was hoisted to `Tree.Position`. This requires explicit migration in client code:

```swift
// Before: var positions: [Tree.Binary<Int>.Position] = []
// After:  var positions: [Tree.Position] = []
```

### Delete-Then-Create Sequencing

1. Create all `Tree.N.*` variants (Bounded, Inline, Small, Traversal)
2. Migrate tests from `Tree.Binary` to `Tree.N<2>`
3. Verify tests pass
4. Delete old `Tree.Binary.*` implementation files
5. Create `Tree.Binary.swift` containing only the typealias

**Applies to**: Type consolidation migrations in general.

---

## Post-Order Traversal and the Rightmost Child Heuristic

**Date**: 2026-01-20

**Context**: Fixing a broken post-order traversal algorithm that returned incorrect ordering for n-ary trees.

### The Failure Mode

The original algorithm tracked "unvisited children" using a complex loop. This failed subtly—producing incorrect traversal orders like `[3, 1]` instead of `[4, 5, 2, 3, 1]`. The bug was difficult to diagnose because simpler trees traversed correctly.

### The Rightmost Child Heuristic

The fix: process the current node if we just came from its rightmost child:

```swift
let cameFromRightmost = rightmostChildIndex >= 0 && rightmostChildIndex == lastVisited

if isLeaf || cameFromRightmost {
    _ = pending.pop()
    process(current)
    lastVisited = current
}
```

This works because post-order requires visiting all children before the parent. If we're at the parent and just visited its rightmost child, we've necessarily visited all children.

### Consistency Across Implementations

The fix was applied in four locations:
1. `Tree.N.swift` - `forEachPostOrder` method
2. `Tree.N.swift` - `removeSubtree` method
3. `Tree.N.swift` - `Storage.deinit`
4. `Tree.N.Traversal.swift` - `PostOrderIterator.next()`

The duplication is unfortunate but necessary given ~Copyable ownership constraints—each context has different requirements (borrows, consumes, deinitializes, copies).

**Applies to**: All post-order traversal implementations.

---

## Parameterized Arity as Design Consolidation

**Date**: 2026-01-20

**Context**: Completing the refactor from Tree.Binary (specialized) to Tree.N<n> (parameterized) as the single tree implementation.

### Consolidation Results

- Eliminated ~1200 lines of redundant code
- Eliminated maintenance divergence vector
- Bug fixes to `Tree.N` automatically apply to binary trees

### When Specialization Is Warranted

The parameterized approach wins because:
1. **Algorithm uniformity**: Pre-order, post-order, level-order work identically for any arity
2. **Storage uniformity**: Arena allocation, position tokens, parent tracking are arity-independent
3. **API uniformity**: Insert, remove, peek, navigation have the same semantics

The only binary-specific feature is in-order traversal, provided via constrained extension `where n == 2`.

### The InlineArray Enabler

The parameterization depends on `InlineArray<n, Int>` for child index storage. Without `InlineArray`, child indices would require heap allocation, unsafe pointers, or manual unrolling.

**Applies to**: Tree.N implementation design.

---

## The Variant Proliferation Pattern

**Date**: 2026-01-20

**Context**: Creating Bounded, Inline, and Small variants for Tree.N matching the pattern established by Tree.Binary.

### Why Three Variants

| Variant | Storage | Capacity | Copy Behavior | Use Case |
|---------|---------|----------|---------------|----------|
| `Tree.N` | Heap (CoW) | Unbounded | Copy-on-write | General purpose |
| `Tree.N.Bounded` | Heap (fixed) | Capped | ~Copyable | Bounded memory |
| `Tree.N.Inline` | Inline | Fixed | ~Copyable | Stack allocation |
| `Tree.N.Small` | Inline + spill | Hybrid | ~Copyable | Small trees fast |

### Shared Position Type

All variants share `Tree.Position` (hoisted to Tree namespace), enabling generic code that works with any variant.

### Error Type Hoisting Pattern

Each variant has its own error type hoisted to module level (`__TreeNBoundedError`, etc.). The double-underscore prefix signals "implementation detail." Hoisting is required because nested error types inside `~Copyable` types inherit that constraint.

**Applies to**: Container variant design patterns.

---

## The n==2 Extension Pattern

**Date**: 2026-01-20

**Context**: Providing binary-tree-specific API (left/right, in-order traversal) via constrained extensions.

```swift
extension Tree.N where n == 2 {
    public func left(of position: Tree.Position) -> Tree.Position? {
        child(of: position, slot: .init(0))
    }
}
```

The `where n == 2` constraint ensures these methods only exist for binary trees. A `Tree.N<Int, 4>` doesn't have `.left(of:)`—it has `.child(of:slot:)`.

### Conditional API as Documentation

The constrained extensions serve as implicit documentation. By seeing that `.left(of:)` only exists when `n == 2`, the API communicates that left/right are binary-tree concepts.

**Applies to**: Binary-specific API on Tree.N.

---

## Test Migration as Verification

**Date**: 2026-01-20

**Context**: Migrating tests from Tree.Binary to Tree.N<2> to verify the refactor.

### Migration Table

| Before | After |
|--------|-------|
| `Tree.Binary<Int>` | `Tree.N<Int, 2>` |
| `Tree.Binary<Int>.Position` | `Tree.Position` |
| `Tree.Binary<Int>.Bounded` | `Tree.N<Int, 2>.Bounded` |
| `__TreeBinaryError` | `__TreeNError` |

### Tests Revealed Bugs

The post-order traversal bug was caught by test migration. The test existed for Tree.Binary and passed. The same test failed for Tree.N<2>. Without test migration, this bug might have shipped.

**Applies to**: Type consolidation verification.

---

## The ~Copyable Sendable Dance

**Date**: 2026-01-20

**Context**: Adding Sendable conformance to Tree.N.Small after test failures.

### Conditional @unchecked Sendable

```swift
extension Tree.N.Small: @unchecked Sendable where Element: Sendable {}
```

The `@unchecked` is justified because:
1. Storage class is not shared (exclusive ownership)
2. Cached pointers are derived from owned storage
3. Access is synchronized by value semantics (~Copyable prevents concurrent access)

This pattern appears throughout container types with unsafe internals.

**Applies to**: Sendable conformance for ~Copyable containers with unsafe internals.

---

## Topics

### Related Documents

- <doc:Tree>
