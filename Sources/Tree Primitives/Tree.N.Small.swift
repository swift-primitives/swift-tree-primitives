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

public import Queue_Primitives
public import Stack_Primitives
public import Buffer_Arena_Primitives

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
        @usableFromInline
        typealias Node = Tree.N<Element, n>.Node

        // MARK: - Storage

        @usableFromInline
        var _arena: Buffer<Node>.Arena.Small<inlineCapacity>

        /// Index of root node (-1 if empty).
        @usableFromInline
        var _rootIndex: Int

        // MARK: - Helpers

        /// Converts a raw Int index to a typed slot index.
        @inlinable
        func _slot(_ index: Int) -> Index<Node> {
            Index<Node>(Ordinal(UInt(index)))
        }

        /// Creates an empty small n-ary tree.
        @inlinable
        public init() {
            self._arena = Buffer<Node>.Arena.Small<inlineCapacity>()
            self._rootIndex = -1
        }

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
    public var count: Int {
        mutating get { Int(bitPattern: _arena.occupied) }
    }

    /// Whether the tree is empty.
    @inlinable
    public var isEmpty: Bool {
        mutating get { _arena.isEmpty }
    }

    /// The position of the root node, or `nil` if the tree is empty.
    @inlinable
    public var root: Tree.Position? {
        guard _rootIndex >= 0 else { return nil }
        return Tree.Position(index: _rootIndex, token: _arena.token(at: _slot(_rootIndex)))
    }

    // MARK: - Position Validation

    /// Validates that a position refers to a currently-occupied slot.
    @usableFromInline
    func _validate(_ position: Tree.Position) throws(__TreeNSmallError) {
        guard position.index >= 0 else { throw .invalidPosition }
        let token = _arena.token(at: _slot(position.index))
        guard token == position.token,
              position.token & 1 == 1 else {
            throw .invalidPosition
        }
    }

    // MARK: - Navigation

    /// Returns the position of a child at the given slot of the node at the given position.
    @inlinable
    public mutating func child(of position: Tree.Position, slot: Tree.N<Element, n>.ChildSlot) -> Tree.Position? {
        do {
            try _validate(position)
        } catch {
            return nil
        }
        let nodePtr = unsafe _arena.pointer(at: _slot(position.index))
        let childIndex = unsafe nodePtr.pointee.childIndices[slot.index]
        guard childIndex >= 0 else { return nil }
        return Tree.Position(index: childIndex, token: _arena.token(at: _slot(childIndex)))
    }

    /// Returns the position of the parent of the node at the given position.
    @inlinable
    public mutating func parent(of position: Tree.Position) -> Tree.Position? {
        do {
            try _validate(position)
        } catch {
            return nil
        }
        let parentIndex = unsafe _arena.pointer(at: _slot(position.index)).pointee.parentIndex
        guard parentIndex >= 0 else { return nil }
        return Tree.Position(index: parentIndex, token: _arena.token(at: _slot(parentIndex)))
    }

    /// Returns the number of children of the node at the given position.
    @inlinable
    public mutating func childCount(of position: Tree.Position) -> Int {
        do {
            try _validate(position)
        } catch {
            return 0
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
        return unsafe _arena.pointer(at: _slot(position.index)).pointee.childCount == 0
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
        at position: Tree.N<Element, n>.InsertPosition
    ) throws(__TreeNSmallError) -> Tree.Position {
        switch position {
        case .root:
            guard _rootIndex < 0 else {
                throw .slotOccupied
            }
            let arenaPos = _arena.insert(Node(element: element))
            _rootIndex = Int(arenaPos.index)
            return Tree.Position(index: Int(arenaPos.index), token: arenaPos.token)

        case .child(of: let parent, slot: let slot):
            try _validate(parent)
            do {
                let parentPtr = unsafe _arena.pointer(at: _slot(parent.index))
                guard unsafe parentPtr.pointee.childIndices[slot.index] < 0 else {
                    throw .slotOccupied
                }
            }
            let arenaPos = _arena.insert(
                Node(element: element, parentIndex: parent.index)
            )
            let index = Int(arenaPos.index)
            // Get fresh pointer after possible spill
            let parentPtr = unsafe _arena.pointer(at: _slot(parent.index))
            unsafe (parentPtr.pointee.childIndices[slot.index] = index)
            unsafe (parentPtr.pointee.childCount += 1)
            return Tree.Position(index: index, token: arenaPos.token)
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
        guard unsafe nodePtr.pointee.childCount == 0 else {
            throw .cannotRemoveNonLeaf
        }

        let parentIndex = unsafe nodePtr.pointee.parentIndex
        if parentIndex >= 0 {
            let parentPtr = unsafe _arena.pointer(at: _slot(parentIndex))
            for slot in 0..<n {
                if unsafe parentPtr.pointee.childIndices[slot] == position.index {
                    unsafe (parentPtr.pointee.childIndices[slot] = -1)
                    unsafe (parentPtr.pointee.childCount -= 1)
                    break
                }
            }
        } else {
            _rootIndex = -1
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

        let parentIndex = unsafe _arena.pointer(at: _slot(position.index)).pointee.parentIndex
        if parentIndex >= 0 {
            let parentPtr = unsafe _arena.pointer(at: _slot(parentIndex))
            for slot in 0..<n {
                if unsafe parentPtr.pointee.childIndices[slot] == position.index {
                    unsafe (parentPtr.pointee.childIndices[slot] = -1)
                    unsafe (parentPtr.pointee.childCount -= 1)
                    break
                }
            }
        } else {
            _rootIndex = -1
        }

        var pending = Stack<Int>()
        var lastVisited: Int = -1

        pending.push(position.index)

        while !pending.isEmpty {
            let current = pending.peek()!
            let nodePtr = unsafe _arena.pointer(at: _slot(current))
            let childIndices = unsafe nodePtr.pointee.childIndices

            var rightmostChildIndex: Int = -1
            for slot in stride(from: n - 1, through: 0, by: -1) {
                if childIndices[slot] >= 0 {
                    rightmostChildIndex = childIndices[slot]
                    break
                }
            }

            var leftmostChildIndex: Int = -1
            for slot in 0..<n {
                if childIndices[slot] >= 0 {
                    leftmostChildIndex = childIndices[slot]
                    break
                }
            }

            let isLeaf = rightmostChildIndex < 0
            let cameFromRightmost = rightmostChildIndex >= 0 && rightmostChildIndex == lastVisited
            let cameFromLeftmostNoOther = leftmostChildIndex >= 0 && leftmostChildIndex == lastVisited && leftmostChildIndex == rightmostChildIndex

            if isLeaf || cameFromRightmost || cameFromLeftmostNoOther {
                _ = pending.pop()
                _arena.free(at: _slot(current))
                lastVisited = current
            } else {
                for slot in stride(from: n - 1, through: 0, by: -1) {
                    let childIndex = childIndices[slot]
                    if childIndex >= 0 {
                        pending.push(childIndex)
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
        _rootIndex = -1
    }

    /// Iterates over all elements in pre-order.
    ///
    /// Uses iterative traversal to avoid stack overflow on deep trees.
    @inlinable
    public mutating func forEachPreOrder(_ body: (borrowing Element) -> Void) {
        var pending = Stack<Int>()
        if _rootIndex >= 0 {
            pending.push(_rootIndex)
        }

        while !pending.isEmpty {
            let index = pending.pop()!
            let nodePtr = unsafe _arena.pointer(at: _slot(index))
            unsafe body(nodePtr.pointee.element)

            for slot in stride(from: n - 1, through: 0, by: -1) {
                let childIndex = unsafe nodePtr.pointee.childIndices[slot]
                if childIndex >= 0 {
                    pending.push(childIndex)
                }
            }
        }
    }

    /// Iterates over all elements in post-order.
    ///
    /// Uses iterative traversal to avoid stack overflow on deep trees.
    @inlinable
    public mutating func forEachPostOrder(_ body: (borrowing Element) -> Void) {
        var pending = Stack<Int>()
        var lastVisited: Int = -1

        if _rootIndex >= 0 {
            pending.push(_rootIndex)
        }

        while !pending.isEmpty {
            let current = pending.peek()!
            let nodePtr = unsafe _arena.pointer(at: _slot(current))
            let childIndices = unsafe nodePtr.pointee.childIndices

            var rightmostChildIndex: Int = -1
            for slot in stride(from: n - 1, through: 0, by: -1) {
                if childIndices[slot] >= 0 {
                    rightmostChildIndex = childIndices[slot]
                    break
                }
            }

            var leftmostChildIndex: Int = -1
            for slot in 0..<n {
                if childIndices[slot] >= 0 {
                    leftmostChildIndex = childIndices[slot]
                    break
                }
            }

            let isLeaf = rightmostChildIndex < 0
            let cameFromRightmost = rightmostChildIndex >= 0 && rightmostChildIndex == lastVisited
            let cameFromLeftmostNoOther = leftmostChildIndex >= 0 && leftmostChildIndex == lastVisited && leftmostChildIndex == rightmostChildIndex

            if isLeaf || cameFromRightmost || cameFromLeftmostNoOther {
                _ = pending.pop()
                unsafe body(nodePtr.pointee.element)
                lastVisited = current
            } else {
                for slot in stride(from: n - 1, through: 0, by: -1) {
                    let childIndex = childIndices[slot]
                    if childIndex >= 0 {
                        pending.push(childIndex)
                    }
                }
            }
        }
    }

    /// Iterates over all elements in level-order.
    @inlinable
    public mutating func forEachLevelOrder(_ body: (borrowing Element) -> Void) {
        guard _rootIndex >= 0 else { return }

        var pending = Queue<Int>()
        pending.enqueue(_rootIndex)

        while !pending.isEmpty {
            let index = pending.dequeue()!
            let nodePtr = unsafe _arena.pointer(at: _slot(index))

            unsafe body(nodePtr.pointee.element)

            for slot in 0..<n {
                let childIndex = unsafe nodePtr.pointee.childIndices[slot]
                if childIndex >= 0 {
                    pending.enqueue(childIndex)
                }
            }
        }
    }

    /// Computes the height of the tree.
    ///
    /// Uses iterative traversal to avoid stack overflow on deep trees.
    @inlinable
    public mutating func height() -> Int {
        guard _rootIndex >= 0 else { return -1 }

        var maxHeight = 0
        var pending = Stack<(index: Int, depth: Int)>()
        pending.push((_rootIndex, 0))

        while !pending.isEmpty {
            let (index, depth) = pending.pop()!
            maxHeight = Swift.max(maxHeight, depth)

            let nodePtr = unsafe _arena.pointer(at: _slot(index))
            for slot in 0..<n {
                let childIndex = unsafe nodePtr.pointee.childIndices[slot]
                if childIndex >= 0 {
                    pending.push((childIndex, depth + 1))
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
        var pending = Stack<Int>()
        var current = _rootIndex

        while current >= 0 || !pending.isEmpty {
            while current >= 0 {
                pending.push(current)
                current = unsafe _arena.pointer(at: _slot(current)).pointee.childIndices[0]
            }

            current = pending.pop()!
            let nodePtr = unsafe _arena.pointer(at: _slot(current))
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

extension Tree.N.Small: @unchecked Sendable where Element: Sendable {}
