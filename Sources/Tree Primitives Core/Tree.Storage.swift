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
// A GENUINE nested `Nest.Name` struct (`Tree<Element>.Storage<ChildLinks>`), NOT a
// hoist+alias: a struct can host a nested type (unlike `Tree.Protocol`, which must
// hoist), so there is no Swift-limitation justification for hoisting this one. It
// nests in the inverse-generic `extension Tree where Element: ~Copyable`, so it
// uses MEMBER-LEVEL construction twins (extension-level twins mangle-collide there
// — the re-validation finding). Conformers (`Tree`, `Tree.N`, `Tree.Keyed`) hold
// one privately; the arena logic (decode / insert-grow / remove / element & link
// access) lives here ONCE. Carries Round M's tree work verbatim: B2 `handle(at:)`
// decode + token validation; A3 typed counts; the generation-preserving
// `grow(to:)` / `clone()` contract; the `Shared` CoW column (the W5 design).

extension Tree where Element: ~Copyable {

    /// The shared generational node arena for the tree family.
    ///
    /// Wraps `Shared<Node, Column.Generational<Node>>` and exposes the
    /// child-representation-agnostic arena operations the conformers delegate to.
    /// The node type and column are internal details; no raw storage crosses the
    /// surface.
    public struct Storage<ChildLinks>: ~Copyable {

        @usableFromInline
        typealias Slot = __TreeNode<Element, ChildLinks>

        /// The generational node column behind the `Shared` CoW box.
        @usableFromInline
        var _column: Shared<Slot, Column.Generational<Slot>>

        /// The handle of the tree's root node, or `nil` if the tree is empty.
        ///
        /// Owned here so the arena and the conformer share one source of truth.
        public var rootHandle: Store.Generational.Handle?

        // MARK: Construction twins (MEMBER-LEVEL — this type nests in an
        // inverse-generic extension, where extension-level twins mangle-collide).

        /// Creates an empty arena (move-only elements — no clone strategy).
        @inlinable
        public init() {
            self._column = Shared(Column.Generational<Slot>.create(slotCapacity: 1))
            self.rootHandle = nil
        }

        /// Creates an empty CoW-capable arena.
        ///
        /// The generation-preserving clone strategy is captured via `Shared`'s
        /// `Copyable` init.
        @inlinable
        public init() where Element: Copyable, ChildLinks: Copyable {
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

        /// Creates an empty CoW-capable arena with reserved capacity.
        @inlinable
        public init(minimumCapacity: Index<Element>.Count) where Element: Copyable, ChildLinks: Copyable {
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

        /// CoW-gated mutable access to a node's element.
        ///
        /// The symmetric counterpart to ``withLinksMut(at:_:)`` for in-place
        /// element replacement (the keyed tree's `update` / `rootValue` /
        /// key-path-insert). Positions survive: the slot and its generation are
        /// untouched, only the stored element changes.
        @inlinable
        public mutating func withElementMut<R: ~Copyable>(
            at handle: Store.Generational.Handle,
            _ body: (inout Element) -> R
        ) -> R {
            _column.withUnique { body(&$0[handle].element) }
        }
    }
}

// MARK: - Copyable (the arena is CoW-capable exactly when its element + links are)

extension Tree.Storage: Copyable where Element: Copyable, ChildLinks: Copyable {}

// MARK: - Sendable
//
// PROPER conditional Sendable (no `@unchecked`): it rides the chain — `Shared` is
// `Sendable where B: Sendable`; `Column.Generational` is `Sendable where Element:
// Sendable`; `__TreeNode` is `Sendable where Element, ChildLinks: Sendable`; the
// `rootHandle` is `Store.Generational.Handle` (`Sendable`). If the compiler cannot
// carry the chain, this falls back to `@unchecked` (NOT `@unsafe`) per [MEM-SAFE-024].

extension Tree.Storage: Sendable where Element: Sendable, ChildLinks: Sendable {}
