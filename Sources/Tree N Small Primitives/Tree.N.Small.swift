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

internal import Buffer_Arena_Primitives
public import Queue_Dynamic_Primitives
public import Queue_Primitives_Core
public import Stack_Primitives

/// A small-buffer optimized n-ary tree with inline storage and spill to heap.
///
/// `Tree.N.Small<inlineCapacity>` uses inline storage for up to `inlineCapacity` nodes,
/// automatically spilling to heap storage when the inline capacity is exceeded.
/// This provides the best of both worlds: zero allocation for small trees and
/// automatic growth for larger ones.
///
/// ## Example
///
/// ```swift
/// // Binary tree with inline capacity of 7 nodes (e.g., a complete tree of depth 2)
/// var tree = Tree<Int>.N<2>.Small<7>()
/// let root = try tree.insert(1, at: .root)
/// let left = try tree.insert(2, at: .left(of: root))
/// let right = try tree.insert(3, at: .right(of: root))
/// print(tree.isSpilled)  // false - still using inline storage
/// ```
///
/// ## Spill Behavior
///
/// When the tree exceeds `inlineCapacity` nodes, all nodes are moved to heap-based
/// storage. The `isSpilled` property indicates whether the tree has transitioned
/// to heap storage. Once spilled, the tree never returns to inline storage.
///
/// ## Move-Only
///
/// `Tree.N.Small` is unconditionally `~Copyable` (move-only) because it uses
/// `@_rawLayout` inline storage that requires a deinitializer.
extension Tree.N where Element: ~Copyable {

    @safe
    public struct Small<let inlineCapacity: Int>: ~Copyable {

        // MARK: - Typealiases

        /// Errors that can occur during small n-ary tree operations.
        public typealias Error = __TreeNSmallError

        /// Node type from parent Tree.N.
        public typealias Node = Tree.N<n>.Node

        /// Typed node count.
        public typealias Count = Index<Node>.Count

        // MARK: - Storage

        /// Index of root node (nil if empty).
        @usableFromInline
        var _rootIndex: Index<Node>?

        @usableFromInline
        var _arena: Buffer<Node>.Arena.Small<inlineCapacity>

        // MARK: - Helpers

        /// Converts a Position's typed index to a typed arena slot index.
        @inlinable
        func _slot(_ index: Index<Tree.Position>) -> Index<Node> {
            index.retag(Node.self)
        }

        /// Creates an empty small n-ary tree.
        @inlinable
        public init() {
            self._rootIndex = nil
            self._arena = Buffer<Node>.Arena.Small<inlineCapacity>()
        }

        // Element cleanup is handled by Buffer.Arena.Inline's deinit (inline case)
        // or Storage.Arena's class deinit (heap case). No workarounds needed at
        // this layer — Buffer.Arena.Inline owns _deinitWorkaround.

        /// Whether the tree is currently using heap storage.
        @inlinable
        public var isSpilled: Bool {
            mutating get { _arena.isSpilled }
        }
    }
}

// MARK: - Small Properties

extension Tree.N.Small {

    /// The number of nodes in the tree.
    @inlinable
    public var count: Count {
        mutating get { _arena.occupied }
    }

    /// Whether the tree is empty.
    @inlinable
    public var isEmpty: Bool {
        mutating get { _arena.isEmpty }
    }

    /// The position of the root node, or `nil` if the tree is empty.
    @inlinable
    public var root: Tree.Position? {
        guard let rootIndex = _rootIndex else { return nil }
        return Tree.Position(index: rootIndex, token: _arena.token(at: rootIndex))
    }

    // MARK: - Position Validation

    /// Validates that a position refers to a currently-occupied slot.
    @usableFromInline
    func _validate(_ position: Tree.Position) throws(__TreeNSmallError) {
        let token = _arena.token(at: _slot(position.index))
        guard token == position.token,
            position.token & 1 == 1
        else {
            throw .invalidPosition
        }
    }

    // MARK: - Navigation

    /// Returns the position of a child at the given slot of the node at the given position.
    @inlinable
    public mutating func child(of position: Tree.Position, slot: Tree.N<n>.ChildSlot) -> Tree.Position? {
        do {
            try _validate(position)
        } catch {
            return nil
        }
        let nodePtr = unsafe _arena.pointer(at: _slot(position.index))
        guard let child = unsafe nodePtr.pointee.childIndices[slot.index] else { return nil }
        return Tree.Position(index: child, token: _arena.token(at: child))
    }

    /// Returns the position of the parent of the node at the given position.
    @inlinable
    public mutating func parent(of position: Tree.Position) -> Tree.Position? {
        do {
            try _validate(position)
        } catch {
            return nil
        }
        guard let parentIndex = unsafe _arena.pointer(at: _slot(position.index)).pointee.parentIndex else {
            return nil
        }
        return Tree.Position(index: parentIndex, token: _arena.token(at: parentIndex))
    }

    /// Returns the number of children of the node at the given position.
    @inlinable
    public mutating func childCount(of position: Tree.Position) -> Count? {
        do {
            try _validate(position)
        } catch {
            return nil
        }
        return unsafe _arena.pointer(at: _slot(position.index)).pointee.childCount
    }

    /// Returns whether the node at the given position is a leaf.
    @inlinable
    public mutating func isLeaf(_ position: Tree.Position) -> Bool {
        do {
            try _validate(position)
        } catch {
            return false
        }
        return unsafe _arena.pointer(at: _slot(position.index)).pointee.childCount == .zero
    }
}

// MARK: - Binary Tree Navigation (n == 2)

extension Tree.N.Small where n == 2 {

    /// Returns the position of the left child of the node at the given position.
    @inlinable
    public mutating func left(of position: Tree.Position) -> Tree.Position? {
        child(of: position, slot: .left)
    }

    /// Returns the position of the right child of the node at the given position.
    @inlinable
    public mutating func right(of position: Tree.Position) -> Tree.Position? {
        child(of: position, slot: .right)
    }
}

// MARK: - Small Insert Operations

extension Tree.N.Small {

    /// Inserts an element at the specified position.
    @inlinable
    @discardableResult
    public mutating func insert(
        _ element: consuming Element,
        at position: Tree.N<n>.InsertPosition
    ) throws(__TreeNSmallError) -> Tree.Position {
        switch position {
        case .root:
            guard _rootIndex == nil else {
                throw .slotOccupied
            }
            let arenaPos = _arena.insert(Node(element: element))
            _rootIndex = arenaPos.slot
            return Tree.Position(index: arenaPos.slot, token: arenaPos.token)

        case .child(of: let parent, let slot):
            try _validate(parent)
            do {
                let parentPtr = unsafe _arena.pointer(at: _slot(parent.index))
                guard unsafe parentPtr.pointee.childIndices[slot.index] == nil else {
                    throw .slotOccupied
                }
            }
            let arenaPos = _arena.insert(
                Node(element: element, parentIndex: _slot(parent.index))
            )
            // Get fresh pointer after possible spill
            let parentPtr = unsafe _arena.pointer(at: _slot(parent.index))
            unsafe (parentPtr.pointee.childIndices[slot.index] = arenaPos.slot)
            unsafe (parentPtr.pointee.childCount += .one)
            return Tree.Position(index: arenaPos.slot, token: arenaPos.token)
        }
    }

    /// Removes the leaf node at the specified position.
    @inlinable
    @discardableResult
    public mutating func remove(
        at position: Tree.Position
    ) throws(__TreeNSmallError) -> Element {
        try _validate(position)

        let nodePtr = unsafe _arena.pointer(at: _slot(position.index))
        guard unsafe nodePtr.pointee.childCount == .zero else {
            throw .cannotRemoveNonLeaf
        }

        if let parentIndex = unsafe nodePtr.pointee.parentIndex {
            let parentPtr = unsafe _arena.pointer(at: parentIndex)
            for slot in 0..<n {
                if unsafe parentPtr.pointee.childIndices[slot] == _slot(position.index) {
                    unsafe (parentPtr.pointee.childIndices[slot] = nil)
                    unsafe (parentPtr.pointee.childCount = parentPtr.pointee.childCount.subtract.saturating(.one))
                    break
                }
            }
        } else {
            _rootIndex = nil
        }

        let node = _arena.remove(at: _slot(position.index))
        return node.element
    }

    /// Removes the subtree rooted at the specified position.
    @inlinable
    public mutating func removeSubtree(
        at position: Tree.Position
    ) throws(__TreeNSmallError) {
        try _validate(position)

        if let parentIndex = unsafe _arena.pointer(at: _slot(position.index)).pointee.parentIndex {
            let parentPtr = unsafe _arena.pointer(at: parentIndex)
            for slot in 0..<n {
                if unsafe parentPtr.pointee.childIndices[slot] == _slot(position.index) {
                    unsafe (parentPtr.pointee.childIndices[slot] = nil)
                    unsafe (parentPtr.pointee.childCount = parentPtr.pointee.childCount.subtract.saturating(.one))
                    break
                }
            }
        } else {
            _rootIndex = nil
        }

        var pending = Stack<Index<Node>>()
        var lastVisited: Index<Node>? = nil

        pending.push(_slot(position.index))

        while !pending.isEmpty {
            let current = pending.peek()!
            let nodePtr = unsafe _arena.pointer(at: current)
            let childIndices = unsafe nodePtr.pointee.childIndices

            var rightmostChild: Index<Node>? = nil
            for slot in stride(from: n - 1, through: 0, by: -1) {
                if let child = childIndices[slot] {
                    rightmostChild = child
                    break
                }
            }

            var leftmostChild: Index<Node>? = nil
            for slot in 0..<n {
                if let child = childIndices[slot] {
                    leftmostChild = child
                    break
                }
            }

            let isLeaf = rightmostChild == nil
            let cameFromRightmost = rightmostChild != nil && rightmostChild == lastVisited
            let cameFromLeftmostNoOther = leftmostChild != nil && leftmostChild == lastVisited && leftmostChild == rightmostChild

            if isLeaf || cameFromRightmost || cameFromLeftmostNoOther {
                _ = pending.pop()
                _arena.free(at: current)
                lastVisited = current
            } else {
                for slot in stride(from: n - 1, through: 0, by: -1) {
                    if let child = childIndices[slot] {
                        pending.push(child)
                    }
                }
            }
        }
    }

    /// Accesses the element at the specified position via a borrowing closure.
    @inlinable
    public mutating func peek<R>(
        at position: Tree.Position,
        _ body: (borrowing Element) -> R
    ) -> R? {
        do {
            try _validate(position)
        } catch {
            return nil
        }
        return unsafe body(_arena.pointer(at: _slot(position.index)).pointee.element)
    }

    /// Clears all nodes from the tree.
    @inlinable
    public mutating func clear() {
        _arena.removeAll()
        _rootIndex = nil
    }

    /// Iterates over all elements in pre-order.
    ///
    /// Uses iterative traversal to avoid stack overflow on deep trees.
    @inlinable
    public mutating func forEachPreOrder(_ body: (borrowing Element) -> Void) {
        guard let rootIndex = _rootIndex else { return }
        var pending = Stack<Index<Node>>()
        pending.push(rootIndex)

        while !pending.isEmpty {
            let index = pending.pop()!
            let nodePtr = unsafe _arena.pointer(at: index)
            unsafe body(nodePtr.pointee.element)

            for slot in stride(from: n - 1, through: 0, by: -1) {
                if let child = unsafe nodePtr.pointee.childIndices[slot] {
                    pending.push(child)
                }
            }
        }
    }

    /// Iterates over all elements in post-order.
    ///
    /// Uses iterative traversal to avoid stack overflow on deep trees.
    @inlinable
    public mutating func forEachPostOrder(_ body: (borrowing Element) -> Void) {
        guard let rootIndex = _rootIndex else { return }
        var pending = Stack<Index<Node>>()
        var lastVisited: Index<Node>? = nil
        pending.push(rootIndex)

        while !pending.isEmpty {
            let current = pending.peek()!
            let nodePtr = unsafe _arena.pointer(at: current)
            let childIndices = unsafe nodePtr.pointee.childIndices

            var rightmostChild: Index<Node>? = nil
            for slot in stride(from: n - 1, through: 0, by: -1) {
                if let child = childIndices[slot] {
                    rightmostChild = child
                    break
                }
            }

            var leftmostChild: Index<Node>? = nil
            for slot in 0..<n {
                if let child = childIndices[slot] {
                    leftmostChild = child
                    break
                }
            }

            let isLeaf = rightmostChild == nil
            let cameFromRightmost = rightmostChild != nil && rightmostChild == lastVisited
            let cameFromLeftmostNoOther = leftmostChild != nil && leftmostChild == lastVisited && leftmostChild == rightmostChild

            if isLeaf || cameFromRightmost || cameFromLeftmostNoOther {
                _ = pending.pop()
                unsafe body(nodePtr.pointee.element)
                lastVisited = current
            } else {
                for slot in stride(from: n - 1, through: 0, by: -1) {
                    if let child = childIndices[slot] {
                        pending.push(child)
                    }
                }
            }
        }
    }

    /// Iterates over all elements in level-order.
    @inlinable
    public mutating func forEachLevelOrder(_ body: (borrowing Element) -> Void) {
        guard let rootIndex = _rootIndex else { return }

        var pending = Queue<Index<Node>>()
        pending.enqueue(rootIndex)

        while !pending.isEmpty {
            let index = pending.dequeue()!
            let nodePtr = unsafe _arena.pointer(at: index)

            unsafe body(nodePtr.pointee.element)

            for slot in 0..<n {
                if let child = unsafe nodePtr.pointee.childIndices[slot] {
                    pending.enqueue(child)
                }
            }
        }
    }

    /// Computes the height of the tree.
    ///
    /// An empty tree returns `nil`, a single-node tree has height `.zero`.
    /// Uses iterative traversal to avoid stack overflow on deep trees.
    @inlinable
    public mutating func height() -> Count? {
        guard let rootIndex = _rootIndex else { return nil }

        var maxHeight: Count = .zero
        var pending = Stack<(index: Index<Node>, depth: Count)>()
        pending.push((rootIndex, .zero))

        while !pending.isEmpty {
            let (index, depth) = pending.pop()!
            maxHeight = Swift.max(maxHeight, depth)

            let nodePtr = unsafe _arena.pointer(at: index)
            for slot in 0..<n {
                if let child = unsafe nodePtr.pointee.childIndices[slot] {
                    pending.push((child, depth + .one))
                }
            }
        }

        return maxHeight
    }
}

// MARK: - Binary Tree In-Order (n == 2)

extension Tree.N.Small where n == 2 {

    /// Iterates over all elements in in-order (left, root, right).
    ///
    /// Only available for binary trees (n == 2).
    /// Uses iterative traversal to avoid stack overflow on deep trees.
    @inlinable
    public mutating func forEachInOrder(_ body: (borrowing Element) -> Void) {
        guard let rootIndex = _rootIndex else { return }
        var pending = Stack<Index<Node>>()
        var current: Index<Node>? = rootIndex

        while current != nil || !pending.isEmpty {
            while let c = current {
                pending.push(c)
                current = unsafe _arena.pointer(at: c).pointee.childIndices[0]
            }

            let c = pending.pop()!
            let nodePtr = unsafe _arena.pointer(at: c)
            unsafe body(nodePtr.pointee.element)
            current = unsafe nodePtr.pointee.childIndices[1]
        }
    }
}

// MARK: - Small Copyable Extensions

extension Tree.N.Small where Element: Copyable {

    /// Returns the element at the specified position.
    @inlinable
    public mutating func peek(at position: Tree.Position) -> Element? {
        do {
            try _validate(position)
        } catch {
            return nil
        }
        return unsafe _arena.pointer(at: _slot(position.index)).pointee.element
    }
}

// MARK: - Sendable

extension Tree.N.Small: @unsafe @unchecked Sendable where Element: Sendable {}
