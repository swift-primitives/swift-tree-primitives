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

/// A dynamically-growing tree of unbounded arity — the canonical tree, and the
/// namespace for the variant trees.
///
/// `Tree<Element>` is the general-purpose tree: each node may have any number of
/// children in a dense, ordered list. It is the `Tree.Protocol` conformer for the
/// dynamic role (the former `Tree.Unbounded`, which retires into this type), and
/// it is ALSO the namespace nest for the bounded-arity ``Tree/N``, the keyed
/// ``Tree/Keyed``, and the binary `Tree.Binary` (= `Tree.N<2>`) variants — each
/// added by its own package via a cross-module extension on `Tree`.
///
/// Both the tree and its elements may be `~Copyable`; when `Element` is `Copyable`
/// the tree is copy-on-write (the `Shared` column's generation-preserving clone).
/// The arena, decode (Round M B2), token validation, typed counts (A3) and the
/// position-survives-growth contract live in ``Tree/Storage`` + the
/// ``Tree/Protocol`` defaults; this type supplies the dense `[Handle]` child-link
/// representation and its operations.
///
/// ## Example
///
/// ```swift
/// var tree = Tree<String>()
/// let root = try tree.insert("root", at: .root)
/// let child = try tree.insert("child", at: .child(of: root, at: 0))
/// tree.forEachPreOrder { print($0) }  // root, child
/// ```
public struct Tree<Element: ~Copyable>: __TreeProtocol {

    /// Children are addressed by a typed ordinal in the tree's own child domain
    /// (`0..<childCount`) — `Index<Tree<Element>>`, distinct from the node count
    /// (`Index<Element>.Count`) and the arena slot (`Index<__TreePosition>`).
    public typealias Address = Index<Tree<Element>>

    /// Typed node count (A3).
    public typealias Count = Index<Element>.Count

    /// The error type for the shared tree operations.
    public typealias Error = __TreeError

    /// The tree abstraction — the canonical surfacing of ``__TreeProtocol`` (the Array.Protocol pattern).
    public typealias `Protocol` = __TreeProtocol

    /// The private generational arena (NON-PUBLIC — `@usableFromInline` for the
    /// inlinable witnesses; the `Tree.Protocol` defaults never reference it).
    @usableFromInline
    var _storage: Storage<[Store.Generational.Handle]>

    // MARK: Initialization (construction twins — the Copyable twin is in the extension below)

    /// Creates an empty tree (move-only elements).
    @inlinable
    public init() { _storage = Storage<[Store.Generational.Handle]>() }

    /// Creates an empty tree with reserved capacity (move-only elements).
    @inlinable
    public init(minimumCapacity: Count) { _storage = Storage<[Store.Generational.Handle]>(minimumCapacity: minimumCapacity) }

    // MARK: Properties

    /// The number of nodes in the tree (typed — A3).
    @inlinable
    public var count: Count { _storage.count }

    /// The number of children of the node at `position`, or `nil` if the position
    /// is invalid — typed in the tree's child domain (`Index<Tree<Element>>.Count`),
    /// so `childIndex < childCount` bounds-checks ([IDX-007]).
    @inlinable
    public func childCount(of position: __TreePosition) -> Index<Tree<Element>>.Count? {
        guard let handle = _liveHandle(position) else { return nil }
        return Index<Tree<Element>>.Count(UInt(_childCount(at: handle)))
    }

    // MARK: Arena requirements (delegated to the private Tree.Storage)

    /// The root node's handle (the `Tree.Protocol` arena requirement).
    @inlinable
    public var _rootHandle: Store.Generational.Handle? {
        get { _storage.rootHandle }
        set { _storage.rootHandle = newValue }
    }

    /// Decodes a position to its live handle (the arena requirement).
    @inlinable
    public func _liveHandle(_ position: __TreePosition) -> Store.Generational.Handle? {
        _storage.liveHandle(position)
    }

    /// Inserts a childless node with the given parent (the arena requirement).
    @inlinable
    public mutating func _insertNode(
        _ element: consuming Element,
        parent: Store.Generational.Handle?
    ) -> Store.Generational.Handle {
        _storage.insertNode(element, links: [], parent: parent)
    }

    /// Removes a node, moving its element out (the arena requirement).
    @inlinable
    public mutating func _removeNode(_ handle: Store.Generational.Handle) -> Element {
        _storage.removeNode(handle)
    }

    /// Removes every node and resets the root (the arena requirement).
    @inlinable
    public mutating func _removeAll() { _storage.removeAll() }

    /// The parent handle of a node (the arena requirement).
    @inlinable
    public func _parentHandle(of handle: Store.Generational.Handle) -> Store.Generational.Handle? {
        _storage.parentHandle(of: handle)
    }

    /// Borrowing access to a node's element (the arena requirement).
    @inlinable
    public func _withElement<R: ~Copyable>(
        at handle: Store.Generational.Handle,
        _ body: (borrowing Element) -> R
    ) -> R {
        _storage.withElement(at: handle, body)
    }

    // MARK: Child-link requirements (dense ordered list)

    /// The child handle at a dense index, or `nil` if out of range.
    ///
    /// The typed child ordinal is lowered to `Int` only at the stdlib-array
    /// boundary ([IDX-006b]/[CONV-002] — same-package implementation).
    @inlinable
    public func _childHandle(
        at handle: Store.Generational.Handle,
        address index: Index<Tree<Element>>
    ) -> Store.Generational.Handle? {
        let i = Int(bitPattern: index)
        return _storage.withLinks(at: handle) { (i >= 0 && i < $0.count) ? $0[i] : nil }
    }

    /// Rejects a child index outside `0...childCount` (the per-conformer error precision).
    @inlinable
    public func _validateLink(
        to parent: Store.Generational.Handle,
        at index: Index<Tree<Element>>
    ) throws(__TreeError) {
        let i = Int(bitPattern: index)
        let childCount = _storage.withLinks(at: parent) { $0.count }
        guard i >= 0, i <= childCount else { throw .childIndexOutOfBounds }
    }

    /// Inserts a child handle at a dense index (precondition: validated).
    @inlinable
    public mutating func _linkChild(
        _ child: Store.Generational.Handle,
        to parent: Store.Generational.Handle,
        at index: Index<Tree<Element>>
    ) {
        let i = Int(bitPattern: index)
        _storage.withLinksMut(at: parent) { $0.insert(child, at: i) }
    }

    /// Removes a child handle from its parent's dense list.
    @inlinable
    public mutating func _unlinkChild(
        _ child: Store.Generational.Handle,
        from parent: Store.Generational.Handle
    ) {
        _storage.withLinksMut(at: parent) { if let position = $0.firstIndex(of: child) { $0.remove(at: position) } }
    }

    /// The number of children of a node.
    @inlinable
    public func _childCount(at handle: Store.Generational.Handle) -> Int {
        _storage.withLinks(at: handle) { $0.count }
    }

    /// Visits each child handle in dense order.
    @inlinable
    public func _forEachChild(
        at handle: Store.Generational.Handle,
        _ body: (Store.Generational.Handle) -> Void
    ) {
        _storage.withLinks(at: handle) { for index in 0..<$0.count { body($0[index]) } }
    }
}

// MARK: - Copyable construction twin (CoW; captures the clone strategy)

extension Tree: Copyable where Element: Copyable {
    /// Creates an empty CoW tree (the clone strategy is captured via the
    /// `Tree.Storage` Copyable twin).
    @inlinable
    public init() { _storage = Storage<[Store.Generational.Handle]>() }

    /// Creates an empty CoW tree with reserved capacity.
    @inlinable
    public init(minimumCapacity: Count) { _storage = Storage<[Store.Generational.Handle]>(minimumCapacity: minimumCapacity) }
}

// MARK: - Sendable
//
// PROPER conditional Sendable (no `@unchecked`): rides the arena's Sendable chain
// (`Tree.Storage` → `Shared` → `Column.Generational` → `__TreeNode`). If the
// compiler cannot carry it, falls back to `@unchecked` (NOT `@unsafe`) per [MEM-SAFE-024].

extension Tree: Sendable where Element: Sendable {}
