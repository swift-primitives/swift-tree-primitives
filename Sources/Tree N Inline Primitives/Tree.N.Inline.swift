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

public import Queue_Primitives_Core
public import Queue_Dynamic_Primitives
public import Stack_Primitives
internal import Buffer_Arena_Primitives

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
        public typealias Node = Tree.N<n>.Node

        /// Typed node count.
        public typealias Count = Index<Node>.Count

        // MARK: - Storage

        /// Index of root node (nil if empty).
        @usableFromInline
        var _rootIndex: Index<Node>?

        @usableFromInline
        var _arena: Buffer<Node>.Arena.Inline<capacity>

        // MARK: - Helpers

        /// Converts a Position's typed index to a typed arena slot index.
        @inlinable
        func _slot(_ index: Index<Tree.Position>) -> Index<Node> {
            index.retag(Node.self)
        }

        /// Creates an empty inline n-ary tree.
        @inlinable
        public init() {
            self._rootIndex = nil
            self._arena = Buffer<Node>.Arena.Inline<capacity>()
        }

        // Element cleanup is handled by Buffer.Arena.Inline's deinit, which
        // iterates meta and deinitializes all occupied slots. No workarounds
        // needed at this layer — Buffer.Arena.Inline owns _deinitWorkaround.

        // MARK: - Properties

        /// The number of nodes in the tree.
        @inlinable
        public var count: Count { _arena.occupied }

        /// Whether the tree is empty.
        @inlinable
        public var isEmpty: Bool { _arena.isEmpty }

        /// Whether the tree is full.
        @inlinable
        public var isFull: Bool { _arena.isFull }

        /// The position of the root node.
        @inlinable
        public var root: Tree.Position? {
            guard let rootIndex = _rootIndex else { return nil }
            return Tree.Position(index: rootIndex, token: _arena.token(at: rootIndex))
        }

        // MARK: - Position Validation

        @usableFromInline
        func _validate(_ position: Tree.Position) throws(__TreeNInlineError) {
            guard Int(bitPattern: position.index) < capacity else { throw .invalidPosition }
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

    /// Returns the position of the parent.
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

    /// Returns whether the node is a leaf.
    @inlinable
    public mutating func isLeaf(_ position: Tree.Position) -> Bool {
        do {
            try _validate(position)
        } catch {
            return false
        }
        return unsafe _arena.pointer(at: _slot(position.index)).pointee.childCount == .zero
    }

    /// Returns the number of children.
    @inlinable
    public mutating func childCount(of position: Tree.Position) -> Count? {
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
        at position: Tree.N<n>.InsertPosition
    ) throws(__TreeNInlineError) -> Tree.Position {
        switch position {
        case .root:
            guard _rootIndex == nil else {
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
            _rootIndex = arenaPos.slot
            return Tree.Position(index: arenaPos.slot, token: arenaPos.token)

        case .child(of: let parent, slot: let slot):
            try _validate(parent)
            do {
                let parentPtr = unsafe _arena.pointer(at: _slot(parent.index))
                guard unsafe parentPtr.pointee.childIndices[slot.index] == nil else {
                    throw .slotOccupied
                }
            }
            guard !_arena.isFull else {
                throw .overflow
            }
            let arenaPos: Buffer<Node>.Arena.Position
            do {
                arenaPos = try _arena.insert(
                    Node(element: element, parentIndex: _slot(parent.index))
                )
            } catch {
                throw .overflow
            }
            let parentPtr = unsafe _arena.pointer(at: _slot(parent.index))
            unsafe (parentPtr.pointee.childIndices[slot.index] = arenaPos.slot)
            unsafe (parentPtr.pointee.childCount += .one)
            return Tree.Position(index: arenaPos.slot, token: arenaPos.token)
        }
    }

    /// Removes the leaf node at the specified position.
    @inlinable
    @discardableResult
    public mutating func remove(at position: Tree.Position) throws(__TreeNInlineError) -> Element {
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
    public mutating func removeSubtree(at position: Tree.Position) throws(__TreeNInlineError) {
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
        _rootIndex = nil
    }

    /// Computes the height of the tree.
    ///
    /// An empty tree returns `nil`, a single-node tree has height `.zero`.
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

// MARK: - Traversal

extension Tree.N.Inline where Element: ~Copyable {

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
}

// MARK: - Binary Tree In-Order (n == 2)

extension Tree.N.Inline where Element: ~Copyable, n == 2 {

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
