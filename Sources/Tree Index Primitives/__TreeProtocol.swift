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
public import Tree_Primitive

// MARK: - Tree.Protocol — the CONSUMER protocol (the Array.Protocol / __ArrayProtocol analog)
//
// The Charter at-target reshape ([DS-025]): the carrier `__Tree<S>` ADDITIVELY conforms
// its own consumer-facing protocol `Tree.Protocol` (`extension __Tree: __TreeProtocol
// where S: __TreeStorage`), exactly as `__Array` conforms `Array.Protocol`. The STORAGE
// column `S` never conforms `Tree.Protocol` — it conforms the SEPARATE storage capability
// ``__TreeStorage``; only the carrier conforms this consumer protocol.
//
// This protocol is the seam GENERIC CONSUMERS and the shared `Property.Borrow` views
// (`tree.forEach.*`, `tree.child.*`) constrain on. Its requirements are the navigation /
// traversal / element-access operations `Tree<S>` supplies through its conditional
// extensions (`__TreeProtocol+Operations.swift`); the views and generic algorithms reach
// them through this protocol without knowing the column.
//
// Hoisted per [API-EXC-001] (a protocol cannot nest in the generic `Tree<S>`); use
// ``Tree/Protocol`` in your code.

/// Hoisted implementation of the tree consumer abstraction.
///
/// The consumer-facing seam for the tree family. `Tree<S>` conforms it conditionally
/// (`where S: __TreeStorage`); generic functions and the shared `tree.forEach.*` /
/// `tree.child.*` views constrain on it.
///
/// - Note: Use ``Tree/Protocol`` in your code, not this type directly.
public protocol __TreeProtocol: ~Copyable {

    /// The element stored at each node (may be `~Copyable`).
    associatedtype Element: ~Copyable

    /// How a child is addressed within its parent: a child index (dynamic), a
    /// bounded slot (n-ary), or a key (keyed).
    associatedtype Address

    // MARK: Properties

    /// Whether the tree has no nodes.
    var isEmpty: Bool { get }

    /// The position of the root node, or `nil` if the tree is empty.
    var root: __TreePosition? { get }

    // MARK: Navigation / traversal seams (the view-facing requirements)

    /// Mints the public position for a live handle.
    func _position(of handle: Store.Generational.Handle) -> __TreePosition

    /// Decodes a position into its live handle, or `nil` if stale/out-of-bounds.
    func _liveHandle(_ position: __TreePosition) -> Store.Generational.Handle?

    /// The position of the child at `address`, or `nil` if absent / position invalid.
    func _child(of position: __TreePosition, at address: Address) -> __TreePosition?

    /// The number of children of a node.
    func _childCount(at handle: Store.Generational.Handle) -> Int

    /// Calls `body` for each child handle of a node, in child order.
    func _forEachChild(
        at handle: Store.Generational.Handle,
        _ body: (Store.Generational.Handle) -> Void
    )

    /// Borrowing access to a node's element.
    func _withElement<R: ~Copyable>(
        at handle: Store.Generational.Handle,
        _ body: (borrowing Element) -> R
    ) -> R

    /// Visits every element in pre-order (root, then children left-to-right).
    func _forEachPreOrder(_ body: (borrowing Element) -> Void)

    /// Visits every element in post-order (children left-to-right, then parent).
    func _forEachPostOrder(_ body: (borrowing Element) -> Void)

    /// Visits every element in level-order (breadth-first).
    func _forEachLevelOrder(_ body: (borrowing Element) -> Void)
}

// MARK: - Shared surfaced typealiases

extension __TreeProtocol where Self: ~Copyable {
    /// Where to insert a new node, addressed per the conformer's `Address`.
    public typealias InsertPosition = __TreeInsertPosition<Address>
}

// MARK: - Tree.Protocol — the column-agnostic namespaced alias
//
// The zero-dependency root `__Tree<S>` (`Tree Primitive`) cannot name `__TreeProtocol`,
// so the consumer-protocol alias attaches by extension from this sub-namespace.

extension __Tree where S: ~Copyable {
    /// The tree consumer abstraction — the canonical surfacing of ``__TreeProtocol``
    /// (the `Array.Protocol` pattern).
    ///
    /// `__Tree<S>` conforms it where `S: __TreeStorage`.
    public typealias `Protocol` = __TreeProtocol
}
