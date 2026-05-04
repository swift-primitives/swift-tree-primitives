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

public import Buffer_Arena_Primitives
public import Queue_Dynamic_Primitives
public import Queue_Primitives_Core
public import Stack_Primitives

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
        public typealias Node = Tree.N<n>.Node

        /// Typed node count.
        public typealias Count = Index<Node>.Count

        // MARK: - Storage

        @usableFromInline
        var _arena: Buffer<Node>.Arena.Bounded

        /// Index of root node (nil if empty).
        @usableFromInline
        var _rootIndex: Index<Node>?

        /// The maximum number of nodes the tree can hold.
        public let capacity: Count

        // MARK: - Helpers

        /// Converts a Position's typed index to a typed arena slot index.
        @inlinable
        func _slot(_ index: Index<Tree.Position>) -> Index<Node> {
            index.retag(Node.self)
        }

        /// Creates a tree with the specified capacity.
        ///
        /// - Parameter capacity: Maximum number of nodes.
        @inlinable
        public init(capacity: Count) {
            self.capacity = capacity
            self._arena = Buffer<Node>.Arena.Bounded(minimumCapacity: capacity)
            self._rootIndex = nil
        }

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

        /// The position of the root node, or `nil` if the tree is empty.
        @inlinable
        public var root: Tree.Position? {
            guard let rootIndex = _rootIndex else { return nil }
            let token = _arena.token(at: rootIndex)
            return Tree.Position(index: rootIndex, token: token)
        }

        // MARK: - Position Validation

        @usableFromInline
        func _validate(_ position: Tree.Position) throws(__TreeNBoundedError) {
            let arenaPos = Buffer<Node>.Arena.Position(
                index: UInt32(Int(bitPattern: position.index)),
                token: position.token
            )
            guard _arena.isValid(arenaPos) else { throw .invalidPosition }
        }
    }
}

// MARK: - Navigation

extension Tree.N.Bounded where Element: ~Copyable {

    /// Returns the position of the child at the given slot.
    @inlinable
    public func child(of position: Tree.Position, slot: Tree.N<n>.ChildSlot) -> Tree.Position? {
        do {
            try _validate(position)
        } catch {
            return nil
        }
        let nodePtr = unsafe _arena.pointer(at: _slot(position.index))
        guard let child = unsafe nodePtr.pointee.childIndices[slot.index] else { return nil }
        let token = _arena.token(at: child)
        return Tree.Position(index: child, token: token)
    }

    /// Returns the position of the parent of the node at the given position.
    @inlinable
    public func parent(of position: Tree.Position) -> Tree.Position? {
        do {
            try _validate(position)
        } catch {
            return nil
        }
        guard let parentIndex = unsafe _arena.pointer(at: _slot(position.index)).pointee.parentIndex else {
            return nil
        }
        let token = _arena.token(at: parentIndex)
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
        return unsafe _arena.pointer(at: _slot(position.index)).pointee.childCount == .zero
    }

    /// Returns the number of children of the node at the given position.
    @inlinable
    public func childCount(of position: Tree.Position) -> Count? {
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
        at position: Tree.N<n>.InsertPosition
    ) throws(__TreeNBoundedError) -> Tree.Position {
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

        case .child(of: let parent, let slot):
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
    public mutating func remove(at position: Tree.Position) throws(__TreeNBoundedError) -> Element {
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
    public mutating func removeSubtree(at position: Tree.Position) throws(__TreeNBoundedError) {
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
        _rootIndex = nil
    }

    /// Computes the height of the tree.
    ///
    /// An empty tree returns `nil`, a single-node tree has height `.zero`.
    @inlinable
    public var height: Count? {
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

extension Tree.N.Bounded where Element: ~Copyable {

    /// Iterates over all elements in pre-order.
    @inlinable
    public func forEachPreOrder(_ body: (borrowing Element) -> Void) {
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
    @inlinable
    public func forEachPostOrder(_ body: (borrowing Element) -> Void) {
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
    public func forEachLevelOrder(_ body: (borrowing Element) -> Void) {
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

// MARK: - Binary Tree In-Order Traversal (n == 2)

extension Tree.N.Bounded where Element: ~Copyable, n == 2 {

    /// Iterates over all elements in in-order.
    @inlinable
    public func forEachInOrder(_ body: (borrowing Element) -> Void) {
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
        at position: Tree.N<n>.InsertPosition
    ) throws(__TreeNBoundedError) -> Tree.Position {
        makeUnique()

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

        case .child(of: let parent, let slot):
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

extension Tree.N.Bounded: @unsafe @unchecked Sendable where Element: Sendable {}
