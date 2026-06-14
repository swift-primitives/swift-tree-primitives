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

public import Column_Primitives
public import Index_Primitives
public import Shared_Primitive
public import Storage_Generational_Primitives
public import Store_Primitive

// MARK: - Tree.Storage — the shared generational arena (the de-dup nucleus)
//
// Hoisted [API-EXC-001] implementation of ``Tree/Storage`` (surfaced as the
// Nest.Name `Tree<Element>.Storage<ChildLinks>`). The corrected-E shared arena:
// ONE generational slot column behind the `Shared` CoW box, generalized over the
// per-variant child-link representation `ChildLinks`. Every `Tree.Protocol`
// conformer (`Tree`, `Tree.N`, `Tree.Keyed`) holds one of these privately; the
// arena logic (decode / insert-grow / remove / element & link access) lives here
// ONCE. Carries Round M's tree work verbatim: B2 `handle(at:)` decode + token
// validation; A3 typed counts; the generation-preserving `grow(to:)` / `clone()`
// contract (positions survive growth); the `Shared` CoW column (the W5 design).
//
// - Note: Use ``Tree/Storage`` in your code, not this type directly.

/// Hoisted implementation of the shared generational node arena.
///
/// Wraps `Shared<Node, Column.Generational<Node>>` and exposes the
/// child-representation-agnostic arena operations the conformers delegate to. The
/// node type and column are internal details; no raw storage crosses the surface.
public struct __TreeStorage<Element: ~Copyable, ChildLinks>: ~Copyable {

    @usableFromInline
    typealias Slot = __TreeNode<Element, ChildLinks>

    /// The generational node column behind the `Shared` CoW box.
    @usableFromInline
    var _column: Shared<Slot, Column.Generational<Slot>>

    /// The handle of the tree's root node, or `nil` if the tree is empty.
    ///
    /// Owned here so the arena and the conformer share one source of truth.
    public var rootHandle: Store.Generational.Handle?

    // MARK: Construction twins
    //
    // The `~Copyable` twin captures no clone strategy (statically unique). The
    // `Copyable` twin (the extension below) routes to `Shared`'s clone-capturing
    // init, so a CoW copy detaches by the generation-preserving deep copy. As a
    // TOP-LEVEL struct, this is free of the nested-in-inverse-generic-enum mangling
    // collision that forces the variant trees to member-level twins (de-risked
    // ×2 incl -O, CoW clone-independence).

    /// Creates an empty arena (move-only elements — no clone strategy).
    @inlinable
    public init() {
        self._column = Shared(Column.Generational<Slot>.create(slotCapacity: 1))
        self.rootHandle = nil
    }

    /// Creates an empty arena with reserved capacity (move-only elements).
    @inlinable
    public init(minimumCapacity: Index<Element>.Count) {
        let slots = Index<Slot>.Count(UInt(Swift.max(Int(bitPattern: minimumCapacity), 1)))
        self._column = Shared(Column.Generational<Slot>.create(slotCapacity: slots))
        self.rootHandle = nil
    }

    // MARK: Arena operations

    /// The number of live nodes (typed — A3; tagged by `Element`, one per node).
    @inlinable
    public var count: Index<Element>.Count {
        Index<Element>.Count(UInt(Int(bitPattern: _column.withColumn { $0.count })))
    }

    /// Decodes a position into its live handle, or `nil` if stale or out of bounds.
    ///
    /// Round M B2: the live handle is reconstructed from the column ledger
    /// (`handle(at:)`, no side table) and accepted only if the token matches the
    /// slot's current projected generation.
    @inlinable
    public func liveHandle(_ position: __TreePosition) -> Store.Generational.Handle? {
        let slot = Int(bitPattern: position.index)
        guard
            slot >= 0,
            let handle = _column.withColumn({ $0.handle(at: Index<Slot>(Ordinal(UInt(slot)))) }),
            UInt32(truncatingIfNeeded: handle.generation) == position.token
        else { return nil }
        return handle
    }

    /// Inserts a node (element + links), growing the column first when full (the
    /// explicit generation-preserving `grow(to:)` door — positions survive growth).
    @inlinable
    public mutating func insertNode(
        _ element: consuming Element,
        links: consuming ChildLinks,
        parent: Store.Generational.Handle?
    ) -> Store.Generational.Handle {
        _column.withUnique(
            consuming: Slot(element: element, links: links, parentHandle: parent)
        ) { (column, node) -> Store.Generational.Handle in
            if column.count == column.capacity {
                let doubled = Index<Slot>.Count(UInt(2 &* Int(bitPattern: column.capacity)))
                column.grow(to: doubled)
            }
            return column.insert(node)
        }
    }

    /// Removes the node at a live handle and moves its element out.
    @inlinable
    public mutating func removeNode(_ handle: Store.Generational.Handle) -> Element {
        guard let node = _column.withUnique({ $0.remove(handle) }) else {
            // Unreachable: callers pass decoded live handles and no removal interleaves.
            preconditionFailure("Tree.Storage: live handle failed to resolve on removal")
        }
        return node.element
    }

    /// Removes every node and resets the root (the `Shared` drain).
    @inlinable
    public mutating func removeAll() {
        _column.withUnique { $0.removeAll() }
        rootHandle = nil
    }

    /// The parent handle of a node (`nil` for the root).
    @inlinable
    public func parentHandle(of handle: Store.Generational.Handle) -> Store.Generational.Handle? {
        _column.withColumn { $0[handle].parentHandle }
    }

    /// Borrowing access to a node's element.
    @inlinable
    public func withElement<R: ~Copyable>(
        at handle: Store.Generational.Handle,
        _ body: (borrowing Element) -> R
    ) -> R {
        _column.withColumn { body($0[handle].element) }
    }

    /// Borrowing access to a node's child links.
    @inlinable
    public func withLinks<R: ~Copyable>(
        at handle: Store.Generational.Handle,
        _ body: (borrowing ChildLinks) -> R
    ) -> R {
        _column.withColumn { body($0[handle].links) }
    }

    /// CoW-gated mutable access to a node's child links.
    @inlinable
    public mutating func withLinksMut<R: ~Copyable>(
        at handle: Store.Generational.Handle,
        _ body: (inout ChildLinks) -> R
    ) -> R {
        _column.withUnique { body(&$0[handle].links) }
    }
}

// MARK: - Copyable construction twin (captures the clone strategy)

extension __TreeStorage: Copyable where Element: Copyable, ChildLinks: Copyable {
    /// Creates an empty CoW-capable arena.
    ///
    /// The generation-preserving clone strategy is captured via `Shared`'s
    /// `Copyable` init.
    @inlinable
    public init() {
        self._column = Shared(Column.Generational<Slot>.create(slotCapacity: 1))
        self.rootHandle = nil
    }

    /// Creates an empty CoW-capable arena with reserved capacity.
    @inlinable
    public init(minimumCapacity: Index<Element>.Count) {
        let slots = Index<Slot>.Count(UInt(Swift.max(Int(bitPattern: minimumCapacity), 1)))
        self._column = Shared(Column.Generational<Slot>.create(slotCapacity: slots))
        self.rootHandle = nil
    }
}

// MARK: - Sendable

extension __TreeStorage: @unsafe @unchecked Sendable where Element: Sendable, ChildLinks: Sendable {}
