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

public import Index_Primitives
public import Storage_Generational_Primitives
public import Store_Primitive

// MARK: - __TreeStorage — the STORAGE CAPABILITY (the Store.Protocol analog for trees)
//
// The Charter at-target reshape ([DS-025]): `Tree<S: ~Copyable>` is a thin generic over
// its storage column `S`, and `S` is what carries the tree's per-node arena + child-link
// CAPABILITY. `__TreeStorage` is that capability — the protocol the STORAGE COLUMNS
// conform to (NOT the tree types). It is the re-roled former `__TreeProtocol` operation
// seam: the same arena (decode / node-at-handle / arena access) + child-link
// (read / set / count / iterate) `_`-ops, now required of the column rather than the ADT.
//
// `Tree<S>` attaches its operations by CONDITIONAL EXTENSION keyed on this capability
// (`extension Tree where S: __TreeStorage`), forwarding to `storage._x`; and `Tree<S>`
// ADDITIVELY conforms the consumer protocol `Tree.Protocol` (`__TreeProtocol`) where
// `S: __TreeStorage`. The storage `S` never conforms `Tree.Protocol`; only `Tree<S>` does
// (the `__ArrayProtocol` / `Store.Protocol` split).
//
// Hoisted per [API-EXC-001] (a protocol cannot nest in the generic `Tree<S>`); the
// capability has no consumer-facing alias — columns conform `__TreeStorage` directly.

/// The storage-column capability for the tree family.
///
/// A column conforms `__TreeStorage` by implementing the per-node arena + child-link
/// operations over its own private ``__TreeArena``. The three shipped columns are the
/// dynamic dense-list column (``Tree/Dynamic``, this package), the n-ary sparse-slot
/// column (swift-tree-n-primitives) and the keyed column (swift-tree-keyed-primitives).
///
/// - Note: This is the STORAGE seam. Generic tree consumers constrain on
///   ``Tree/Protocol`` (which `Tree<S>` conforms), never on this capability.
public protocol __TreeStorage: ~Copyable {

    /// The element stored at each node (may be `~Copyable`).
    associatedtype Element: ~Copyable

    /// How a child is addressed within its parent: a child index (dynamic), a
    /// bounded slot (n-ary), or a key (keyed).
    associatedtype Address

    // MARK: Arena requirements (delegated to the column's private __TreeArena)

    /// The number of live nodes (typed — A3; tagged by `Element`, one per node).
    var _count: Index_Primitives.Index<Element>.Count { get }

    /// The handle of the root node, or `nil` if the tree is empty.
    var _rootHandle: Store.Generational.Handle? { get set }

    /// Decodes a position into its live handle, or `nil` if stale/out-of-bounds.
    func _liveHandle(_ position: __TreePosition) -> Store.Generational.Handle?

    /// Inserts a node with no children yet and the given parent; returns its handle.
    mutating func _insertNode(
        _ element: consuming Element,
        parent: Store.Generational.Handle?
    ) -> Store.Generational.Handle

    /// Removes the node at a live handle and moves its element out.
    mutating func _removeNode(_ handle: Store.Generational.Handle) -> Element

    /// Removes every node and resets the root.
    mutating func _removeAll()

    /// The parent handle of a node (`nil` for the root).
    func _parentHandle(of handle: Store.Generational.Handle) -> Store.Generational.Handle?

    /// Borrowing access to a node's element.
    func _withElement<R: ~Copyable>(
        at handle: Store.Generational.Handle,
        _ body: (borrowing Element) -> R
    ) -> R

    /// In-place (position-stable) mutating access to a node's element.
    ///
    /// The slot and its generation are untouched — only the stored element changes —
    /// so positions minted before the mutation keep resolving. Backs the value-update
    /// surfaces (the keyed tree's `update(at:)` / `rootValue` setter / `mapValues`).
    mutating func _withElementMut<R: ~Copyable>(
        at handle: Store.Generational.Handle,
        _ body: (inout Element) -> R
    ) -> R

    // MARK: Child-link requirements (genuinely per-column)

    /// The handle of the child at `address`, or `nil` if absent.
    func _childHandle(
        at handle: Store.Generational.Handle,
        address: Address
    ) -> Store.Generational.Handle?

    /// Validates that a child link at `address` under `parent` is permissible
    /// BEFORE any node is inserted — the per-column error precision flows here
    /// (`.childIndexOutOfBounds` / `.slotOccupied` / keyed). No mutation.
    func _validateLink(
        to parent: Store.Generational.Handle,
        at address: Address
    ) throws(__TreeError)

    /// Links `child` under `parent` at `address`. Precondition: a prior
    /// `_validateLink(to:at:)` succeeded, so this never fails.
    mutating func _linkChild(
        _ child: Store.Generational.Handle,
        to parent: Store.Generational.Handle,
        at address: Address
    )

    /// Unlinks `child` from `parent`'s child links.
    mutating func _unlinkChild(
        _ child: Store.Generational.Handle,
        from parent: Store.Generational.Handle
    )

    /// The number of children of a node.
    func _childCount(at handle: Store.Generational.Handle) -> Int

    /// Calls `body` for each child handle of a node, in child order.
    func _forEachChild(
        at handle: Store.Generational.Handle,
        _ body: (Store.Generational.Handle) -> Void
    )
}
