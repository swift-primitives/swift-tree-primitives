# Tree Primitives

![Development Status](https://img.shields.io/badge/status-active--development-blue.svg)
[![CI](https://github.com/swift-primitives/swift-tree-primitives/actions/workflows/ci.yml/badge.svg)](https://github.com/swift-primitives/swift-tree-primitives/actions/workflows/ci.yml)

A tree generic over its storage **column** — the carrier writes the node-shape-agnostic surface (insert, remove, subtree teardown, traversal, navigation) once against the column seam, and copyability flows from the column rather than from per-tree machinery. The shipped column is `TreeStorage.Dynamic<Element>`, a dense ordered-children arena; `Tree<Element>` names the canonical dynamic tree built on it.

Positions are generational: `Tree.Position` carries a slot index plus a generation token, so a position held across a removal goes *stale* and is rejected — it can never silently resolve to whatever node later reuses the freed slot. Elements may be `~Copyable`; with a `Copyable` element the dynamic tree is copy-on-write, so copies fork lazily and mutate independently.

---

## Key Features

- **Column-generic engine** — one `Tree<S>` type; the shared operations attach by conditional extension on the storage seam, so alternative columns plug in without re-implementing the algorithms.
- **Generational positions** — stale positions throw or return `nil` instead of aliasing a recycled slot; positions survive unrelated growth and in-place element mutation.
- **Noncopyable elements** — borrowing element access via `peek(at:)` closures and in-place mutation via `withElementMut(at:)`, with no requirement that elements be copyable.
- **Copyability from the column** — move-only by default; opt into copy-on-write value semantics simply by storing a `Copyable` element.
- **Read-only fluent views** — `tree.forEach.preOrder { }` / `.postOrder` / `.levelOrder` and `tree.child.at(_:of:)` / `.count(of:)` / `.leftmost(of:)` / `.rightmost(of:)`, callable on a `let` or borrowed tree.
- **Typed throws end-to-end** — every failing operation throws `Tree.Error`; consumers can match exhaustively without `any Error`.

---

## Quick Start

```swift
import Tree_Primitives

var tree = Tree<String>()
let root = try tree.insert("root", at: .root)
let draft = try tree.insert("draft", at: .child(of: root, at: 0))
_ = try tree.insert("published", at: .child(of: root, at: 1))

var visited: [String] = []
tree.forEach.preOrder { visited.append($0) }    // ["root", "draft", "published"]

// Positions are generational: removal invalidates the position rather than
// letting it alias whatever node reuses the freed slot.
try tree.remove(at: draft)
let recovered = tree.peek(at: draft)            // nil — stale position rejected
```

---

## Installation

Add the dependency to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/swift-primitives/swift-tree-primitives.git", branch: "main")
]
```

Add a product to your target:

```swift
.target(
    name: "App",
    dependencies: [
        .product(name: "Tree Primitives", package: "swift-tree-primitives")
    ]
)
```

The package is pre-1.0 — depend on `branch: "main"` until `0.1.0` is tagged. Requires Swift 6.3 and macOS 26 / iOS 26 / tvOS 26 / watchOS 26 / visionOS 26 (or the corresponding Linux / Windows toolchain).

---

## Architecture

| Product | When to import |
|---------|----------------|
| `Tree Primitives` | Umbrella — the ADT, positions and errors, the dynamic column, and the traversal / navigation views |
| `Tree Primitive` | The bare column-generic carrier value type, zero dependencies — column authors and minimal consumers |
| `Tree Index Primitives` | `Tree.Position`, `Tree.Error`, insert positions, and the storage / consumer seam protocols — writing code generic over tree-like storage |
| `Tree Storage Primitives` | The dynamic column (`TreeStorage.Dynamic`) and the canonical `Tree<Element>` front door, without the operations surface |
| `Tree Operations Primitives` | The shared algorithm engine and the `forEach` / `child` views |
| `Tree Primitives Test Support` | Test utilities for targets exercising tree code |

---

## Error Handling

Every throwing operation throws `Tree.Error`:

```
Tree.Error
├── .invalidPosition        // The position is stale or out of bounds
├── .rootOccupied           // Root insert attempted on a non-empty tree
├── .slotOccupied           // A child slot is already occupied (bounded-arity / keyed columns)
├── .childIndexOutOfBounds  // Child index above the parent's current child count (dynamic column)
└── .cannotRemoveNonLeaf    // remove(at:) on an interior node — use removeSubtree(at:)
```

Typed throws make exhaustive handling checkable:

```swift
do {
    try tree.insert(item, at: .child(of: parent, at: 3))
} catch .invalidPosition {
    // `parent` went stale — its node was removed
} catch .rootOccupied, .slotOccupied {
    // The insert target is already filled
} catch .childIndexOutOfBounds {
    // Dynamic column: the index must be at most the current child count
} catch .cannotRemoveNonLeaf {
    // Raised by remove(at:), not insert — removeSubtree(at:) tears down interior nodes
}
```

---

## Platform Support

| Platform                  | CI  | Status    |
|---------------------------|-----|-----------|
| macOS 26                  | Yes | Full support |
| Linux                     | Yes | Supported |
| Windows                   | Yes | Supported |
| iOS/tvOS/watchOS/visionOS | —   | Supported |
| Swift Embedded            | —   | Untested  |

---

## Related Packages

### Dependencies

- [`swift-index-primitives`](https://github.com/swift-primitives/swift-index-primitives) — the typed index / count vocabulary behind positions and node counts.
- [`swift-storage-generational-primitives`](https://github.com/swift-primitives/swift-storage-generational-primitives) — the generational handles that make stale positions detectable.
- [`swift-storage-primitives`](https://github.com/swift-primitives/swift-storage-primitives) — the store vocabulary the arena is expressed in.
- [`swift-column-primitives`](https://github.com/swift-primitives/swift-column-primitives) — the storage-column vocabulary the arena composes.
- [`swift-shared-primitives`](https://github.com/swift-primitives/swift-shared-primitives) — the copy-on-write box behind the copyable tree.
- [`swift-property-primitives`](https://github.com/swift-primitives/swift-property-primitives) — the borrowing accessor mechanism behind the `forEach` / `child` views.
- [`swift-stack-primitives`](https://github.com/swift-primitives/swift-stack-primitives), [`swift-queue-primitives`](https://github.com/swift-primitives/swift-queue-primitives), [`swift-buffer-ring-primitives`](https://github.com/swift-primitives/swift-buffer-ring-primitives) — the work-list containers driving the iterative traversals.

### Variants

- swift-tree-n-primitives (private, unreleased) — the bounded-arity column over the same seam.
- swift-tree-keyed-primitives (private, unreleased) — the keyed (children-by-key) column over the same seam.

---

## Community

<!-- BEGIN: discussion -->
*Discussion thread will be created at first public release.*
<!-- END: discussion -->

## License

Apache 2.0. See [LICENSE.md](LICENSE.md).
