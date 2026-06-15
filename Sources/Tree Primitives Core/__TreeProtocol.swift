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

public import Storage_Generational_Primitives
public import Store_Primitive

// MARK: - Tree.Protocol — the OPERATION-requirement abstraction (the Array.Protocol pattern)
//
// `__TreeProtocol` is the additive abstraction the tree variants CONFORM TO
// (mirroring `Array.Protocol` / `__ArrayProtocol`). Its requirements are
// OPERATIONS — decode, node-at-handle, child-link read/set, arena access — never
// raw storage: a conformer implements them over its OWN private `Tree.Storage`,
// and the shared defaults (`__TreeProtocol+Defaults.swift`) orchestrate
// insert / remove / navigation / traversal via these requirements ALONE. The
// abstraction never sees a conformer's storage, so storage stays non-public.
//
// Ruling 12: this is the SANCTIONED additive-abstraction kind (a conformance
// target + generic bound, mirroring `Array.Protocol`), NOT a composition bound —
// there is no `Tree<S: __TreeProtocol>` generic type.
//
// Hoisted per [API-EXC-001]; use ``Tree/Protocol`` in your code.

/// Hoisted implementation of the tree abstraction.
///
/// The shared operation seam for the tree family. Conformers
/// (`Tree` / `Tree.N` / `Tree.Keyed`) implement the operation
/// requirements over a private `Tree.Storage`; the shared defaults provide the
/// node-shape-agnostic tree algorithms.
///
/// - Note: Use ``Tree/Protocol`` in your code, not this type directly.
public protocol __TreeProtocol: ~Copyable {

    /// The element stored at each node (may be `~Copyable`).
    associatedtype Element: ~Copyable

    /// How a child is addressed within its parent: a child index (dynamic), a
    /// bounded slot (n-ary), or a key (keyed).
    associatedtype Address

    // MARK: Arena requirements (the conformer delegates to its private Tree.Storage)

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

    // MARK: Child-link requirements (genuinely per-conformer)

    /// The handle of the child at `address`, or `nil` if absent.
    func _childHandle(
        at handle: Store.Generational.Handle,
        address: Address
    ) -> Store.Generational.Handle?

    /// Validates that a child link at `address` under `parent` is permissible
    /// BEFORE any node is inserted — the per-conformer error precision flows here
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

// MARK: - Shared surfaced typealiases

extension __TreeProtocol where Self: ~Copyable {
    /// Where to insert a new node, addressed per the conformer's `Address`.
    public typealias InsertPosition = __TreeInsertPosition<Address>
}
