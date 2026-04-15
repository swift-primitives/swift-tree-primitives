# Tree Operations Audit

<!--
---
version: 1.0.0
last_updated: 2026-02-16
status: RECOMMENDATION
tier: 1
---
-->

## Context

Proactive audit of swift-tree-primitives per [RES-012] Discovery.
**Scope**: Package-specific (swift-tree-primitives).

This audit inventories every public operation across all tree variants and compares them against canonical Tree ADT operations. The goal is to identify gaps (missing operations that belong at the primitives layer), intentional absences (operations that belong at higher layers), and any operations beyond the canonical set.

Prior research documents cover discipline boundaries (`tree-discipline-boundary-analysis.md`) and typed remediation (`tree-typed-remediation.md`). This document focuses exclusively on **operations completeness**.

## Question

Does swift-tree-primitives provide the canonical operations expected of the Tree ADT?

---

## Canonical Operations (ADT Reference)

### General Tree

| Operation | Expected Complexity | Description |
|-----------|-------------------|-------------|
| insert(node, x) | O(1) | Add child to node |
| remove_subtree(node) | O(subtree size) | Remove node and descendants |
| parent(node) | O(1) | Get parent node |
| children(node) | O(1) | Get child nodes |
| root | O(1) | Get root node |
| is_leaf(node) | O(1) | Check if node is leaf |
| height | O(n) | Tree height |
| count/size | O(1) | Number of nodes |
| isEmpty | O(1) | Empty check |
| clear | O(n) | Remove all nodes |

### Traversal Operations

| Operation | Complexity | Description |
|-----------|-----------|-------------|
| pre-order | O(n) | Root, then children |
| in-order | O(n) | Left, root, right (binary only) |
| post-order | O(n) | Children, then root |
| level-order (BFS) | O(n) | Level by level |

### N-ary Tree Specific

| Operation | Complexity | Description |
|-----------|-----------|-------------|
| child_at(slot) | O(1) | Access specific child slot |
| child_count | O(1) | Number of children |
| is_full | O(1) | All child slots occupied |

---

## Current Operations Inventory

### Type Hierarchy

```
Tree                           (namespace enum)
  Tree.Position                (shared cursor type, Sendable, Equatable, Hashable)
  Tree.Index<Element>          (typealias for Index_Primitives.Index<Element>)
  Tree.Binary<Element>         (typealias for Tree.N<Element, 2>)

  Tree.N<Element, let n>       (bounded-arity, dynamic growth)
    Tree.N.Bounded             (fixed capacity)
    Tree.N.Inline<let capacity>(zero-allocation inline storage)
    Tree.N.Small<let inlineCapacity> (inline with spill-to-heap)
    Tree.N.Node                (arena node)
    Tree.N.ChildSlot           (bounded slot index 0..<n)
    Tree.N.InsertPosition      (.root | .child(of:slot:))
    Tree.N.Error               (typed error enum)
    Tree.N.Count               (typealias for Index<Node>.Count)
    Tree.N.Order               (namespace for traversal sequences, Copyable only)
      Order.Pre.Sequence / .Iterator
      Order.In.Sequence / .Iterator   (n == 2 only)
      Order.Post.Sequence / .Iterator
      Order.Level.Sequence / .Iterator

  Tree.Unbounded<Element>      (dynamic arity, dynamic growth)
    Tree.Unbounded.Node        (arena node with dynamic child array)
    Tree.Unbounded.InsertPosition (.root | .child(of:at:) | .appendChild(of:))
    Tree.Unbounded.Error       (typed error enum)
    Tree.Unbounded.Count       (typealias for Index<Node>.Count)
```

Note: `Tree.Unbounded.Bounded` and `Tree.Unbounded.Small` have error types declared but the structs themselves were not found in the source files read. Their error types exist (`__TreeUnboundedBoundedError`, `__TreeUnboundedSmallError`), suggesting these variants are planned or exist outside the files inventoried.

---

### Tree.N (Growable N-ary Tree)

**File**: `Sources/Tree Primitives/Tree.N.swift`

#### Initialization

| Signature | Constraint | Line |
|-----------|-----------|------|
| `public init()` | `Element: ~Copyable` | 142 |
| `public init(minimumCapacity: Count)` | `Element: ~Copyable` | 151 |

#### Properties

| Signature | Type | Constraint | Line |
|-----------|------|-----------|------|
| `public var count: Count` | computed | `Element: ~Copyable` | 160 |
| `public var isEmpty: Bool` | computed | `Element: ~Copyable` | 164 |
| `public static var arity: Int` | static | `Element: ~Copyable` | 168 |
| `public var root: Tree.Position?` | computed | `Element: ~Copyable` | 172 |
| `public var height: Count?` | computed | `Element: ~Copyable` | 533 |

#### Navigation

| Signature | Returns | Constraint | Line |
|-----------|---------|-----------|------|
| `public func child(of:slot:) -> Tree.Position?` | position | `Element: ~Copyable` | 208 |
| `public func parent(of:) -> Tree.Position?` | position | `Element: ~Copyable` | 226 |
| `public func isLeaf(_:) -> Bool` | bool | `Element: ~Copyable` | 245 |
| `public func childCount(of:) -> Count?` | count | `Element: ~Copyable` | 259 |
| `public func leftmostChild(of:) -> Tree.Position?` | position | `Element: ~Copyable` | 273 |
| `public func rightmostChild(of:) -> Tree.Position?` | position | `Element: ~Copyable` | 294 |
| `public func left(of:) -> Tree.Position?` | position | `n == 2` | 321 |
| `public func right(of:) -> Tree.Position?` | position | `n == 2` | 330 |

#### Mutation

| Signature | Returns | Constraint | Line |
|-----------|---------|-----------|------|
| `public mutating func insert(_:at:) throws(__TreeNError) -> Tree.Position` | position | `Element: ~Copyable` | 350 |
| `public mutating func insert(_:at:) throws(__TreeNError) -> Tree.Position` | position | `Element: Copyable` (CoW) | 714 |
| `public mutating func remove(at:) throws(__TreeNError) -> Element` | element | `Element: ~Copyable` | 393 |
| `public mutating func removeSubtree(at:) throws(__TreeNError)` | void | `Element: ~Copyable` | 431 |
| `public mutating func clear()` | void | `Element: ~Copyable` | 521 |

#### Element Access

| Signature | Returns | Constraint | Line |
|-----------|---------|-----------|------|
| `public func peek<R>(at:_:) -> R?` | closure result | `Element: ~Copyable` | 510 |
| `public func peek(at:) -> Element?` | element copy | `Element: Copyable` | 756 |

#### Traversal (Closure-Based, ~Copyable)

| Signature | Constraint | Line |
|-----------|-----------|------|
| `public func forEachPreOrder(_:)` | `Element: ~Copyable` | 565 |
| `public func forEachPostOrder(_:)` | `Element: ~Copyable` | 589 |
| `public func forEachLevelOrder(_:)` | `Element: ~Copyable` | 645 |
| `public func forEachInOrder(_:)` | `Element: ~Copyable, n == 2` | 678 |

#### Traversal (Sequence-Based, Copyable Only)

| Property | Returns | Constraint | Line (Tree.N.Traversal.swift) |
|----------|---------|-----------|------|
| `public var preOrder: Order.Pre.Sequence` | sequence | `Element: Copyable` | 17 |
| `public var postOrder: Order.Post.Sequence` | sequence | `Element: Copyable` | 22 |
| `public var levelOrder: Order.Level.Sequence` | sequence | `Element: Copyable` | 27 |
| `public var inOrder: Order.In.Sequence` | sequence | `Element: Copyable, n == 2` | 39 |

#### Protocol Conformances

| Conformance | Constraint |
|-------------|-----------|
| `Copyable` | `Element: Copyable` |
| `@unchecked Sendable` | `Element: Sendable` |

---

### Tree.N.Bounded (Fixed-Capacity N-ary Tree)

**File**: `Sources/Tree Primitives/Tree.N.Bounded.swift`

#### Initialization

| Signature | Constraint | Line |
|-----------|-----------|------|
| `public init(capacity: Count)` | `Element: ~Copyable` | 71 |

#### Properties

| Signature | Type | Constraint | Line |
|-----------|------|-----------|------|
| `public var count: Count` | computed | `Element: ~Copyable` | 81 |
| `public var isEmpty: Bool` | computed | `Element: ~Copyable` | 85 |
| `public var isFull: Bool` | computed | `Element: ~Copyable` | 89 |
| `public let capacity: Count` | stored | `Element: ~Copyable` | 57 |
| `public var root: Tree.Position?` | computed | `Element: ~Copyable` | 93 |
| `public var height: Count?` | computed | `Element: ~Copyable` | 350 |

#### Navigation

| Signature | Returns | Constraint | Line |
|-----------|---------|-----------|------|
| `public func child(of:slot:) -> Tree.Position?` | position | `Element: ~Copyable` | 117 |
| `public func parent(of:) -> Tree.Position?` | position | `Element: ~Copyable` | 131 |
| `public func isLeaf(_:) -> Bool` | bool | `Element: ~Copyable` | 146 |
| `public func childCount(of:) -> Count?` | count | `Element: ~Copyable` | 157 |
| `public func left(of:) -> Tree.Position?` | position | `n == 2` | 173 |
| `public func right(of:) -> Tree.Position?` | position | `n == 2` | 179 |

#### Mutation

| Signature | Returns | Constraint | Line |
|-----------|---------|-----------|------|
| `public mutating func insert(_:at:) throws(__TreeNBoundedError) -> Tree.Position` | position | `Element: ~Copyable` | 191 |
| `public mutating func insert(_:at:) throws(__TreeNBoundedError) -> Tree.Position` | position | `Element: Copyable` (CoW) | 505 |
| `public mutating func remove(at:) throws(__TreeNBoundedError) -> Element` | element | `Element: ~Copyable` | 241 |
| `public mutating func removeSubtree(at:) throws(__TreeNBoundedError)` | void | `Element: ~Copyable` | 268 |
| `public mutating func clear()` | void | `Element: ~Copyable` | 341 |

#### Element Access

| Signature | Returns | Constraint | Line |
|-----------|---------|-----------|------|
| `public func peek<R>(at:_:) -> R?` | closure result | `Element: ~Copyable` | 330 |
| `public func peek(at:) -> Element?` | element copy | `Element: Copyable` | 556 |

#### Traversal (Closure-Based, ~Copyable)

| Signature | Constraint | Line |
|-----------|-----------|------|
| `public func forEachPreOrder(_:)` | `Element: ~Copyable` | 379 |
| `public func forEachPostOrder(_:)` | `Element: ~Copyable` | 399 |
| `public func forEachLevelOrder(_:)` | `Element: ~Copyable` | 446 |
| `public func forEachInOrder(_:)` | `Element: ~Copyable, n == 2` | 473 |

#### Traversal (Sequence-Based, Copyable Only)

| Property | Returns | Constraint | Line |
|----------|---------|-----------|------|
| `public var preOrder: Order.Pre.Sequence` | sequence | `Element: Copyable` | 571 |
| `public var postOrder: Order.Post.Sequence` | sequence | `Element: Copyable` | 576 |
| `public var levelOrder: Order.Level.Sequence` | sequence | `Element: Copyable` | 581 |
| `public var inOrder: Order.In.Sequence` | sequence | `Element: Copyable, n == 2` | 591 |

#### Protocol Conformances

| Conformance | Constraint |
|-------------|-----------|
| `Copyable` | `Element: Copyable` |
| `@unchecked Sendable` | `Element: Sendable` |

---

### Tree.N.Inline (Zero-Allocation Inline N-ary Tree)

**File**: `Sources/Tree Primitives/Tree.N.Inline.swift`

#### Initialization

| Signature | Constraint | Line |
|-----------|-----------|------|
| `public init()` | `Element: ~Copyable` | 69 |

#### Properties

| Signature | Type | Constraint | Line |
|-----------|------|-----------|------|
| `public var count: Count` | computed | `Element: ~Copyable` | 78 |
| `public var isEmpty: Bool` | computed | `Element: ~Copyable` | 82 |
| `public var isFull: Bool` | computed | `Element: ~Copyable` | 86 |
| `public var root: Tree.Position?` | computed | `Element: ~Copyable` | 90 |

#### Navigation (all `mutating` due to inline arena access)

| Signature | Returns | Constraint | Line |
|-----------|---------|-----------|------|
| `public mutating func child(of:slot:) -> Tree.Position?` | position | `Element: ~Copyable` | 115 |
| `public mutating func parent(of:) -> Tree.Position?` | position | `Element: ~Copyable` | 128 |
| `public mutating func isLeaf(_:) -> Bool` | bool | `Element: ~Copyable` | 142 |
| `public mutating func childCount(of:) -> Count?` | count | `Element: ~Copyable` | 153 |
| `public mutating func left(of:) -> Tree.Position?` | position | `n == 2` | 168 |
| `public mutating func right(of:) -> Tree.Position?` | position | `n == 2` | 173 |

#### Mutation

| Signature | Returns | Constraint | Line |
|-----------|---------|-----------|------|
| `public mutating func insert(_:at:) throws(__TreeNInlineError) -> Tree.Position` | position | `Element: ~Copyable` | 185 |
| `public mutating func remove(at:) throws(__TreeNInlineError) -> Element` | element | `Element: ~Copyable` | 235 |
| `public mutating func removeSubtree(at:) throws(__TreeNInlineError)` | void | `Element: ~Copyable` | 262 |
| `public mutating func clear()` | void | `Element: ~Copyable` | 335 |

#### Element Access

| Signature | Returns | Constraint | Line |
|-----------|---------|-----------|------|
| `public mutating func peek<R>(at:_:) -> R?` | closure result | `Element: ~Copyable` | 324 |
| `public mutating func peek(at:) -> Element?` | element copy | `Element: Copyable` | 488 |

#### Height

| Signature | Returns | Constraint | Line |
|-----------|---------|-----------|------|
| `public mutating func height() -> Count?` | count | `Element: ~Copyable` | 344 |

Note: `height` is a method (not a computed property) in Inline because the inline arena requires `mutating` access.

#### Traversal (Closure-Based, ~Copyable, all `mutating`)

| Signature | Constraint | Line |
|-----------|-----------|------|
| `public mutating func forEachPreOrder(_:)` | `Element: ~Copyable` | 372 |
| `public mutating func forEachPostOrder(_:)` | `Element: ~Copyable` | 391 |
| `public mutating func forEachLevelOrder(_:)` | `Element: ~Copyable` | 437 |
| `public mutating func forEachInOrder(_:)` | `Element: ~Copyable, n == 2` | 463 |

#### Traversal (Sequence-Based)

**Not provided.** Inline is unconditionally `~Copyable`, so Sequence conformance (which requires `Copyable` iterator capture of tree) is not feasible.

#### Protocol Conformances

| Conformance | Constraint |
|-------------|-----------|
| `@unchecked Sendable` | `Element: Sendable` |

Note: Inline is unconditionally `~Copyable` (no conditional Copyable conformance).

---

### Tree.N.Small (Inline with Spill-to-Heap)

**File**: `Sources/Tree Primitives/Tree.N.Small.swift`

#### Initialization

| Signature | Constraint | Line |
|-----------|-----------|------|
| `public init()` | `Element: ~Copyable` | 79 |

#### Properties

| Signature | Type | Constraint | Line |
|-----------|------|-----------|------|
| `public var count: Count` | mutating get | — | 98 |
| `public var isEmpty: Bool` | mutating get | — | 104 |
| `public var root: Tree.Position?` | computed | — | 110 |
| `public var isSpilled: Bool` | mutating get | — | 87 |

#### Navigation (all `mutating`)

| Signature | Returns | Constraint | Line |
|-----------|---------|-----------|------|
| `public mutating func child(of:slot:) -> Tree.Position?` | position | — | 131 |
| `public mutating func parent(of:) -> Tree.Position?` | position | — | 144 |
| `public mutating func childCount(of:) -> Count?` | count | — | 158 |
| `public mutating func isLeaf(_:) -> Bool` | bool | — | 169 |
| `public mutating func left(of:) -> Tree.Position?` | position | `n == 2` | 185 |
| `public mutating func right(of:) -> Tree.Position?` | position | `n == 2` | 191 |

#### Mutation

| Signature | Returns | Constraint | Line |
|-----------|---------|-----------|------|
| `public mutating func insert(_:at:) throws(__TreeNSmallError) -> Tree.Position` | position | — | 203 |
| `public mutating func remove(at:) throws(__TreeNSmallError) -> Element` | element | — | 238 |
| `public mutating func removeSubtree(at:) throws(__TreeNSmallError)` | void | — | 267 |
| `public mutating func clear()` | void | — | 345 |

#### Element Access

| Signature | Returns | Constraint | Line |
|-----------|---------|-----------|------|
| `public mutating func peek<R>(at:_:) -> R?` | closure result | — | 331 |
| `public mutating func peek(at:) -> Element?` | element copy | `Element: Copyable` | 505 |

#### Traversal (Closure-Based, all `mutating`)

| Signature | Constraint | Line |
|-----------|-----------|------|
| `public mutating func forEachPreOrder(_:)` | — | 354 |
| `public mutating func forEachPostOrder(_:)` | — | 376 |
| `public mutating func forEachLevelOrder(_:)` | — | 423 |
| `public mutating func forEachInOrder(_:)` | `n == 2` | 480 |

#### Height

| Signature | Returns | Constraint | Line |
|-----------|---------|-----------|------|
| `public mutating func height() -> Count?` | count | — | 448 |

#### Traversal (Sequence-Based)

**Not provided.** Same rationale as Inline: unconditionally `~Copyable`.

#### Protocol Conformances

| Conformance | Constraint |
|-------------|-----------|
| `@unchecked Sendable` | `Element: Sendable` |

Note: Small is unconditionally `~Copyable` (no conditional Copyable conformance).

---

### Tree.Unbounded (Dynamic-Arity Tree)

**File**: `Sources/Tree Primitives/Tree.Unbounded.swift`

#### Initialization

| Signature | Constraint | Line |
|-----------|-----------|------|
| `public init()` | `Element: ~Copyable` | 149 |
| `public init(minimumCapacity: Count)` | `Element: ~Copyable` | 158 |

#### Properties

| Signature | Type | Constraint | Line |
|-----------|------|-----------|------|
| `public var count: Count` | computed | `Element: ~Copyable` | 167 |
| `public var isEmpty: Bool` | computed | `Element: ~Copyable` | 171 |
| `public var root: Tree.Position?` | computed | `Element: ~Copyable` | 175 |
| `public var height: Count?` | computed | `Element: ~Copyable` | 482 |

#### Navigation

| Signature | Returns | Constraint | Line |
|-----------|---------|-----------|------|
| `public func child(of:at:) -> Tree.Position?` | position | `Element: ~Copyable` | 211 |
| `public func parent(of:) -> Tree.Position?` | position | `Element: ~Copyable` | 230 |
| `public func isLeaf(_:) -> Bool` | bool | `Element: ~Copyable` | 249 |
| `public func childCount(of:) -> Int?` | count | `Element: ~Copyable` | 263 |
| `public func firstChild(of:) -> Tree.Position?` | position | `Element: ~Copyable` | 277 |
| `public func lastChild(of:) -> Tree.Position?` | position | `Element: ~Copyable` | 286 |

Note: `childCount(of:)` returns `Int?` (not typed `Count?`). This is tracked by the typed remediation research document.

#### Mutation

| Signature | Returns | Constraint | Line |
|-----------|---------|-----------|------|
| `public mutating func insert(_:at:) throws(__TreeUnboundedError) -> Tree.Position` | position | `Element: ~Copyable` | 315 |
| `public mutating func insert(_:at:) throws(__TreeUnboundedError) -> Tree.Position` | position | `Element: Copyable` (CoW) | 612 |
| `public mutating func remove(at:) throws(__TreeUnboundedError) -> Element` | element | `Element: ~Copyable` | 366 |
| `public mutating func removeSubtree(at:) throws(__TreeUnboundedError)` | void | `Element: ~Copyable` | 398 |
| `public mutating func clear()` | void | `Element: ~Copyable` | 470 |

#### Element Access

| Signature | Returns | Constraint | Line |
|-----------|---------|-----------|------|
| `public func peek<R>(at:_:) -> R?` | closure result | `Element: ~Copyable` | 459 |
| `public func peek(at:) -> Element?` | element copy | `Element: Copyable` | 662 |

#### Traversal (Closure-Based, ~Copyable)

| Signature | Constraint | Line |
|-----------|-----------|------|
| `public func forEachPreOrder(_:)` | `Element: ~Copyable` | 512 |
| `public func forEachPostOrder(_:)` | `Element: ~Copyable` | 535 |
| `public func forEachLevelOrder(_:)` | `Element: ~Copyable` | 579 |

Note: No `forEachInOrder` -- in-order traversal is defined only for binary trees (n == 2), which does not apply to unbounded arity.

#### Traversal (Sequence-Based)

**Not provided.** Unlike `Tree.N` and `Tree.N.Bounded`, `Tree.Unbounded` does not expose `Order` namespace or sequence-based traversal properties.

#### Protocol Conformances

| Conformance | Constraint |
|-------------|-----------|
| `Copyable` | `Element: Copyable` |
| `@unchecked Sendable` | `Element: Sendable` |

---

### Supporting Types

#### Tree.N.ChildSlot (`__TreeNChildSlot<let n>`)

**File**: `Sources/Tree Primitives/Tree.N.ChildSlot.swift`

| Member | Constraint |
|--------|-----------|
| `public init?(_ index: Int)` | all n |
| `public static var left: Self` | `n == 2` |
| `public static var right: Self` | `n == 2` |
| `public static var left: Self` | `n == 3` |
| `public static var middle: Self` | `n == 3` |
| `public static var right: Self` | `n == 3` |
| `public static var northwest: Self` | `n == 4` |
| `public static var northeast: Self` | `n == 4` |
| `public static var southwest: Self` | `n == 4` |
| `public static var southeast: Self` | `n == 4` |
| `var description: String` | CustomStringConvertible |
| Sendable, Equatable, Hashable | all n |

#### Tree.N.InsertPosition (`__TreeNInsertPosition<let n>`)

**File**: `Sources/Tree Primitives/Tree.N.InsertPosition.swift`

| Case/Member | Constraint |
|-------------|-----------|
| `.root` | all n |
| `.child(of: Tree.Position, slot: ChildSlot)` | all n |
| `static func left(of:) -> Self` | `n == 2` |
| `static func right(of:) -> Self` | `n == 2` |
| `static func left(of:) -> Self` | `n == 3` |
| `static func middle(of:) -> Self` | `n == 3` |
| `static func right(of:) -> Self` | `n == 3` |
| `static func northwest(of:) -> Self` | `n == 4` |
| `static func northeast(of:) -> Self` | `n == 4` |
| `static func southwest(of:) -> Self` | `n == 4` |
| `static func southeast(of:) -> Self` | `n == 4` |
| Sendable, Equatable | all n |

#### Tree.Unbounded.InsertPosition (`__TreeUnboundedInsertPosition`)

**File**: `Sources/Tree Primitives/Tree.Unbounded.InsertPosition.swift`

| Case | Description |
|------|-------------|
| `.root` | Insert as root |
| `.child(of: Tree.Position, at: Int)` | Insert at specific child index |
| `.appendChild(of: Tree.Position)` | Append as last child |
| Sendable, Equatable | |

#### Tree.Position

**File**: `Sources/Tree Primitives/Tree.Position.swift`

| Member | Description |
|--------|-------------|
| Sendable, Equatable, Hashable | Protocol conformances |
| Internal inits only (3 overloads) | Created by tree operations, not user-constructible |

---

## Gap Analysis

### Present and Correctly Mapped

| Canonical Operation | Implementation | Variants | Complexity |
|--------------------|----------------|----------|------------|
| insert(node, x) | `insert(_:at:)` | All 5 variants | O(1) amortized |
| remove (leaf) | `remove(at:)` | All 5 variants | O(1) |
| remove_subtree(node) | `removeSubtree(at:)` | All 5 variants | O(subtree size) |
| parent(node) | `parent(of:)` | All 5 variants | O(1) |
| child_at(slot) | `child(of:slot:)` (N) / `child(of:at:)` (Unbounded) | All 5 variants | O(1) |
| root | `var root: Tree.Position?` | All 5 variants | O(1) |
| is_leaf(node) | `isLeaf(_:)` | All 5 variants | O(1) |
| child_count | `childCount(of:)` | All 5 variants | O(1) |
| height | `var height: Count?` / `func height() -> Count?` | All 5 variants | O(n) |
| count/size | `var count: Count` | All 5 variants | O(1) |
| isEmpty | `var isEmpty: Bool` | All 5 variants | O(1) |
| clear | `clear()` | All 5 variants | O(n) |
| is_full | `var isFull: Bool` | Bounded, Inline | O(1) |
| pre-order | `forEachPreOrder(_:)` + `preOrder` sequence | All 5 variants (closure); N, Bounded (sequence) | O(n) |
| post-order | `forEachPostOrder(_:)` + `postOrder` sequence | All 5 variants (closure); N, Bounded (sequence) | O(n) |
| level-order (BFS) | `forEachLevelOrder(_:)` + `levelOrder` sequence | All 5 variants (closure); N, Bounded (sequence) | O(n) |
| in-order | `forEachInOrder(_:)` + `inOrder` sequence | N, Bounded, Inline, Small when n==2 (closure); N, Bounded when n==2 (sequence) | O(n) |
| element access | `peek(at:)` / `peek(at:_:)` | All 5 variants | O(1) |

### Additional Operations (Beyond Canonical)

| Operation | Variant | Description |
|-----------|---------|-------------|
| `leftmostChild(of:)` | Tree.N | First non-empty child slot |
| `rightmostChild(of:)` | Tree.N | Last non-empty child slot |
| `left(of:)` / `right(of:)` | Tree.N, Bounded, Inline, Small (n==2) | Binary convenience navigation |
| `firstChild(of:)` | Tree.Unbounded | First child (index 0) |
| `lastChild(of:)` | Tree.Unbounded | Last child |
| `.appendChild(of:)` | Tree.Unbounded | Append as last child |
| `var isSpilled: Bool` | Tree.N.Small | Whether storage moved to heap |
| `var arity: Int` (static) | Tree.N | Compile-time arity |
| `var capacity: Count` | Tree.N.Bounded | Maximum node capacity |
| CoW overloads for insert/peek | Tree.N, Bounded, Unbounded | Copy-on-write for Copyable elements |
| Sequence types (4 orders) | Tree.N, Bounded | Lazy traversal via Swift.Sequence |

These are all reasonable primitives-layer additions. The navigation shortcuts (`leftmostChild`, `rightmostChild`, `firstChild`, `lastChild`, binary `left`/`right`) are standard convenience operations found in most tree libraries.

---

### Missing -- Should Add (Primitives Layer)

#### 1. `leftmostChild(of:)` / `rightmostChild(of:)` on Bounded, Inline, Small

**Current state**: `leftmostChild(of:)` and `rightmostChild(of:)` are defined only on `Tree.N`. The Bounded, Inline, and Small variants lack these methods despite having the same sparse-slot child model.

**Recommendation**: Add `leftmostChild(of:)` and `rightmostChild(of:)` to `Tree.N.Bounded`, `Tree.N.Inline`, and `Tree.N.Small`.

**Rationale**: These are O(n) scans over at most `n` child slots (where n is the compile-time arity, typically 2-8). They express intent that would otherwise require the user to manually loop over `child(of:slot:)` for each slot. Since the slot count is bounded at compile time, these are pure navigation primitives with no policy.

#### 2. Traversal Sequence types for `Tree.Unbounded` (Copyable elements)

**Current state**: `Tree.N` and `Tree.N.Bounded` both expose `Order.Pre.Sequence`, `Order.Post.Sequence`, `Order.Level.Sequence` (and `Order.In.Sequence` for n==2) with corresponding `preOrder`, `postOrder`, `levelOrder`, `inOrder` properties. `Tree.Unbounded` has only closure-based traversal (`forEachPreOrder`, etc.) and no sequence types.

**Recommendation**: Add `Tree.Unbounded.Order` namespace with `Pre`, `Post`, and `Level` sequence types and corresponding traversal properties for `Element: Copyable`.

**Rationale**: `Tree.Unbounded` supports `Copyable` elements and has copy-on-write semantics. The closure-based `forEach*` traversals already implement the iteration logic. Sequence types provide composability (`map`, `filter`, `reduce`, `prefix`, `lazy`) that closure-based traversal cannot. This is a gap in API parity between `Tree.N`/`Tree.N.Bounded` and `Tree.Unbounded`.

#### 3. `isFull` on `Tree.N.Small`

**Current state**: `Tree.N.Bounded` and `Tree.N.Inline` both expose `var isFull: Bool`. `Tree.N.Small` does not, despite having a finite inline capacity before spill.

**Ambiguity**: "Full" has two possible meanings for Small: (a) inline capacity exhausted (about to spill), or (b) never full (can always grow after spill). If interpretation (a) is useful, it should be `var isInlineFull: Bool`. If (b), then absence is correct.

**Recommendation**: No action needed. After spill, Small behaves like a growable tree. The `isSpilled` property already communicates the inline-to-heap transition. Adding `isFull` would be misleading since the tree can always accept more nodes.

#### 4. `depth(of:)` -- Depth of a Specific Node

**Current state**: No variant provides `depth(of: Tree.Position) -> Count?` (distance from root to the given node).

**Recommendation**: Add `depth(of:)` to all variants.

**Rationale**: Depth is a fundamental tree metric distinct from height. It is computable in O(depth) time by walking parent pointers, which the tree already stores. Every tree algorithms textbook lists depth alongside height as a core operation. The parent-pointer chain makes this trivially implementable without any new storage.

#### 5. `sibling(of:)` / `nextSibling(of:)` -- Sibling Navigation

**Current state**: No variant provides sibling navigation. Given a position, there is no way to navigate to the next/previous sibling without going up to the parent and then back down.

**Recommendation**: Consider adding `nextSibling(of:)` and `previousSibling(of:)` for `Tree.N` variants (where sibling order is defined by slot indices), and `nextSibling(of:)`/`previousSibling(of:)` for `Tree.Unbounded` (where sibling order is defined by child array index).

**Rationale**: Sibling navigation is a common operation in DOM traversal, file system trees, and XML processing. It is implementable in O(n) for bounded arity (scan parent's child slots) and O(k) for unbounded (find index in parent's child array). This is a borderline primitives-layer operation -- it could also live in foundations. If added, it should follow the existing navigation pattern (return `Tree.Position?`, return `nil` if no next/previous sibling exists).

**Priority**: Low. The operation is expressible via `parent(of:)` + `child(of:slot:)` composition. Adding it is a convenience, not a capability gap.

---

### Missing -- Intentionally Absent (Higher Layer)

| Operation | Why Not Primitives |
|-----------|--------------------|
| `contains(_:)` / `find(_:)` | Requires `Equatable` constraint, which is policy. Search strategies (DFS vs BFS) are also policy. Belongs in foundations. |
| `map(_:)` / `flatMap(_:)` | Tree-structural map (preserving shape) is a higher-order operation. The primitives layer provides traversal; transformation belongs in foundations. |
| `subtree(at:)` | Extracting a subtree as a new tree requires deep copy with index remapping. This is a composition operation, not a primitive. |
| `merge(_:at:)` | Merging two trees is a structural operation with multiple valid strategies. Belongs in foundations. |
| `rotate(at:)` / `balance()` | Self-balancing is search-tree-specific (AVL, Red-Black). The general tree ADT does not define balance operations. |
| `ancestor(of:where:)` | Filtered ancestor search is a query operation. Expressible via `parent(of:)` iteration. |
| `lowestCommonAncestor(_:_:)` | LCA algorithms require either preprocessing (Euler tour, sparse table) or O(depth) walks. The O(depth) walk is expressible via `parent(of:)`. Optimized LCA is an algorithm, not a primitive. |
| `serialize()` / `deserialize(_:)` | Encoding is IO-layer concern. |
| `description` / `debugDescription` | Text rendering of tree structure is presentation concern. |
| Collection conformance | Trees are not linear collections. Sequence conformance (for specific traversal orders) is already provided. |

---

## Consistency Observations

### 1. `height` Is a Property on N/Bounded/Unbounded but a Method on Inline/Small

| Variant | Declaration |
|---------|-------------|
| Tree.N | `public var height: Count?` (computed property) |
| Tree.N.Bounded | `public var height: Count?` (computed property) |
| Tree.Unbounded | `public var height: Count?` (computed property) |
| Tree.N.Inline | `public mutating func height() -> Count?` (method) |
| Tree.N.Small | `public mutating func height() -> Count?` (method) |

This divergence is forced by the inline arena requiring `mutating` access for pointer operations. Computed properties cannot be `mutating` in Swift. The inconsistency is a Swift language constraint, not a design flaw.

### 2. Navigation Is Non-Mutating on N/Bounded/Unbounded but Mutating on Inline/Small

Same root cause: inline arena storage requires `mutating` access. This is documented and expected behavior for `~Copyable` inline storage types.

### 3. `childCount(of:)` Returns `Count?` on N Variants but `Int?` on Unbounded

`Tree.Unbounded.childCount(of:)` returns `Int?` while all `Tree.N` variants return `Count?` (which is `Index<Node>.Count`). This is tracked in `tree-typed-remediation.md` and will be resolved when `Tree.Unbounded`'s bare-Int usage is remediated.

### 4. Sequence Types: N and Bounded Have Them, Unbounded Does Not

As noted in the gap analysis above, `Tree.Unbounded` lacks `Order` namespace and sequence-based traversal. This is the largest API parity gap.

### 5. `Tree.Unbounded.Bounded` and `Tree.Unbounded.Small` Existence

Error types exist for both (`__TreeUnboundedBoundedError`, `__TreeUnboundedSmallError`), but the struct definitions were not found in the source files. These may be planned but not yet implemented, or they may exist in files not yet created. If not yet implemented, they represent a completeness gap in the variant matrix.

---

## Variant Completeness Matrix

| Operation | N | Bounded | Inline | Small | Unbounded |
|-----------|---|---------|--------|-------|-----------|
| init() | Y | Y (capacity:) | Y | Y | Y |
| init(minimumCapacity:) | Y | -- | -- | -- | Y |
| count | Y | Y | Y | Y | Y |
| isEmpty | Y | Y | Y | Y | Y |
| root | Y | Y | Y | Y | Y |
| isFull | -- | Y | Y | -- | -- |
| capacity | -- | Y | -- | -- | -- |
| isSpilled | -- | -- | -- | Y | -- |
| arity (static) | Y | -- | -- | -- | -- |
| height | Y | Y | Y | Y | Y |
| insert | Y | Y | Y | Y | Y |
| remove (leaf) | Y | Y | Y | Y | Y |
| removeSubtree | Y | Y | Y | Y | Y |
| clear | Y | Y | Y | Y | Y |
| peek (closure) | Y | Y | Y | Y | Y |
| peek (copy) | Y | Y | Y | Y | Y |
| child(of:slot:) | Y | Y | Y | Y | Y* |
| parent(of:) | Y | Y | Y | Y | Y |
| isLeaf | Y | Y | Y | Y | Y |
| childCount(of:) | Y | Y | Y | Y | Y |
| leftmostChild(of:) | Y | -- | -- | -- | -- |
| rightmostChild(of:) | Y | -- | -- | -- | -- |
| firstChild(of:) | -- | -- | -- | -- | Y |
| lastChild(of:) | -- | -- | -- | -- | Y |
| left(of:) (n==2) | Y | Y | Y | Y | -- |
| right(of:) (n==2) | Y | Y | Y | Y | -- |
| forEachPreOrder | Y | Y | Y | Y | Y |
| forEachPostOrder | Y | Y | Y | Y | Y |
| forEachLevelOrder | Y | Y | Y | Y | Y |
| forEachInOrder (n==2) | Y | Y | Y | Y | -- |
| preOrder (Sequence) | Y | Y | -- | -- | -- |
| postOrder (Sequence) | Y | Y | -- | -- | -- |
| levelOrder (Sequence) | Y | Y | -- | -- | -- |
| inOrder (Sequence, n==2) | Y | Y | -- | -- | -- |
| Copyable conformance | cond. | cond. | never | never | cond. |
| Sendable conformance | cond. | cond. | cond. | cond. | cond. |
| depth(of:) | -- | -- | -- | -- | -- |

`*` Unbounded uses `child(of:at:)` with `Int` index instead of `ChildSlot`.

---

## Outcome

**Status**: RECOMMENDATION

### Summary

swift-tree-primitives provides **all canonical Tree ADT operations** across its five variants. The coverage is thorough: insert, remove (leaf and subtree), navigation (parent, child, root), introspection (isLeaf, childCount, height, count, isEmpty), clear, element access, and all four standard traversal orders.

### Prioritized Recommendations

1. **Add `leftmostChild(of:)` / `rightmostChild(of:)` to Bounded, Inline, Small** -- Low effort, high consistency value. These are copy-paste from Tree.N with variant-appropriate arena access.

2. **Add traversal Sequence types to `Tree.Unbounded`** -- Medium effort, high API parity value. Mirrors the existing `Tree.N.Order` / `Tree.N.Bounded.Order` infrastructure.

3. **Add `depth(of:)` to all variants** -- Low effort, fills a canonical ADT gap. Walk parent pointers, count steps.

4. **Verify `Tree.Unbounded.Bounded` and `Tree.Unbounded.Small` struct existence** -- If only error types exist, implement the structs or remove the error types to avoid dead code.

5. **(Low priority) Consider sibling navigation** -- Useful but expressible via existing operations. Defer unless demanded by a consumer.
