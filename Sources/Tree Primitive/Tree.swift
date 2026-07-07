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

// MARK: - __Tree (the hoisted ADT-tier CARRIER — generic over the STORAGE COLUMN, [DS-025])

/// A tree — the semantic ADT carrier over an explicit storage COLUMN `S`.
///
/// The Charter at-target shape ([DS-025]): `__Tree` is the HOISTED thin carrier
/// ([API-IMPL-009]), generic over its storage column `S`, bound `~Copyable` **only** —
/// no storage-protocol bound on the type. Capabilities attach by CONDITIONAL EXTENSION
/// keyed on what `S` supports (`extension __Tree where S: __TreeStorage`), and
/// `__Tree<S>` ADDITIVELY conforms its own consumer protocol `Tree.Protocol`
/// (`extension __Tree: Tree.Protocol where S: __TreeStorage`). The storage `S` never
/// conforms `Tree.Protocol`; only the carrier does — the exact `__Array` / `Buffer<S>`
/// model.
///
/// Consumers never spell the carrier: the canonical front door is the `Tree<Element>`
/// alias over the dynamic column ([DS-028], `Tree Storage Primitives`); the keyed
/// column's door is `Tree<Element>.Keyed<Key>` (swift-tree-keyed-primitives).
///
/// Copyability **flows from the column**: `__Tree<S>` is `Copyable` exactly when `S` is.
/// The ADT carries no `deinit` — teardown lives in the column's `__TreeArena` (the
/// `Shared` CoW box drain / generational column).
///
/// The shipped columns are the dynamic dense-list column (``Tree/Dynamic``, this
/// package) and the keyed column (`swift-tree-keyed-primitives`); the bounded-arity
/// n-ary column (`swift-tree-n-primitives`) is pending its column re-skeleton.
///
/// ## Example
///
/// ```swift
/// var tree = Tree<String>()                        // = __Tree<TreeStorage.Dynamic<String>>
/// let root = try tree.insert("root", at: .root)
/// let child = try tree.insert("child", at: .child(of: root, at: 0))
/// tree.forEach.preOrder { print($0) }              // root, child
/// ```
///
/// - Note: This zero-dependency root owns the column-agnostic ADT only ([MOD-017]). The
///   typed `Index` / `Position` / `Error` / `Protocol` namespaced aliases attach by
///   extension from the sub-namespace that owns each referenced type
///   (`Tree Index Primitives`, `Tree Operations Primitives`); the canonical `Tree<Element>`
///   front-door alias is supplied by `Tree Storage Primitives` (it names the dynamic column,
///   which the zero-dep root cannot).
@_documentation(visibility: public)  // symbolgraph-extract drops __-prefixed decls otherwise (§9.6.12)
@frozen
public struct __Tree<S: ~Copyable> {

    /// The storage column — the arena + child-link capability the tree is a thin
    /// semantic discipline over.
    ///
    /// Carries the per-node arena (`__TreeArena`) and the
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

// MARK: - Column-access seam (for column-specific extensions in OTHER packages)
//
// `__Tree<S>` hides its `storage` (package access), so a column author in a SEPARATE
// package (the keyed / n-ary variants) cannot attach carrier-surface operations that
// reach column-specific capabilities — key-path navigation, in-place value update, the
// keyed children-by-key reads. This public `_read`/`_modify` accessor is the sanctioned
// door: it borrows / mutably-yields the column without copying (so it carries `~Copyable`
// columns), the `__Array.storage`-equivalent seam. SPI-spelled (`_`-prefixed) — generic
// consumers stay on the public ADT surface; only a column's own package reaches through.

extension __Tree where S: ~Copyable {

    /// Borrowing / mutating access to the storage column.
    ///
    /// The seam a column's own package uses to attach carrier-surface operations that
    /// reach column-specific capabilities (e.g. the keyed tree's `keyPath(to:)` /
    /// `update`). Yields without copying, so it carries `~Copyable` columns.
    @inlinable
    public var _storage: S {
        _read { yield storage }
        _modify { yield &storage }
    }
}

// MARK: - Conditional Conformances (copyability + Sendability flow from the column)

extension __Tree: Copyable where S: Copyable {}

extension __Tree: Sendable where S: Sendable & ~Copyable {}
