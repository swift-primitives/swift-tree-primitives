# Tree Typed Remediation: Bare Int to Typed Infrastructure

<!--
---
version: 1.0.0
last_updated: 2026-02-15
status: RECOMMENDATION
tier: 2
---
-->

## Context

The swift-tree-primitives package has excellent naming (Nest.Name throughout), good structure (one-type-per-file), correct layering (arena-based storage, no Foundation), and proper `~Copyable` support. However, the implementation layer systematically uses bare `Int` for node indices, child slots, depths, and sentinel values where the swift-primitives ecosystem provides typed alternatives.

This contradicts [IMPL-INTENT] (intent-over-mechanism), [IMPL-002] (typed arithmetic), [IMPL-006] (typed stored properties), and [IMPL-010] (push Int to the edge).

**Trigger**: [RES-013] Design Audit — proactive implementation-level review against naming, implementation, and existing-infrastructure skills.

**Scope**: Package-specific (swift-tree-primitives).

## Question

Where does `tree-primitives` use bare `Int` instead of typed primitives infrastructure, and what is the phased remediation plan?

---

## Analysis

### Finding 1: Node Model Stores Bare Int

**Location**: `Tree.N.swift:102-118`

```swift
struct Node: ~Copyable {
    var element: Element
    var childIndices: InlineArray<n, Int>   // F-01: bare Int
    var childCount: Int                      // F-02: bare Int
    var parentIndex: Index<Node>?            // ✓ correctly typed
}
```

`childIndices` stores arena slot references as bare `Int` with `-1` sentinel for empty. `childCount` is a bare `Int` count. Meanwhile, `parentIndex` is correctly typed as `Index<Node>?`, demonstrating the pattern already exists within the same struct.

**Contrast**: `parentIndex: Index<Node>?` uses `Optional` for absence. `childIndices` uses magic `-1` for the same semantic.

### Finding 2: Position Handle Stores Bare Int

**Location**: `Tree.Position.swift:35-54`

```swift
public struct Position {
    let index: Int       // F-03: bare Int
    let token: UInt32
}
```

`Position.index` is a bare `Int` that represents an arena slot. It has a typed convenience init (`init(index: Index<T>, token:)`) but the stored property itself is untyped, leaking raw `Int` through every method that reads `position.index`.

### Finding 3: ChildSlot Stores Bare Int

**Location**: `Tree.N.ChildSlot.swift:35-58`

```swift
public struct __TreeNChildSlot<let n: Int> {
    let index: Int       // F-04: bare Int
}
```

A wrapper type exists but its payload is bare `Int` rather than `Index<ChildSlot>.Bounded<n>` or similar typed ordinal.

### Finding 4: Traversal Collections Use `Stack<Int>` / `Queue<Int>`

**Locations**: Throughout `Tree.N.swift` and all iterator files.

| Location | Code | Should Be |
|----------|------|-----------|
| `Tree.N.swift:463` | `Stack<Int>()` | `Stack<Index<Node>>()` |
| `Tree.N.swift:549` | `Stack<(index: Int, depth: Int)>()` | typed tuple |
| `Tree.N.swift:580` | `Stack<Int>()` | `Stack<Index<Node>>()` |
| `Tree.N.swift:605` | `Stack<Int>()` | `Stack<Index<Node>>()` |
| `Tree.N.swift:663` | `Queue<Int>()` | `Queue<Index<Node>>()` |
| `Tree.N.swift:696` | `Stack<Int>()` | `Stack<Index<Node>>()` |
| `Order.Pre.Iterator.swift:21` | `var pending: Stack<Int>` | `Stack<Index<Node>>` |
| `Order.Post.Iterator.swift:21` | `var pending: Stack<Int>` | `Stack<Index<Node>>` |
| `Order.Level.Iterator.swift:21` | `var pending: Queue<Int>` | `Queue<Index<Node>>` |

Same pattern repeats across Bounded, Inline, Small variants and their iterator files (~40 sites total).

### Finding 5: Sentinel `-1` Pervasive

**Pattern**: `-1` used as "no child" / "not visited" throughout.

| Location | Code | Should Be |
|----------|------|-----------|
| `Tree.N.swift:115` | `InlineArray(repeating: -1)` | `InlineArray(repeating: nil)` with `Optional<Index<Node>>` |
| `Tree.N.swift:452` | `childIndices[slot] = -1` | `childIndices[slot] = nil` |
| `Tree.N.swift:464` | `var lastVisited: Int = -1` | `var lastVisited: Index<Node>? = nil` |
| `Tree.N.swift:474` | `var rightmostChildIndex: Int = -1` | `var rightmostChild: Index<Node>? = nil` |
| `Tree.N.swift:476` | `if childIndices[slot] >= 0` | `if let child = childIndices[slot]` |
| `Tree.N.swift:495` | `let isLeaf = rightmostChildIndex < 0` | `let isLeaf = rightmostChild == nil` |
| `Tree.N.swift:546` | `return -1` (height of empty tree) | `return nil` with `Optional<Count>` |

~50 sites across all variants follow this pattern.

### Finding 6: Bare Arithmetic at Call Sites

| Location | Code | Violation |
|----------|------|-----------|
| `Tree.N.swift:453` | `childCount -= 1` | [IMPL-002]: should be typed subtraction |
| `Tree.N.swift:475` | `stride(from: n - 1, through: 0, by: -1)` | [IMPL-002]: bare `n - 1` |
| `Tree.N.swift:554` | `Swift.max(maxHeight, depth)` | [IMPL-005]: should be `Count.max(a, b)` |
| `Tree.N.swift:560` | `depth + 1` | [IMPL-002]: bare integer arithmetic |
| All iterator files | `stride(from: n - 1, through: 0, by: -1)` | [IMPL-002]: repeated pattern |

### Finding 7: Conversion Helpers Are Band-Aid

**Location**: `Tree.N.swift:132-142`

```swift
func _slot(_ index: Int) -> Index<Node> {
    Index<Node>(Ordinal(UInt(index)))
}
func _rawIndex(_ index: Index<Node>) -> Int {
    Int(bitPattern: index)
}
```

These exist because the core data model stores bare `Int`, requiring constant round-tripping. If the data model stored typed indices natively, these helpers would be unnecessary.

### Finding 8: Swift.Array in Unbounded (Known)

**Location**: `Tree.Unbounded.swift:96-104`

Documented workaround (Phase 5 / F-04). `Swift.Array<Int>` for dynamic child storage because `Array_Primitives.Array<Int>` lacks `firstIndex(of:)`, `insert(_:at:)`, `remove(at:)`. This remains a valid tracked deviation.

---

## Remediation Plan

### Guiding Principle

The typed domain boundary should live at the **Node struct**, not scattered across every method. If `Node.childIndices` stores `Optional<Index<Node>>` instead of sentinel `Int`, all downstream code naturally uses typed optionals, eliminating ~80% of the bare-Int sites without changing any algorithm logic.

### Phase 1: Core Data Model (Highest Impact, Smallest Diff)

**Goal**: Type the Node struct. This cascades through all code that reads/writes node fields.

**Changes**:

1. **`Node.childIndices`**: `InlineArray<n, Int>` → `InlineArray<n, Index<Node>?>`
   - Empty sentinel changes from `-1` to `nil`
   - All `childIndices[slot] >= 0` checks become `if let child = childIndices[slot]`
   - All `childIndices[slot] = -1` become `childIndices[slot] = nil`

2. **`Node.childCount`**: `Int` → `Index<Node>.Count`
   - `childCount -= 1` → `childCount = childCount.subtract.saturating(.one)`
   - `childCount += 1` → `childCount += .one`
   - `childCount == 0` → `childCount == .zero`

3. **`_slot()` / `_rawIndex()`** helpers: Remove entirely — no longer needed if traversal collections store typed indices.

**Files affected**: `Tree.N.swift`, `Tree.N.Bounded.swift`, `Tree.N.Inline.swift`, `Tree.N.Small.swift` (same Node struct in each).

**Estimated impact**: Eliminates ~80% of bare-Int sites mechanically.

### Phase 2: Traversal Collections

**Goal**: `Stack<Index<Node>>` and `Queue<Index<Node>>` instead of `Stack<Int>` / `Queue<Int>`.

**Changes**:

1. All `Stack<Int>()` → `Stack<Index<Node>>()`
2. All `Queue<Int>()` → `Queue<Index<Node>>()`
3. `pending.push(childIndex)` already passes the correct type after Phase 1 (childIndices stores `Index<Node>?`)
4. `lastVisited: Int = -1` → `lastVisited: Index<Node>? = nil`

**Files affected**: All `Tree.N.Order.*.Iterator.swift` files, inline traversal methods in `Tree.N.swift` and variants (~20 files).

### Phase 3: Position and ChildSlot

**Goal**: Type the public position handle and child slot.

**Changes**:

1. **`Tree.Position.index`**: `Int` → `Index<Tree.Position>` or an opaque typed wrapper
   - The typed init already exists; make the stored property match
   - Validation (`position.index >= 0`) becomes unnecessary (typed indices can't be negative)

2. **`ChildSlot.index`**: `Int` → `Index<ChildSlot>.Bounded<n>` (or keep as-is if InlineArray subscripting doesn't support typed indices yet)
   - Binary/ternary/quad conveniences (`.left`, `.right`, etc.) adjust to typed construction

**Constraint**: `InlineArray` subscript currently accepts bare `Int`. If it doesn't accept typed indices, `ChildSlot` typing may require a boundary overload on InlineArray access.

### Phase 4: Height and Depth

**Goal**: Type traversal depth and tree height.

**Changes**:

1. **Height return type**: `Int` → `Optional<Index<Node>.Count>`
   - Empty tree returns `nil` instead of `-1`
   - Single node returns `.zero` (unchanged semantically)

2. **Depth in traversal tuples**: `(index: Int, depth: Int)` → `(index: Index<Node>, depth: Index<Node>.Count)`
   - `depth + 1` → `depth + .one`
   - `Swift.max(maxHeight, depth)` → `Index<Node>.Count.max(maxHeight, depth)`

3. **Loop bounds**: `for slot in 0..<n` → typed range if `ChildSlot` supports iteration, otherwise document as acceptable bare-Int boundary (InlineArray subscript limitation).

### Phase 5: Unbounded Variant (Deferred)

**Goal**: Replace `Swift.Array<Int>` with typed primitives collection.

**Prerequisite**: `Array_Primitives.Array` must expose `firstIndex(of:)`, `insert(_:at:)`, `remove(at:)` APIs, or the child storage must be redesigned (e.g., linked list of children using `Buffer.Arena` indices).

**Status**: Already tracked as F-04 in prior remediation plan. No change to timeline.

---

## Dependency Graph

```
Phase 1 (Node model)
    ↓
Phase 2 (Traversal collections)  ←  depends on Phase 1 (typed indices flow from Node)
    ↓
Phase 3 (Position / ChildSlot)   ←  independent of Phase 2, depends on Phase 1
    ↓
Phase 4 (Height / Depth)         ←  depends on Phase 2 (traversal tuple types)
    ↓
Phase 5 (Unbounded Array)        ←  external dependency (Array_Primitives API parity)
```

Phases 2 and 3 can proceed in parallel after Phase 1.

---

## Risk Assessment

| Phase | Risk | Mitigation |
|-------|------|------------|
| 1 | InlineArray<n, Optional<Index<Node>>> may have different layout than InlineArray<n, Int> | Verify with experiment; Optional<Index<Node>> is pointer-sized on 64-bit |
| 2 | Stack/Queue with typed Index<Node> is ~Copyable-aware? | Verify Stack<Index<Node>> compiles; Index<Node> is Copyable so no issue |
| 3 | Position.index typing may break Equatable/Hashable | Index<Node> already conforms to Equatable/Hashable |
| 4 | Height Optional return is API-breaking | Acceptable at primitives layer; no external consumers yet |
| 5 | Array_Primitives API parity is external blocker | Defer; document workaround |

---

## Outcome

**Status**: RECOMMENDATION

The tree-primitives package naming and structure are exemplary. The implementation layer needs systematic remediation to use typed primitives infrastructure instead of bare `Int`. The five-phase plan prioritizes the Node data model (Phase 1) because it cascades through ~80% of bare-Int sites mechanically.

Phases 1–4 are self-contained within tree-primitives. Phase 5 is blocked on external API parity in Array_Primitives.

## References

- [IMPL-INTENT]: Intent-over-mechanism axiom
- [IMPL-002]: Typed arithmetic
- [IMPL-006]: Typed stored properties
- [IMPL-010]: Push Int to the edge
- [TREE-003]: Sparse child slot semantics
- [TREE-008]: ~Copyable constraint propagation
- Research/tree-discipline-boundary-analysis.md: Prior layering audit
