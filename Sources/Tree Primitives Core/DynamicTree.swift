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

/// The canonical dynamic-arity tree — the `Tree.Protocol` conformer whose nodes
/// hold a dense, ordered list of child handles.
///
/// `DynamicTree` is the general-purpose tree: each node may have any number of
/// children, inserted at an index or appended. It is the conformer the canonical
/// `Tree<Element>` resolves to (the namespace dissolution lands in W4). Both the
/// tree and its elements may be `~Copyable`; when `Element` is `Copyable` the tree
/// is copy-on-write (the `Shared` column's generation-preserving clone).
///
/// The arena, decode (Round M B2), token validation, typed counts (A3) and the
/// position-survives-growth contract all live in the shared `TreeStorage`; the
/// tree algorithms live in the `Tree.Protocol` defaults. This type supplies only
/// the dense `[Handle]` child-link representation and its operations.
///
/// ## Example
///
/// ```swift
/// var tree = DynamicTree<String>()
/// let root = try tree.insert("root", at: .root)
/// let child = try tree.insert("child", at: .child(of: root, at: 0))
/// tree.forEachPreOrder { print($0) }  // root, child
/// ```
public struct DynamicTree<Element: ~Copyable>: __TreeProtocol {

    /// Children are addressed by a dense index (`0..<childCount`).
    public typealias Address = Int

    /// Typed node count (A3).
    public typealias Count = Index<Element>.Count

    /// A position (cursor) to a node.
    public typealias Position = __TreePosition

    /// The error type for the shared tree operations.
    public typealias Error = __TreeError

    /// The private generational arena (NON-PUBLIC — `@usableFromInline` for the
    /// inlinable witnesses; the `Tree.Protocol` defaults never reference it).
    @usableFromInline
    var _storage: TreeStorage<Element, [Store.Generational.Handle]>

    // MARK: Initialization (construction twins — the Copyable twin is in the extension below)

    /// Creates an empty tree (move-only elements).
    @inlinable
    public init() { _storage = TreeStorage() }

    /// Creates an empty tree with reserved capacity (move-only elements).
    @inlinable
    public init(minimumCapacity: Count) { _storage = TreeStorage(minimumCapacity: minimumCapacity) }

    // MARK: Properties

    /// The number of nodes in the tree (typed — A3).
    @inlinable
    public var count: Count { _storage.count }

    // MARK: Arena requirements (delegated to the private TreeStorage)

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
    @inlinable
    public func _childHandle(
        at handle: Store.Generational.Handle,
        address index: Int
    ) -> Store.Generational.Handle? {
        _storage.withLinks(at: handle) { (index >= 0 && index < $0.count) ? $0[index] : nil }
    }

    /// Rejects a child index outside `0...childCount` (the per-conformer error precision).
    @inlinable
    public func _validateLink(
        to parent: Store.Generational.Handle,
        at index: Int
    ) throws(__TreeError) {
        let childCount = _storage.withLinks(at: parent) { $0.count }
        guard index >= 0, index <= childCount else { throw .childIndexOutOfBounds }
    }

    /// Inserts a child handle at a dense index (precondition: validated).
    @inlinable
    public mutating func _linkChild(
        _ child: Store.Generational.Handle,
        to parent: Store.Generational.Handle,
        at index: Int
    ) {
        _storage.withLinksMut(at: parent) { $0.insert(child, at: index) }
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

extension DynamicTree: Copyable where Element: Copyable {
    /// Creates an empty CoW tree (the clone strategy is captured via the
    /// `TreeStorage` Copyable twin).
    @inlinable
    public init() { _storage = TreeStorage() }

    /// Creates an empty CoW tree with reserved capacity.
    @inlinable
    public init(minimumCapacity: Count) { _storage = TreeStorage(minimumCapacity: minimumCapacity) }
}

// MARK: - The tree abstraction alias (the Array.Protocol pattern)

extension DynamicTree {
    /// The tree abstraction — the canonical surfacing of ``__TreeProtocol``.
    ///
    /// Spelled `DynamicTree.Protocol` (and, after W4 dissolves the namespace,
    /// `Tree.Protocol`).
    public typealias `Protocol` = __TreeProtocol
}

// MARK: - Sendable

extension DynamicTree: @unsafe @unchecked Sendable where Element: Sendable {}
