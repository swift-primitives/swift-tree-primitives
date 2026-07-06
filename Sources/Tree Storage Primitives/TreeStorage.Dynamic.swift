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
public import Tree_Index_Primitives
public import Tree_Primitive

// MARK: - Tree.Storage namespace + Tree.Storage.Dynamic — the DYNAMIC storage column
//
// `TreeStorage.Dynamic` is the canonical tree's storage capability conformer
// ([DS-025]/[DS-027].1): a dense, ordered `[Handle]` child-link representation over the
// shared ``__TreeArena``. It is the `S` of the canonical dynamic tree
// `__Tree<TreeStorage.Dynamic<Element>>` (the ``Tree`` front door) — the re-roled former
// `struct Tree<Element>`'s arena + child-link `_`-ops, now a STORAGE column conforming
// ``__TreeStorage`` rather than the ADT conforming the seam. This is a re-skeleton: the
// arena and witnesses carry forward verbatim. The `TreeStorage` namespace enum is in
// `TreeStorage.swift`.

extension TreeStorage {

    /// The dynamic (unbounded-arity) tree storage column.
    ///
    /// Each node has a dense, ordered list of children (`[Handle]`); children are
    /// addressed by a typed ordinal in this column's child domain
    /// (`Index<TreeStorage.Dynamic<Element>>`). Inserting at an index shifts the rest.
    public struct Dynamic<Element: ~Copyable>: ~Copyable {

        /// Children are addressed by a typed ordinal in this column's child domain.
        public typealias Address = Index<Self>

        /// The private generational arena (NON-PUBLIC — `@usableFromInline` for the
        /// inlinable witnesses).
        @usableFromInline
        var _arena: __TreeArena<Element, [Store.Generational.Handle]>

        /// Creates an empty dynamic column (move-only elements).
        @inlinable
        public init() { _arena = __TreeArena<Element, [Store.Generational.Handle]>() }

        /// Creates an empty dynamic column with reserved capacity (move-only elements).
        @inlinable
        public init(minimumCapacity: Index<Element>.Count) {
            _arena = __TreeArena<Element, [Store.Generational.Handle]>(minimumCapacity: minimumCapacity)
        }

        /// Creates an empty CoW-capable dynamic column (the clone strategy is captured here).
        @inlinable
        public init() where Element: Copyable {
            _arena = __TreeArena<Element, [Store.Generational.Handle]>()
        }

        /// Creates an empty CoW-capable dynamic column with reserved capacity.
        @inlinable
        public init(minimumCapacity: Index<Element>.Count) where Element: Copyable {
            _arena = __TreeArena<Element, [Store.Generational.Handle]>(minimumCapacity: minimumCapacity)
        }
    }
}

// MARK: - __TreeStorage conformance (the arena + dense child-link witnesses)

extension TreeStorage.Dynamic: __TreeStorage where Element: ~Copyable {

    // MARK: Arena requirements (delegated to the private __TreeArena)

    /// The number of live nodes (typed — A3).
    @inlinable
    public var _count: Index<Element>.Count { _arena.count }

    /// The root node's handle.
    @inlinable
    public var _rootHandle: Store.Generational.Handle? {
        get { _arena.rootHandle }
        set { _arena.rootHandle = newValue }
    }

    /// Decodes a position to its live handle.
    @inlinable
    public func _liveHandle(_ position: __TreePosition) -> Store.Generational.Handle? {
        _arena.liveHandle(position)
    }

    /// Inserts a childless node with the given parent.
    @inlinable
    public mutating func _insertNode(
        _ element: consuming Element,
        parent: Store.Generational.Handle?
    ) -> Store.Generational.Handle {
        _arena.insertNode(element, links: [], parent: parent)
    }

    /// Removes a node, moving its element out.
    @inlinable
    public mutating func _removeNode(_ handle: Store.Generational.Handle) -> Element {
        _arena.removeNode(handle)
    }

    /// Removes every node and resets the root.
    @inlinable
    public mutating func _removeAll() { _arena.removeAll() }

    /// The parent handle of a node.
    @inlinable
    public func _parentHandle(of handle: Store.Generational.Handle) -> Store.Generational.Handle? {
        _arena.parentHandle(of: handle)
    }

    /// Borrowing access to a node's element.
    @inlinable
    public func _withElement<R: ~Copyable>(
        at handle: Store.Generational.Handle,
        _ body: (borrowing Element) -> R
    ) -> R {
        _arena.withElement(at: handle, body)
    }

    /// In-place (position-stable) mutating access to a node's element.
    @inlinable
    public mutating func _withElementMut<R: ~Copyable>(
        at handle: Store.Generational.Handle,
        _ body: (inout Element) -> R
    ) -> R {
        _arena.withElementMut(at: handle, body)
    }

    // MARK: Child-link requirements (dense ordered list)

    /// The child handle at a dense index, or `nil` if out of range.
    ///
    /// The typed child ordinal is lowered to `Int` only at the stdlib-array
    /// boundary ([IDX-006b]/[CONV-002] — same-package implementation).
    @inlinable
    public func _childHandle(
        at handle: Store.Generational.Handle,
        address index: Index<Self>
    ) -> Store.Generational.Handle? {
        let i = Int(bitPattern: index)
        return _arena.withLinks(at: handle) { (i >= 0 && i < $0.count) ? $0[i] : nil }
    }

    /// Rejects a child index outside `0...childCount` (the per-column error precision).
    @inlinable
    public func _validateLink(
        to parent: Store.Generational.Handle,
        at index: Index<Self>
    ) throws(__TreeError) {
        let i = Int(bitPattern: index)
        let childCount = _arena.withLinks(at: parent) { $0.count }
        guard i >= 0, i <= childCount else { throw .childIndexOutOfBounds }
    }

    /// Inserts a child handle at a dense index (precondition: validated).
    @inlinable
    public mutating func _linkChild(
        _ child: Store.Generational.Handle,
        to parent: Store.Generational.Handle,
        at index: Index<Self>
    ) {
        let i = Int(bitPattern: index)
        _arena.withLinksMut(at: parent) { $0.insert(child, at: i) }
    }

    /// Removes a child handle from its parent's dense list.
    @inlinable
    public mutating func _unlinkChild(
        _ child: Store.Generational.Handle,
        from parent: Store.Generational.Handle
    ) {
        _arena.withLinksMut(at: parent) { if let position = $0.firstIndex(of: child) { $0.remove(at: position) } }
    }

    /// The number of children of a node.
    @inlinable
    public func _childCount(at handle: Store.Generational.Handle) -> Int {
        _arena.withLinks(at: handle) { $0.count }
    }

    /// Visits each child handle in dense order.
    @inlinable
    public func _forEachChild(
        at handle: Store.Generational.Handle,
        _ body: (Store.Generational.Handle) -> Void
    ) {
        _arena.withLinks(at: handle) { for index in 0..<$0.count { body($0[index]) } }
    }
}

// MARK: - Copyable / Sendable (flow from element + the dense links)

extension TreeStorage.Dynamic: Copyable where Element: Copyable {}

extension TreeStorage.Dynamic: Sendable where Element: Sendable {}

// MARK: - Column-pinned construction (the `Array+Columns` mechanic: method-level `where ==`)
//
// The carrier's construction pins to the dynamic column here (`init() where S ==
// TreeStorage.Dynamic<E>`), so the canonical ``Tree`` front door gets the ergonomic
// empty / reserved-capacity inits. Mirrors `Array`'s per-column inits.

extension __Tree where S: ~Copyable {

    /// Creates an empty dynamic tree (move-only elements).
    @inlinable
    public init<Element: ~Copyable>() where S == TreeStorage.Dynamic<Element> {
        self.init(storage: TreeStorage.Dynamic<Element>())
    }

    /// Creates an empty dynamic tree with reserved capacity (move-only elements).
    @inlinable
    public init<Element: ~Copyable>(minimumCapacity: Index_Primitives.Index<Element>.Count)
    where S == TreeStorage.Dynamic<Element> {
        self.init(storage: TreeStorage.Dynamic<Element>(minimumCapacity: minimumCapacity))
    }

    // CoW construction twins (MEMBER-LEVEL): for a `Copyable` element the column's clone
    // strategy MUST be captured at construction (the `Shared` box's `Copyable` init), else
    // a copied tree's first mutation traps ("not unique but carries no clone strategy").
    // The more-constrained twin wins at `Copyable` call sites.

    /// Creates an empty CoW-capable dynamic tree (captures the clone strategy).
    @inlinable
    public init<Element>() where S == TreeStorage.Dynamic<Element> {
        self.init(storage: TreeStorage.Dynamic<Element>())
    }

    /// Creates an empty CoW-capable dynamic tree with reserved capacity.
    @inlinable
    public init<Element>(minimumCapacity: Index_Primitives.Index<Element>.Count)
    where S == TreeStorage.Dynamic<Element> {
        self.init(storage: TreeStorage.Dynamic<Element>(minimumCapacity: minimumCapacity))
    }
}

// The former `TreeDynamic` compound ergonomic alias is RETIRED (§9.6.5, [API-NAME-001]
// hygiene): the canonical spelling is the `Tree<Element>` front door (`Tree.FrontDoor.swift`,
// this target). The 6.3.2 frontend crash that forced the compound top-level alias is fixed
// on 6.3.3 (the adt-tower walls probes) — the front door is the sanctioned [DS-028] shape.
