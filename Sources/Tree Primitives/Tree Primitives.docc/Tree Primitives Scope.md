# Tree Primitives Scope

`swift-tree-primitives` provides the **tree-family substrate + the canonical
dynamic (unbounded-arity) tree**. It owns the `Tree<S>` ADT namespace (a thin
generic over an explicit storage column `S`, per `[DS-025]`), the shared
generational arena every column is built on, the storage and consumer seam
protocols, the column-agnostic algorithm engine, and the dense-list dynamic
column (`TreeStorage.Dynamic`, the canonical `Tree<Element>` front door). The
bounded-arity n-ary column and the keyed column are their own sibling packages
(`swift-tree-n-primitives`, `swift-tree-keyed-primitives`), each conforming the
shared `__TreeStorage` capability and reusing this package's arena + engine.

## Per-[MOD-031] shape

The package follows `[MOD-031]` per-sub-namespace decomposition: `Tree Primitive`
is the layer-invariant namespace target per `[MOD-017]`, and each concern is its
own target. There is no `Tree Primitives Core` implementation target — the legacy
`[MOD-001]` Core convention is deprecated; the `Tree Primitives Core` library now
survives only as a time-boxed exports-only shim (re-exports the dissolved surface
so `tree-keyed` / `tree-n` / `BuildAll` keep resolving until the L1
core-dissolution cleanup wave, 2026-06-23).

## Owner targets

- **Tree Primitive** — the `public struct Tree<S: ~Copyable>` ADT namespace
  target (plus its column-flowing `Copyable` / `Sendable` conformances). Zero
  external dependencies per `[MOD-017]`'s invariant.
- **Tree Index Primitives** — the typed-addressing + seam foundation: `Tree.Index`
  / `Tree.Position` (over `Index_Primitives`), the shared `Tree.Error`
  (`__TreeError`) and insert-position (`__TreeInsertPosition`), and the two hoisted
  seam protocols — the storage capability `__TreeStorage` (the contract storage
  columns conform) and the consumer protocol `Tree.Protocol` (`__TreeProtocol`,
  which `Tree<S>` conforms). Depends on the root.
- **Tree Storage Primitives** — the concrete storage: the shared generational
  arena (`__TreeArena` over `Shared<Node, Column.Generational<Node>>`), its node
  (`__TreeNode`), the `TreeStorage` column namespace, and the canonical dynamic
  dense-list column `TreeStorage.Dynamic` (with the canonical `Tree<Element>` front door) conforming
  `__TreeStorage`. Depends on the root + Index.
- **Tree Operations Primitives** — the de-dup algorithm engine written once on
  `Tree<S>` (traversal, insert / remove / removeSubtree, height, navigation), the
  additive `Tree<S>: Tree.Protocol` conformance, and the read-only `tree.forEach.*`
  / `tree.child.*` fluent views (over `Property<Tag, Base>.Borrow`). Depends on the
  root + Index.
- **Tree Primitives** — umbrella; re-exports the root + all three sub-namespaces so
  consumers needing the union write `import Tree_Primitives` (`[MOD-005]`).
- **Tree Primitives Core** — DEPRECATED transitional shim (exports-only); removed in
  the cleanup wave.
- **Tree Primitives Test Support** — published test-fixtures product.

## Out of scope (siblings)

Each specialized tree column is its own sibling package. Each USES the `Tree`
namespace + the shared arena + seams + engine from this package and supplies its
own storage column.

- `TreeStorage.N` (bounded-arity n-ary column, sparse slots) → `swift-tree-n-primitives`
- `TreeStorage.Keyed` (keyed column, ordered key→child dictionary) → `swift-tree-keyed-primitives`

## Evaluation rule

Sub-target additions are evaluated against this scope.

- A proposed addition that is a **specialized storage column** — a distinct
  child-addressing / arity discipline (bounded n-ary, keyed, …) — extracts to a
  sibling package conforming `__TreeStorage`, not into this one.
- A proposed addition that is **shared substrate** (the `Tree` namespace, the
  arena, the seam protocols, the column-agnostic engine) or part of the
  **canonical dynamic column** lands as / within the matching sub-namespace target,
  per `[MOD-031]`.
