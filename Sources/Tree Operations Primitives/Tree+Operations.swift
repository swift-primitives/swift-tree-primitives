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

public import Buffer_Ring_Primitive
public import Index_Primitives
public import Queue_Primitives
public import Stack_Primitives
public import Storage_Generational_Primitives
public import Store_Primitive
public import Tree_Index_Primitives
public import Tree_Primitive

// MARK: - Tree operations (the de-dup engine: written ONCE on __Tree<S>, for every column)
//
// The Charter at-target reshape ([DS-025]): the node-shape-agnostic tree algorithms move
// from the former `extension __TreeProtocol` defaults onto the carrier by CONDITIONAL
// EXTENSION keyed on the storage capability (`extension __Tree where S: __TreeStorage`),
// forwarding to `storage._x`. This is a re-skeleton — the algorithm bodies carry forward
// VERBATIM (the post-order dropped-subtree fix, the two-stack n-ary teardown, the
// iterative height, the position plumbing); only the receiver changes from `self._x`
// (the ADT-conformed-the-seam shape) to `storage._x` (the column-conforms-the-seam shape).
// `Element`/`Address` are read from the column as `S.Element` / `S.Address`.

extension __Tree where S: __TreeStorage & ~Copyable {

    // MARK: Surfaced typealiases (the consumer-facing element / address / insert position)

    /// The element stored at each node (the column's element).
    public typealias Element = S.Element

    /// How a child is addressed within its parent (the column's addressing scheme).
    public typealias Address = S.Address

    /// Typed node count (A3).
    public typealias Count = Index_Primitives.Index<S.Element>.Count

    /// Where to insert a new node, addressed per the column's `Address`.
    public typealias InsertPosition = __TreeInsertPosition<S.Address>

    /// The number of nodes in the tree (typed — A3).
    @inlinable
    public var count: Count {
        // The column owns the typed count via its arena; recovered through the seam.
        storage._count
    }

    // MARK: Position plumbing

    /// Mints the public position for a live handle: the slot plus the slot
    /// generation projected into the position's `UInt32` token (wraps after 2^32
    /// frees of one slot — the retired arena's wrap, unchanged).
    @inlinable
    public func _position(of handle: Store.Generational.Handle) -> __TreePosition {
        __TreePosition(index: handle.index, token: UInt32(truncatingIfNeeded: handle.generation))
    }

    /// Decodes a position into a live handle or throws `.invalidPosition`.
    @inlinable
    package func _decode(_ position: __TreePosition) throws(__TreeError) -> Store.Generational.Handle {
        guard let handle = storage._liveHandle(position) else { throw .invalidPosition }
        return handle
    }

    // MARK: Properties

    /// Whether the tree has no nodes.
    @inlinable
    public var isEmpty: Bool { storage._rootHandle == nil }

    /// The position of the root node, or `nil` if the tree is empty.
    @inlinable
    public var root: __TreePosition? {
        guard let rootHandle = storage._rootHandle else { return nil }
        return _position(of: rootHandle)
    }

    /// Validates that a position refers to a currently-live node.
    @inlinable
    public func validate(_ position: __TreePosition) throws(__TreeError) {
        _ = try _decode(position)
    }

    // MARK: Navigation

    /// The position of the child at `address`, or `nil` if absent / position invalid.
    ///
    /// SPI backing for the public `tree.child.at(_:of:)` accessor ([API-NAME-002];
    /// the compound surface was folded into the `child` view in R1 W4).
    @inlinable
    public func _child(of position: __TreePosition, at address: S.Address) -> __TreePosition? {
        // swiftlint:disable:next no_try_optional - reason: invalid position maps to nil per the documented contract
        guard let handle = try? _decode(position),
            let childHandle = storage._childHandle(at: handle, address: address)
        else { return nil }
        return _position(of: childHandle)
    }

    /// The position of a node's parent, or `nil` if it is the root / position invalid.
    @inlinable
    public func parent(of position: __TreePosition) -> __TreePosition? {
        // swiftlint:disable:next no_try_optional - reason: invalid position maps to nil per the documented contract
        guard let handle = try? _decode(position),
            let parentHandle = storage._parentHandle(of: handle)
        else { return nil }
        return _position(of: parentHandle)
    }

    /// The number of children of a node (the `Tree.Protocol` view-facing requirement).
    @inlinable
    public func _childCount(at handle: Store.Generational.Handle) -> Int {
        storage._childCount(at: handle)
    }

    /// Calls `body` for each child handle of a node, in child order (the view-facing requirement).
    @inlinable
    public func _forEachChild(
        at handle: Store.Generational.Handle,
        _ body: (Store.Generational.Handle) -> Void
    ) {
        storage._forEachChild(at: handle, body)
    }

    /// The live handle for a position, or `nil` (the `Tree.Protocol` view-facing requirement).
    @inlinable
    public func _liveHandle(_ position: __TreePosition) -> Store.Generational.Handle? {
        storage._liveHandle(position)
    }

    // `childCount(of:)` is NOT a shared op: its return type is the column's own child
    // domain. Each column / variant surfaces it over the `_childCount` requirement.

    /// Whether the node at `position` is a leaf (has no children).
    ///
    /// Returns `false` if the position is invalid.
    @inlinable
    public func isLeaf(_ position: __TreePosition) -> Bool {
        // swiftlint:disable:next no_try_optional - reason: invalid position maps to false per the documented contract
        guard let handle = try? _decode(position) else { return false }
        return storage._childCount(at: handle) == 0
    }

    // MARK: Element access

    /// Borrowing access to the element at `position`, or `nil` if invalid.
    @inlinable
    public func peek<R: ~Copyable>(
        at position: __TreePosition,
        _ body: (borrowing S.Element) -> R
    ) -> R? {
        // swiftlint:disable:next no_try_optional - reason: invalid position maps to nil per the documented contract
        guard let handle = try? _decode(position) else { return nil }
        return storage._withElement(at: handle, body)
    }

    /// Borrowing access to a node's element (the `Tree.Protocol` view-facing requirement).
    @inlinable
    public func _withElement<R: ~Copyable>(
        at handle: Store.Generational.Handle,
        _ body: (borrowing S.Element) -> R
    ) -> R {
        storage._withElement(at: handle, body)
    }

    /// In-place (position-stable) mutating access to the element at `position`, or
    /// `nil` if the position is invalid.
    ///
    /// The slot and its generation are untouched — only the stored element changes —
    /// so `position` (and any other outstanding position) keeps resolving. The
    /// mutating counterpart to ``peek(at:_:)``; backs value-update surfaces.
    @inlinable
    @discardableResult
    public mutating func withElementMut<R: ~Copyable>(
        at position: __TreePosition,
        _ body: (inout S.Element) -> R
    ) -> R? {
        // swiftlint:disable:next no_try_optional - reason: invalid position maps to nil per the documented contract
        guard let handle = try? _decode(position) else { return nil }
        return storage._withElementMut(at: handle, body)
    }

    // MARK: Mutation

    /// Inserts an element at the given insert position; returns the new node's position.
    ///
    /// Validates the child link BEFORE inserting the node (so no orphan is created
    /// on rejection), preserving each column's error precision.
    @inlinable
    @discardableResult
    public mutating func insert(
        _ element: consuming S.Element,
        at position: __TreeInsertPosition<S.Address>
    ) throws(__TreeError) -> __TreePosition {
        switch position {
        case .root:
            guard storage._rootHandle == nil else { throw .rootOccupied }
            let handle = storage._insertNode(element, parent: nil)
            storage._rootHandle = handle
            return _position(of: handle)

        case .child(of: let parent, at: let address):
            let parentHandle = try _decode(parent)
            try storage._validateLink(to: parentHandle, at: address)
            let handle = storage._insertNode(element, parent: parentHandle)
            storage._linkChild(handle, to: parentHandle, at: address)
            return _position(of: handle)
        }
    }

    /// Removes the leaf node at `position` and returns its element.
    @inlinable
    @discardableResult
    public mutating func remove(at position: __TreePosition) throws(__TreeError) -> S.Element {
        let handle = try _decode(position)
        guard storage._childCount(at: handle) == 0 else { throw .cannotRemoveNonLeaf }
        if let parentHandle = storage._parentHandle(of: handle) {
            storage._unlinkChild(handle, from: parentHandle)
        } else {
            storage._rootHandle = nil
        }
        return storage._removeNode(handle)
    }

    /// Removes every node from the tree.
    @inlinable
    public mutating func clear() { storage._removeAll() }

    /// The length of the longest root-to-leaf path, or `nil` if the tree is empty.
    ///
    /// A single-node tree has height `.zero`. Iterative traversal (deep-tree safe).
    @inlinable
    public var height: Index_Primitives.Index<S.Element>.Count? {
        guard let rootHandle = storage._rootHandle else { return nil }
        var maxDepth = 0
        var pending = Stack<(handle: Store.Generational.Handle, depth: Int)>()
        pending.push((rootHandle, 0))
        while let (handle, depth) = pending.pop() {
            maxDepth = Swift.max(maxDepth, depth)
            storage._forEachChild(at: handle) { pending.push(($0, depth + 1)) }
        }
        return Index_Primitives.Index<S.Element>.Count(UInt(maxDepth))
    }

    /// Removes the entire subtree rooted at `position` (post-order teardown).
    @inlinable
    public mutating func removeSubtree(at position: __TreePosition) throws(__TreeError) {
        let handle = try _decode(position)
        if let parentHandle = storage._parentHandle(of: handle) {
            storage._unlinkChild(handle, from: parentHandle)
        } else {
            storage._rootHandle = nil
        }
        // Two-stack post-order: a pre-order pass fills `output`; draining it frees
        // children before parents (the n-ary-safe teardown — a single lastVisited
        // scalar cannot disambiguate an n-ary node's completed child).
        var pending = Stack<Store.Generational.Handle>()
        var output = Stack<Store.Generational.Handle>()
        pending.push(handle)
        while let current = pending.pop() {
            output.push(current)
            storage._forEachChild(at: current) { pending.push($0) }
        }
        while let current = output.pop() {
            _ = storage._removeNode(current)
        }
    }

    // MARK: Traversal (closure-based; SPI backing the public `tree.forEach.*` view)
    //
    // The public surface is `tree.forEach.preOrder { }` etc. (`__TreeForEach.swift`,
    // R1 W4 [API-NAME-002]); these `_forEach*` ops carry the shared logic.

    /// Visits every element in pre-order (root, then children left-to-right).
    @inlinable
    public func _forEachPreOrder(_ body: (borrowing S.Element) -> Void) {
        guard let rootHandle = storage._rootHandle else { return }
        var pending = Stack<Store.Generational.Handle>()
        pending.push(rootHandle)
        while let current = pending.pop() {
            storage._withElement(at: current) { body($0) }
            var kids: [Store.Generational.Handle] = []
            storage._forEachChild(at: current) { kids.append($0) }
            for index in (0..<kids.count).reversed() { pending.push(kids[index]) }
        }
    }

    /// Visits every element in post-order (children left-to-right, then parent).
    @inlinable
    public func _forEachPostOrder(_ body: (borrowing S.Element) -> Void) {
        guard let rootHandle = storage._rootHandle else { return }
        var pending = Stack<Store.Generational.Handle>()
        var output = Stack<Store.Generational.Handle>()
        pending.push(rootHandle)
        while let current = pending.pop() {
            output.push(current)
            storage._forEachChild(at: current) { pending.push($0) }
        }
        while let current = output.pop() {
            storage._withElement(at: current) { body($0) }
        }
    }

    /// Visits every element in level-order (breadth-first).
    @inlinable
    public func _forEachLevelOrder(_ body: (borrowing S.Element) -> Void) {
        guard let rootHandle = storage._rootHandle else { return }
        var pending = Queue<Store.Generational.Handle>()
        pending.enqueue(rootHandle)
        while let current = pending.dequeue() {
            storage._withElement(at: current) { body($0) }
            storage._forEachChild(at: current) { pending.enqueue($0) }
        }
    }
}

// MARK: - Copyable-element conveniences

extension __Tree where S: __TreeStorage & ~Copyable, S.Element: Copyable {
    /// The element at `position`, or `nil` if the position is invalid.
    @inlinable
    public func peek(at position: __TreePosition) -> S.Element? {
        peek(at: position) { $0 }
    }
}

// MARK: - Additive consumer-protocol conformance (the carrier conforms; the column never does)
//
// `__Tree<S>` conforms `Tree.Protocol` (`__TreeProtocol`) where its column carries the
// storage capability — the `__Array: Array.Protocol` model ([DS-025] point 4). The
// requirements are satisfied by the operations above; the storage `S` itself never
// conforms `Tree.Protocol`.

extension __Tree: __TreeProtocol where S: __TreeStorage & ~Copyable {}
