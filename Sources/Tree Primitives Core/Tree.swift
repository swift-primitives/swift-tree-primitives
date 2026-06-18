// ===----------------------------------------------------------------------===//
//
// This source file is part of the swift-primitives open source project
//
// Copyright (c) 2024-2026 Coen ten Thije Boonkkamp and the swift-primitives project authors
// Licensed under Apache License v2.0
//
// See LICENSE for license information
//
// ===----------------------------------------------------------------------===//

// MARK: - Tree (the ADT tier — generic over the STORAGE COLUMN, per [DS-025])

/// A tree — the semantic ADT over an explicit storage COLUMN `S`.
///
/// The Charter at-target shape ([DS-025]): `Tree` is a thin generic over its storage
/// column `S`, bound `~Copyable` **only** — no storage-protocol bound on the type.
/// Capabilities attach by CONDITIONAL EXTENSION keyed on what `S` supports
/// (`extension Tree where S: __TreeStorage`), and `Tree<S>` ADDITIVELY conforms its own
/// consumer protocol `Tree.Protocol` (`extension Tree: Tree.Protocol where S:
/// __TreeStorage`). The storage `S` never conforms `Tree.Protocol`; only `Tree<S>` does
/// — the exact `Array<S>` / `Buffer<S>` model.
///
/// Copyability **flows from the column**: `Tree<S>` is `Copyable` exactly when `S` is.
/// The ADT carries no `deinit` — teardown lives in the column's `__TreeArena` (the
/// `Shared` CoW box drain / generational column).
///
/// The shipped columns are the dynamic dense-list column (``Tree/Dynamic``, this
/// package), the bounded-arity n-ary column (`swift-tree-n-primitives`) and the keyed
/// column (`swift-tree-keyed-primitives`); the canonical dynamic tree is the
/// ``TreeDynamic`` ergonomic alias.
///
/// ## Example
///
/// ```swift
/// var tree = TreeDynamic<String>()                 // = Tree<Tree.Dynamic<String>>
/// let root = try tree.insert("root", at: .root)
/// let child = try tree.insert("child", at: .child(of: root, at: 0))
/// tree.forEach.preOrder { print($0) }              // root, child
/// ```
@frozen
public struct Tree<S: ~Copyable> {

    /// The storage column — the arena + child-link capability the tree is a thin
    /// semantic discipline over. Carries the per-node arena (`__TreeArena`) and the
    /// per-column child-link interpretation.
    @usableFromInline
    package var storage: S

    /// Wraps an existing storage column.
    @inlinable
    public init(storage: consuming S) {
        self.storage = storage
    }

    /// Consumes the tree, yielding its storage column.
    @inlinable
    public consuming func take() -> S {
        storage
    }
}

// MARK: - Conditional Conformances (copyability + Sendability flow from the column)

extension Tree: Copyable where S: Copyable {}

extension Tree: Sendable where S: Sendable & ~Copyable {}

// MARK: - Column-agnostic typealiases (no `S` capture — the Set.Ordered namespaced pattern)

extension Tree {

    /// The error type for the shared tree operations.
    public typealias Error = __TreeError

    /// The tree consumer abstraction — the canonical surfacing of ``__TreeProtocol``
    /// (the `Array.Protocol` pattern). `Tree<S>` conforms it where `S: __TreeStorage`.
    public typealias `Protocol` = __TreeProtocol
}

// MARK: - Ergonomic alias for the canonical dynamic tree
//
// Top-level (NOT namespaced as a generic typealias under `Tree<S>` — that crashes the
// 6.3.2 frontend, probe-confirmed) so users and tests write `TreeDynamic<Element>` for
// the canonical `Tree<TreeStorage.Dynamic<Element>>`.

/// The canonical dynamic (unbounded-arity) tree: `Tree` over the dense `[Handle]` column.
///
/// ```swift
/// var tree = TreeDynamic<String>()
/// let root = try tree.insert("root", at: .root)
/// ```
public typealias TreeDynamic<Element: ~Copyable> = Tree<TreeStorage.Dynamic<Element>>
