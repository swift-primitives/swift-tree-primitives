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

// MARK: - Inline N-ary Tree

extension Tree.N where Element: ~Copyable {

    /// A fixed-capacity, inline-storage n-ary tree with compile-time capacity.
    ///
    /// `N.Inline` stores nodes directly within the struct's memory layout,
    /// requiring no heap allocation. The capacity is specified as a compile-time
    /// generic parameter.
    ///
    /// ## Example
    ///
    /// ```swift
    /// var tree = Tree<Int>.N<2>.Inline<16>()
    /// let root = try tree.insert(1, at: .root)
    /// ```
    ///
    /// ## Non-Copyable
    ///
    /// `N.Inline` is unconditionally `~Copyable` (move-only) because it uses
    /// `@_rawLayout` inline storage that requires a deinitializer.
    public struct Inline<let capacity: Int>: ~Copyable {

        // MARK: - Typealiases

        /// Errors that can occur during inline n-ary tree operations.
        public typealias Error = __TreeNInlineError

        /// Node type from parent Tree.N.
        @usableFromInline
        typealias Node = Tree.N<Element, n>.Node

        // MARK: - Storage

        @usableFromInline
        var _arena: Buffer<Node>.Arena.Inline<capacity>

        /// Index of root node (-1 if empty).
        @usableFromInline
        var _rootIndex: Int

        // MARK: - Helpers

        /// Converts a raw Int index to a typed slot index.
        @inlinable
        func _slot(_ index: Int) -> Index<Node> {
            Index<Node>(Ordinal(UInt(index)))
        }

        /// Creates an empty inline n-ary tree.
        @inlinable
        public init() {
            self._arena = Buffer<Node>.Arena.Inline<capacity>()
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

        /// The position of the root node.
        @inlinable
        public var root: Tree.Position? {
            guard _rootIndex >= 0 else { return nil }
            return Tree.Position(index: _rootIndex, token: _arena.token(at: _slot(_rootIndex)))
        }

        // MARK: - Position Validation

        @usableFromInline
        func _validate(_ position: Tree.Position) throws(__TreeNInlineError) {
            guard position.index >= 0,
                  position.index < capacity else { throw .invalidPosition }
            let token = _arena.token(at: _slot(position.index))
            guard token == position.token,
                  position.token & 1 == 1 else {
                throw .invalidPosition
            }
        }
    }
}

// MARK: - Navigation

extension Tree.N.Inline where Element: ~Copyable {

    /// Returns the position of the child at the given slot.
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

    /// Returns the position of the parent.
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

    /// Returns whether the node is a leaf.
    @inlinable
    public mutating func isLeaf(_ position: Tree.Position) -> Bool {
        do {
            try _validate(position)
        } catch {
            return false
        }
        return unsafe _arena.pointer(at: _slot(position.index)).pointee.childCount == 0
    }

    /// Returns the number of children.
    @inlinable
    public mutating func childCount(of position: Tree.Position) -> Int? {
        do {
            try _validate(position)
        } catch {
            return nil
        }
        return unsafe _arena.pointer(at: _slot(position.index)).pointee.childCount
    }
}

// MARK: - Binary Tree Navigation (n == 2)

extension Tree.N.Inline where Element: ~Copyable, n == 2 {

    @inlinable
    public mutating func left(of position: Tree.Position) -> Tree.Position? {
        child(of: position, slot: .left)
    }

    @inlinable
    public mutating func right(of position: Tree.Position) -> Tree.Position? {
        child(of: position, slot: .right)
    }
}

// MARK: - Insert Operations

extension Tree.N.Inline where Element: ~Copyable {

    /// Inserts an element at the specified position.
    @inlinable
    @discardableResult
    public mutating func insert(
        _ element: consuming Element,
        at position: Tree.N<Element, n>.InsertPosition
    ) throws(__TreeNInlineError) -> Tree.Position {
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
    public mutating func remove(at position: Tree.Position) throws(__TreeNInlineError) -> Element {
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
    public mutating func removeSubtree(at position: Tree.Position) throws(__TreeNInlineError) {
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

    /// Accesses the element via a borrowing closure.
    @inlinable
    public mutating func peek<R>(at position: Tree.Position, _ body: (borrowing Element) -> R) -> R? {
        do {
            try _validate(position)
        } catch {
            return nil
        }
        return unsafe body(_arena.pointer(at: _slot(position.index)).pointee.element)
    }

    /// Clears all nodes.
    @inlinable
    public mutating func clear() {
        _arena.removeAll()
        _rootIndex = -1
    }

    /// Computes the height of the tree.
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

// MARK: - Traversal

extension Tree.N.Inline where Element: ~Copyable {

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
}

// MARK: - Binary Tree In-Order (n == 2)

extension Tree.N.Inline where Element: ~Copyable, n == 2 {

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

// MARK: - Copyable Extensions

extension Tree.N.Inline where Element: Copyable {

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

extension Tree.N.Inline: @unchecked Sendable where Element: Sendable {}
