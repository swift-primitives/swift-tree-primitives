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
public import Column_Primitives
public import Queue_Primitives
public import Stack_Primitives
public import Storage_Generational_Primitives
public import Store_Primitive

// MARK: - Tree.Protocol shared defaults (the de-dup: written ONCE, inherited by all conformers)
//
// The node-shape-agnostic tree algorithms, expressed over the operation
// requirements ALONE. No default touches a conformer's storage. This is the
// shared orchestration the corrected-E shape factors out of the three variants.

extension __TreeProtocol where Self: ~Copyable {

    // MARK: Position plumbing

    /// Mints the public position for a live handle: the slot plus the slot
    /// generation projected into the position's `UInt32` token (wraps after 2^32
    /// frees of one slot — the retired arena's wrap, unchanged).
    @inlinable
    func _position(of handle: Store.Generational.Handle) -> __TreePosition {
        __TreePosition(index: handle.index, token: UInt32(truncatingIfNeeded: handle.generation))
    }

    /// Decodes a position into a live handle or throws `.invalidPosition`.
    @inlinable
    func _decode(_ position: __TreePosition) throws(__TreeError) -> Store.Generational.Handle {
        guard let handle = _liveHandle(position) else { throw .invalidPosition }
        return handle
    }

    // MARK: Properties

    /// Whether the tree has no nodes.
    @inlinable
    public var isEmpty: Bool { _rootHandle == nil }

    /// The position of the root node, or `nil` if the tree is empty.
    @inlinable
    public var root: __TreePosition? {
        guard let rootHandle = _rootHandle else { return nil }
        return _position(of: rootHandle)
    }

    /// Validates that a position refers to a currently-live node.
    @inlinable
    public func validate(_ position: __TreePosition) throws(__TreeError) {
        _ = try _decode(position)
    }

    // MARK: Navigation

    /// The position of the child at `address`, or `nil` if absent / position invalid.
    @inlinable
    public func child(of position: __TreePosition, at address: Address) -> __TreePosition? {
        guard let handle = try? _decode(position),
            let childHandle = _childHandle(at: handle, address: address)
        else { return nil }
        return _position(of: childHandle)
    }

    /// The position of a node's parent, or `nil` if it is the root / position invalid.
    @inlinable
    public func parent(of position: __TreePosition) -> __TreePosition? {
        guard let handle = try? _decode(position),
            let parentHandle = _parentHandle(of: handle)
        else { return nil }
        return _position(of: parentHandle)
    }

    // `childCount(of:)` is NOT a shared default: its return type is the conformer's
    // own child domain (`Index<Tree<Element>>.Count?` for the dynamic tree, the
    // bounded count for `Tree.N`, the key count for `Tree.Keyed`). Each conformer
    // surfaces it over the `_childCount` requirement.

    /// Whether the node at `position` is a leaf (has no children). `false` if invalid.
    @inlinable
    public func isLeaf(_ position: __TreePosition) -> Bool {
        guard let handle = try? _decode(position) else { return false }
        return _childCount(at: handle) == 0
    }

    // MARK: Element access

    /// Borrowing access to the element at `position`, or `nil` if invalid.
    @inlinable
    public func peek<R: ~Copyable>(
        at position: __TreePosition,
        _ body: (borrowing Element) -> R
    ) -> R? {
        guard let handle = try? _decode(position) else { return nil }
        return _withElement(at: handle, body)
    }

    // MARK: Mutation

    /// Inserts an element at the given insert position; returns the new node's position.
    ///
    /// Validates the child link BEFORE inserting the node (so no orphan is created
    /// on rejection), preserving each conformer's error precision.
    @inlinable
    @discardableResult
    public mutating func insert(
        _ element: consuming Element,
        at position: __TreeInsertPosition<Address>
    ) throws(__TreeError) -> __TreePosition {
        switch position {
        case .root:
            guard _rootHandle == nil else { throw .rootOccupied }
            let handle = _insertNode(element, parent: nil)
            _rootHandle = handle
            return _position(of: handle)

        case .child(of: let parent, at: let address):
            let parentHandle = try _decode(parent)
            try _validateLink(to: parentHandle, at: address)
            let handle = _insertNode(element, parent: parentHandle)
            _linkChild(handle, to: parentHandle, at: address)
            return _position(of: handle)
        }
    }

    /// Removes the leaf node at `position` and returns its element.
    @inlinable
    @discardableResult
    public mutating func remove(at position: __TreePosition) throws(__TreeError) -> Element {
        let handle = try _decode(position)
        guard _childCount(at: handle) == 0 else { throw .cannotRemoveNonLeaf }
        if let parentHandle = _parentHandle(of: handle) {
            _unlinkChild(handle, from: parentHandle)
        } else {
            _rootHandle = nil
        }
        return _removeNode(handle)
    }

    /// Removes every node from the tree.
    @inlinable
    public mutating func clear() { _removeAll() }

    /// The length of the longest root-to-leaf path, or `nil` if the tree is empty.
    ///
    /// A single-node tree has height `.zero`. Iterative traversal (deep-tree safe).
    @inlinable
    public var height: Index<Element>.Count? {
        guard let rootHandle = _rootHandle else { return nil }
        var maxDepth = 0
        var pending = Stack<(handle: Store.Generational.Handle, depth: Int)>()
        pending.push((rootHandle, 0))
        while let (handle, depth) = pending.pop() {
            maxDepth = Swift.max(maxDepth, depth)
            _forEachChild(at: handle) { pending.push(($0, depth + 1)) }
        }
        return Index<Element>.Count(UInt(maxDepth))
    }

    /// Removes the entire subtree rooted at `position` (post-order teardown).
    @inlinable
    public mutating func removeSubtree(at position: __TreePosition) throws(__TreeError) {
        let handle = try _decode(position)
        if let parentHandle = _parentHandle(of: handle) {
            _unlinkChild(handle, from: parentHandle)
        } else {
            _rootHandle = nil
        }
        // Two-stack post-order: a pre-order pass fills `output`; draining it frees
        // children before parents (the n-ary-safe teardown — a single lastVisited
        // scalar cannot disambiguate an n-ary node's completed child).
        var pending = Stack<Store.Generational.Handle>()
        var output = Stack<Store.Generational.Handle>()
        pending.push(handle)
        while let current = pending.pop() {
            output.push(current)
            _forEachChild(at: current) { pending.push($0) }
        }
        while let current = output.pop() {
            _ = _removeNode(current)
        }
    }

    // MARK: Traversal (closure-based; shared across all conformers)

    /// Visits every element in pre-order (root, then children left-to-right).
    @inlinable
    public func forEachPreOrder(_ body: (borrowing Element) -> Void) {
        guard let rootHandle = _rootHandle else { return }
        var pending = Stack<Store.Generational.Handle>()
        pending.push(rootHandle)
        while let current = pending.pop() {
            _withElement(at: current) { body($0) }
            var kids: [Store.Generational.Handle] = []
            _forEachChild(at: current) { kids.append($0) }
            for index in (0..<kids.count).reversed() { pending.push(kids[index]) }
        }
    }

    /// Visits every element in post-order (children left-to-right, then parent).
    @inlinable
    public func forEachPostOrder(_ body: (borrowing Element) -> Void) {
        guard let rootHandle = _rootHandle else { return }
        var pending = Stack<Store.Generational.Handle>()
        var output = Stack<Store.Generational.Handle>()
        pending.push(rootHandle)
        while let current = pending.pop() {
            output.push(current)
            _forEachChild(at: current) { pending.push($0) }
        }
        while let current = output.pop() {
            _withElement(at: current) { body($0) }
        }
    }

    /// Visits every element in level-order (breadth-first).
    @inlinable
    public func forEachLevelOrder(_ body: (borrowing Element) -> Void) {
        guard let rootHandle = _rootHandle else { return }
        var pending = Queue<Column.Ring<Store.Generational.Handle>>()
        pending.enqueue(rootHandle)
        while let current = pending.dequeue() {
            _withElement(at: current) { body($0) }
            _forEachChild(at: current) { pending.enqueue($0) }
        }
    }
}

// MARK: - Copyable-element conveniences

extension __TreeProtocol where Self: ~Copyable, Element: Copyable {
    /// The element at `position`, or `nil` if the position is invalid.
    @inlinable
    public func peek(at position: __TreePosition) -> Element? {
        peek(at: position) { $0 }
    }
}
