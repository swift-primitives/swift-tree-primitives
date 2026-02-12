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

// MARK: - Bounded N-ary Tree

extension Tree.N where Element: ~Copyable {

    /// A fixed-capacity n-ary tree.
    ///
    /// `N.Bounded` allocates storage upfront and throws on overflow.
    /// Use this variant when capacity is known or in contexts requiring
    /// predictable memory behavior (embedded, real-time).
    ///
    /// ## Example
    ///
    /// ```swift
    /// var tree = try Tree<Int>.N<2>.Bounded(capacity: 100)
    /// let root = try tree.insert(1, at: .root)
    /// let left = try tree.insert(2, at: .left(of: root))
    /// ```
    @safe
    public struct Bounded: ~Copyable {

        // MARK: - Typealiases

        /// Errors that can occur during bounded n-ary tree operations.
        public typealias Error = __TreeNBoundedError

        /// Node type from parent Tree.N.
        @usableFromInline
        typealias Node = Tree.N<Element, n>.Node

        // MARK: - Storage

        @usableFromInline
        var _arena: Buffer<Node>.Arena.Bounded

        /// Index of root node (-1 if empty).
        @usableFromInline
        var _rootIndex: Int

        /// The maximum number of nodes the tree can hold.
        public let capacity: Int

        // MARK: - Helpers

        /// Converts a raw Int index to a typed slot index.
        @inlinable
        func _slot(_ index: Int) -> Index<Node> {
            Index<Node>(Ordinal(UInt(index)))
        }

        /// Creates a tree with the specified capacity.
        ///
        /// - Parameter capacity: Maximum number of nodes. Must be non-negative.
        /// - Throws: ``Error/invalidCapacity`` if capacity is negative.
        @inlinable
        public init(capacity: Int) throws(__TreeNBoundedError) {
            guard capacity >= 0 else {
                throw .invalidCapacity
            }
            self.capacity = capacity
            self._arena = Buffer<Node>.Arena.Bounded(
                minimumCapacity: Index<Node>.Count(Cardinal(UInt(capacity)))
            )
            self._rootIndex = -1
        }

        // MARK: - Properties

        /// The number of nodes in the tree.
        @inlinable
        public var count: Int { Int(bitPattern: _arena.occupied) }

        /// Whether the tree is empty.
        @inlinable
        public var isEmpty: Bool { _arena.isEmpty }

        /// Whether the tree is full.
        @inlinable
        public var isFull: Bool { _arena.isFull }

        /// The position of the root node, or `nil` if the tree is empty.
        @inlinable
        public var root: Tree.Position? {
            guard _rootIndex >= 0 else { return nil }
            let token = _arena.token(at: _slot(_rootIndex))
            return Tree.Position(index: _rootIndex, token: token)
        }

        // MARK: - Position Validation

        @usableFromInline
        func _validate(_ position: Tree.Position) throws(__TreeNBoundedError) {
            guard position.index >= 0 else { throw .invalidPosition }
            let arenaPos = Buffer<Node>.Arena.Position(
                index: UInt32(position.index), token: position.token
            )
            guard _arena.isValid(arenaPos) else { throw .invalidPosition }
        }
    }
}

// MARK: - Navigation

extension Tree.N.Bounded where Element: ~Copyable {

    /// Returns the position of the child at the given slot.
    @inlinable
    public func child(of position: Tree.Position, slot: Tree.N<Element, n>.ChildSlot) -> Tree.Position? {
        do {
            try _validate(position)
        } catch {
            return nil
        }
        let nodePtr = unsafe _arena.pointer(at: _slot(position.index))
        let childIndex = unsafe nodePtr.pointee.childIndices[slot.index]
        guard childIndex >= 0 else { return nil }
        let token = _arena.token(at: _slot(childIndex))
        return Tree.Position(index: childIndex, token: token)
    }

    /// Returns the position of the parent of the node at the given position.
    @inlinable
    public func parent(of position: Tree.Position) -> Tree.Position? {
        do {
            try _validate(position)
        } catch {
            return nil
        }
        let parentIndex = unsafe _arena.pointer(at: _slot(position.index)).pointee.parentIndex
        guard parentIndex >= 0 else { return nil }
        let token = _arena.token(at: _slot(parentIndex))
        return Tree.Position(index: parentIndex, token: token)
    }

    /// Returns whether the node at the given position is a leaf.
    @inlinable
    public func isLeaf(_ position: Tree.Position) -> Bool {
        do {
            try _validate(position)
        } catch {
            return false
        }
        return unsafe _arena.pointer(at: _slot(position.index)).pointee.childCount == 0
    }

    /// Returns the number of children of the node at the given position.
    @inlinable
    public func childCount(of position: Tree.Position) -> Int? {
        do {
            try _validate(position)
        } catch {
            return nil
        }
        return unsafe _arena.pointer(at: _slot(position.index)).pointee.childCount
    }
}

// MARK: - Binary Tree Navigation Convenience (n == 2)

extension Tree.N.Bounded where Element: ~Copyable, n == 2 {

    /// Returns the position of the left child.
    @inlinable
    public func left(of position: Tree.Position) -> Tree.Position? {
        child(of: position, slot: .left)
    }

    /// Returns the position of the right child.
    @inlinable
    public func right(of position: Tree.Position) -> Tree.Position? {
        child(of: position, slot: .right)
    }
}

// MARK: - Insert Operations (~Copyable)

extension Tree.N.Bounded where Element: ~Copyable {

    /// Inserts an element at the specified position.
    @inlinable
    @discardableResult
    public mutating func insert(
        _ element: consuming Element,
        at position: Tree.N<Element, n>.InsertPosition
    ) throws(__TreeNBoundedError) -> Tree.Position {
        switch position {
        case .root:
            guard _rootIndex < 0 else {
                throw .slotOccupied
            }
            guard !_arena.isFull else {
                throw .overflow
            }
            let arenaPos: Buffer<Node>.Arena.Position
            do {
                arenaPos = try _arena.insert(Node(element: element))
            } catch {
                throw .overflow
            }
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
            guard !_arena.isFull else {
                throw .overflow
            }
            let arenaPos: Buffer<Node>.Arena.Position
            do {
                arenaPos = try _arena.insert(
                    Node(element: element, parentIndex: parent.index)
                )
            } catch {
                throw .overflow
            }
            let index = Int(arenaPos.index)
            let parentPtr = unsafe _arena.pointer(at: _slot(parent.index))
            unsafe (parentPtr.pointee.childIndices[slot.index] = index)
            unsafe (parentPtr.pointee.childCount += 1)
            return Tree.Position(index: index, token: arenaPos.token)
        }
    }

    /// Removes the leaf node at the specified position.
    @inlinable
    @discardableResult
    public mutating func remove(at position: Tree.Position) throws(__TreeNBoundedError) -> Element {
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
    public mutating func removeSubtree(at position: Tree.Position) throws(__TreeNBoundedError) {
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
    public func peek<R>(at position: Tree.Position, _ body: (borrowing Element) -> R) -> R? {
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

    /// Computes the height of the tree.
    @inlinable
    public var height: Int {
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

// MARK: - Traversal

extension Tree.N.Bounded where Element: ~Copyable {

    /// Iterates over all elements in pre-order.
    @inlinable
    public func forEachPreOrder(_ body: (borrowing Element) -> Void) {
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
    @inlinable
    public func forEachPostOrder(_ body: (borrowing Element) -> Void) {
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
    public func forEachLevelOrder(_ body: (borrowing Element) -> Void) {
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
}

// MARK: - Binary Tree In-Order Traversal (n == 2)

extension Tree.N.Bounded where Element: ~Copyable, n == 2 {

    /// Iterates over all elements in in-order.
    @inlinable
    public func forEachInOrder(_ body: (borrowing Element) -> Void) {
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

// MARK: - Copyable Element Extensions

extension Tree.N.Bounded where Element: Copyable {

    /// Ensures unique storage, copying if necessary for copy-on-write.
    @usableFromInline
    mutating func makeUnique() {
        _arena.ensureUnique()
    }

    /// Inserts an element at the specified position (CoW-aware).
    @inlinable
    @discardableResult
    public mutating func insert(
        _ element: Element,
        at position: Tree.N<Element, n>.InsertPosition
    ) throws(__TreeNBoundedError) -> Tree.Position {
        makeUnique()

        switch position {
        case .root:
            guard _rootIndex < 0 else {
                throw .slotOccupied
            }
            guard !_arena.isFull else {
                throw .overflow
            }
            let arenaPos: Buffer<Node>.Arena.Position
            do {
                arenaPos = try _arena.insert(Node(element: element))
            } catch {
                throw .overflow
            }
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
            guard !_arena.isFull else {
                throw .overflow
            }
            let arenaPos: Buffer<Node>.Arena.Position
            do {
                arenaPos = try _arena.insert(
                    Node(element: element, parentIndex: parent.index)
                )
            } catch {
                throw .overflow
            }
            let index = Int(arenaPos.index)
            let parentPtr = unsafe _arena.pointer(at: _slot(parent.index))
            unsafe (parentPtr.pointee.childIndices[slot.index] = index)
            unsafe (parentPtr.pointee.childCount += 1)
            return Tree.Position(index: index, token: arenaPos.token)
        }
    }

    /// Returns the element at the specified position.
    @inlinable
    public func peek(at position: Tree.Position) -> Element? {
        do {
            try _validate(position)
        } catch {
            return nil
        }
        return unsafe _arena.pointer(at: _slot(position.index)).pointee.element
    }
}

// MARK: - Traversal Sequences (Copyable elements only)

extension Tree.N.Bounded where Element: Copyable {

    /// A sequence that yields elements in pre-order.
    public var preOrder: Order.Pre.Sequence {
        Order.Pre.Sequence(tree: self)
    }

    /// A sequence that yields elements in post-order.
    public var postOrder: Order.Post.Sequence {
        Order.Post.Sequence(tree: self)
    }

    /// A sequence that yields elements in level-order.
    public var levelOrder: Order.Level.Sequence {
        Order.Level.Sequence(tree: self)
    }
}

// MARK: - Binary Tree In-Order Sequence (n == 2)

extension Tree.N.Bounded where Element: Copyable, n == 2 {

    /// A sequence that yields elements in in-order.
    public var inOrder: Order.In.Sequence {
        Order.In.Sequence(tree: self)
    }
}

// MARK: - Conditional Copyable

extension Tree.N.Bounded: Copyable where Element: Copyable {}

// MARK: - Sendable

extension Tree.N.Bounded: @unchecked Sendable where Element: Sendable {}
