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

        // MARK: - Storage

        @usableFromInline
        var _storage: Storage

        /// Cached pointer to node storage.
        @usableFromInline
        var _cachedPtr: UnsafeMutablePointer<Node>

        /// Cached pointer to token buffer (owned by Storage).
        @usableFromInline
        var _tokens: UnsafeMutablePointer<UInt32>?

        /// Cached pointer to free-list next buffer (owned by Storage).
        @usableFromInline
        var _nextFree: UnsafeMutablePointer<Int>?

        /// The maximum number of nodes the tree can hold.
        public let capacity: Int

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
            self._storage = Storage.create(minimumCapacity: capacity)
            unsafe (self._cachedPtr = self._storage._nodesPointer)
            unsafe (self._tokens = self._storage._tokens)
            unsafe (self._nextFree = self._storage._nextFree)
        }

        // MARK: - Properties

        /// The number of nodes in the tree.
        @inlinable
        public var count: Int { _storage.header.count }

        /// Whether the tree is empty.
        @inlinable
        public var isEmpty: Bool { _storage.header.count == 0 }

        /// Whether the tree is full.
        @inlinable
        public var isFull: Bool { _storage.header.count >= capacity }

        /// The position of the root node, or `nil` if the tree is empty.
        @inlinable
        public var root: Tree.Position? {
            let rootIndex = _storage.header.rootIndex
            guard rootIndex >= 0, let tokens = unsafe _tokens else { return nil }
            return Tree.Position(index: rootIndex, token: unsafe tokens[rootIndex])
        }

        // MARK: - Position Validation

        @usableFromInline
        func _validate(_ position: Tree.Position) throws(__TreeNBoundedError) {
            guard position.index >= 0,
                  position.index < capacity,
                  let tokens = unsafe _tokens,
                  unsafe tokens[position.index] == position.token,
                  position.token & 1 == 1 else {
                throw .invalidPosition
            }
        }

        // MARK: - Slot Management

        @usableFromInline
        mutating func _allocateSlot() -> (index: Int, token: UInt32)? {
            let index: Int

            if _storage.header.freeHead >= 0 {
                index = _storage.header.freeHead
                if let nextFree = unsafe _nextFree {
                    _storage.header.freeHead = unsafe nextFree[index]
                }
            } else if _storage.header.count < capacity {
                index = _storage.header.count
            } else {
                return nil
            }

            if let tokens = unsafe _tokens {
                unsafe (tokens[index] &+= 1)
                return (index, unsafe tokens[index])
            } else {
                return (index, 1)
            }
        }

        @usableFromInline
        mutating func _freeSlot(_ index: Int) {
            if let tokens = unsafe _tokens {
                unsafe (tokens[index] &+= 1)
            }

            if let nextFree = unsafe _nextFree {
                unsafe (nextFree[index] = _storage.header.freeHead)
            }
            _storage.header.freeHead = index
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
        let childIndex = unsafe _cachedPtr[position.index].childIndices[slot.index]
        guard childIndex >= 0, let tokens = unsafe _tokens else { return nil }
        return Tree.Position(index: childIndex, token: unsafe tokens[childIndex])
    }

    /// Returns the position of the parent of the node at the given position.
    @inlinable
    public func parent(of position: Tree.Position) -> Tree.Position? {
        do {
            try _validate(position)
        } catch {
            return nil
        }
        let parentIndex = unsafe _cachedPtr[position.index].parentIndex
        guard parentIndex >= 0, let tokens = unsafe _tokens else { return nil }
        return Tree.Position(index: parentIndex, token: unsafe tokens[parentIndex])
    }

    /// Returns whether the node at the given position is a leaf.
    @inlinable
    public func isLeaf(_ position: Tree.Position) -> Bool {
        do {
            try _validate(position)
        } catch {
            return false
        }
        return unsafe _cachedPtr[position.index].childCount == 0
    }

    /// Returns the number of children of the node at the given position.
    @inlinable
    public func childCount(of position: Tree.Position) -> Int? {
        do {
            try _validate(position)
        } catch {
            return nil
        }
        return unsafe _cachedPtr[position.index].childCount
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
            guard _storage.header.rootIndex < 0 else {
                throw .slotOccupied
            }
            guard let (index, token) = _allocateSlot() else {
                throw .overflow
            }
            _storage._initializeNode(at: index, element: element)
            _storage.header.rootIndex = index
            _storage.header.count += 1
            return Tree.Position(index: index, token: token)

        case .child(of: let parent, slot: let slot):
            try _validate(parent)
            guard unsafe _cachedPtr[parent.index].childIndices[slot.index] < 0 else {
                throw .slotOccupied
            }
            guard let (index, token) = _allocateSlot() else {
                throw .overflow
            }
            _storage._initializeNode(at: index, element: element, parentIndex: parent.index)
            unsafe (_cachedPtr[parent.index].childIndices[slot.index] = index)
            unsafe (_cachedPtr[parent.index].childCount += 1)
            _storage.header.count += 1
            return Tree.Position(index: index, token: token)
        }
    }

    /// Removes the leaf node at the specified position.
    @inlinable
    @discardableResult
    public mutating func remove(at position: Tree.Position) throws(__TreeNBoundedError) -> Element {
        try _validate(position)

        guard unsafe _cachedPtr[position.index].childCount == 0 else {
            throw .cannotRemoveNonLeaf
        }

        let parentIndex = unsafe _cachedPtr[position.index].parentIndex
        if parentIndex >= 0 {
            for slot in 0..<n {
                if unsafe _cachedPtr[parentIndex].childIndices[slot] == position.index {
                    unsafe (_cachedPtr[parentIndex].childIndices[slot] = -1)
                    unsafe (_cachedPtr[parentIndex].childCount -= 1)
                    break
                }
            }
        } else {
            _storage.header.rootIndex = -1
        }

        let element = _storage._moveElement(at: position.index)
        _freeSlot(position.index)
        _storage.header.count -= 1

        return element
    }

    /// Removes the subtree rooted at the specified position.
    @inlinable
    public mutating func removeSubtree(at position: Tree.Position) throws(__TreeNBoundedError) {
        try _validate(position)

        let parentIndex = unsafe _cachedPtr[position.index].parentIndex
        if parentIndex >= 0 {
            for slot in 0..<n {
                if unsafe _cachedPtr[parentIndex].childIndices[slot] == position.index {
                    unsafe (_cachedPtr[parentIndex].childIndices[slot] = -1)
                    unsafe (_cachedPtr[parentIndex].childCount -= 1)
                    break
                }
            }
        } else {
            _storage.header.rootIndex = -1
        }

        var pending = Stack<Int>()
        var lastVisited: Int = -1

        pending.push(position.index)

        while !pending.isEmpty {
            let current = pending.peek()!

            var hasUnvisitedChild = false
            for slot in stride(from: n - 1, through: 0, by: -1) {
                let childIndex = unsafe _cachedPtr[current].childIndices[slot]
                if childIndex >= 0 && childIndex != lastVisited {
                    var laterChildVisited = false
                    for laterSlot in (slot + 1)..<n {
                        if unsafe _cachedPtr[current].childIndices[laterSlot] == lastVisited {
                            laterChildVisited = true
                            break
                        }
                    }
                    if !laterChildVisited {
                        pending.push(childIndex)
                        hasUnvisitedChild = true
                        break
                    }
                }
            }

            if !hasUnvisitedChild {
                _ = pending.pop()
                _storage._deinitializeNode(at: current)
                _freeSlot(current)
                _storage.header.count -= 1
                lastVisited = current
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
        return unsafe body(_cachedPtr[position.index].element)
    }

    /// Clears all nodes from the tree.
    @inlinable
    public mutating func clear() {
        guard _storage.header.count > 0 else { return }

        var pending = Stack<Int>()
        var lastVisited: Int = -1

        if _storage.header.rootIndex >= 0 {
            pending.push(_storage.header.rootIndex)
        }

        while !pending.isEmpty {
            let current = pending.peek()!

            var hasUnvisitedChild = false
            for slot in stride(from: n - 1, through: 0, by: -1) {
                let childIndex = unsafe _cachedPtr[current].childIndices[slot]
                if childIndex >= 0 && childIndex != lastVisited {
                    var laterChildVisited = false
                    for laterSlot in (slot + 1)..<n {
                        if unsafe _cachedPtr[current].childIndices[laterSlot] == lastVisited {
                            laterChildVisited = true
                            break
                        }
                    }
                    if !laterChildVisited {
                        pending.push(childIndex)
                        hasUnvisitedChild = true
                        break
                    }
                }
            }

            if !hasUnvisitedChild {
                _ = pending.pop()
                _storage._deinitializeNode(at: current)
                _freeSlot(current)
                lastVisited = current
            }
        }

        _storage.header.rootIndex = -1
        _storage.header.count = 0
        _storage.header.freeHead = -1
    }

    /// Computes the height of the tree.
    @inlinable
    public var height: Int {
        let rootIndex = _storage.header.rootIndex
        guard rootIndex >= 0 else { return -1 }

        var maxHeight = 0
        var pending = Stack<(index: Int, depth: Int)>()
        pending.push((rootIndex, 0))

        while !pending.isEmpty {
            let (index, depth) = pending.pop()!
            maxHeight = Swift.max(maxHeight, depth)

            for slot in 0..<n {
                let childIndex = unsafe _cachedPtr[index].childIndices[slot]
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
        if _storage.header.rootIndex >= 0 {
            pending.push(_storage.header.rootIndex)
        }

        while !pending.isEmpty {
            let index = pending.pop()!
            unsafe body(_cachedPtr[index].element)

            for slot in stride(from: n - 1, through: 0, by: -1) {
                let childIndex = unsafe _cachedPtr[index].childIndices[slot]
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

        if _storage.header.rootIndex >= 0 {
            pending.push(_storage.header.rootIndex)
        }

        while !pending.isEmpty {
            let current = pending.peek()!

            var hasUnvisitedChild = false
            for slot in stride(from: n - 1, through: 0, by: -1) {
                let childIndex = unsafe _cachedPtr[current].childIndices[slot]
                if childIndex >= 0 && childIndex != lastVisited {
                    var laterChildVisited = false
                    for laterSlot in (slot + 1)..<n {
                        if unsafe _cachedPtr[current].childIndices[laterSlot] == lastVisited {
                            laterChildVisited = true
                            break
                        }
                    }
                    if !laterChildVisited {
                        pending.push(childIndex)
                        hasUnvisitedChild = true
                        break
                    }
                }
            }

            if !hasUnvisitedChild {
                _ = pending.pop()
                unsafe body(_cachedPtr[current].element)
                lastVisited = current
            }
        }
    }

    /// Iterates over all elements in level-order.
    @inlinable
    public func forEachLevelOrder(_ body: (borrowing Element) -> Void) {
        guard _storage.header.rootIndex >= 0 else { return }

        var pending = Queue<Int>()
        pending.enqueue(_storage.header.rootIndex)

        while !pending.isEmpty {
            let index = pending.dequeue()!

            unsafe body(_cachedPtr[index].element)

            for slot in 0..<n {
                let childIndex = unsafe _cachedPtr[index].childIndices[slot]
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
        var current = _storage.header.rootIndex

        while current >= 0 || !pending.isEmpty {
            while current >= 0 {
                pending.push(current)
                current = unsafe _cachedPtr[current].childIndices[0]
            }

            current = pending.pop()!
            unsafe body(_cachedPtr[current].element)
            current = unsafe _cachedPtr[current].childIndices[1]
        }
    }
}

// MARK: - Copyable Element Extensions

extension Tree.N.Bounded where Element: Copyable {

    @usableFromInline
    mutating func _replaceStorage(_ newStorage: Tree.N<Element, n>.Storage) {
        _storage = newStorage
        unsafe (_cachedPtr = newStorage._nodesPointer)
        unsafe (_tokens = newStorage._tokens)
        unsafe (_nextFree = newStorage._nextFree)
    }

    @usableFromInline
    mutating func makeUnique() {
        if !isKnownUniquelyReferenced(&_storage) {
            let newStorage = Tree.N<Element, n>.Storage.create(minimumCapacity: capacity)
            _storage._copyAllElements(to: newStorage)
            _replaceStorage(newStorage)
        }
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
            guard _storage.header.rootIndex < 0 else {
                throw .slotOccupied
            }
            guard let (index, token) = _allocateSlot() else {
                throw .overflow
            }
            _storage._initializeNode(at: index, element: element)
            _storage.header.rootIndex = index
            _storage.header.count += 1
            return Tree.Position(index: index, token: token)

        case .child(of: let parent, slot: let slot):
            try _validate(parent)
            guard unsafe _cachedPtr[parent.index].childIndices[slot.index] < 0 else {
                throw .slotOccupied
            }
            guard let (index, token) = _allocateSlot() else {
                throw .overflow
            }
            _storage._initializeNode(at: index, element: element, parentIndex: parent.index)
            unsafe (_cachedPtr[parent.index].childIndices[slot.index] = index)
            unsafe (_cachedPtr[parent.index].childCount += 1)
            _storage.header.count += 1
            return Tree.Position(index: index, token: token)
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
        return unsafe _cachedPtr[position.index].element
    }
}

// MARK: - Traversal Sequences (Copyable elements only)

extension Tree.N.Bounded where Element: Copyable {

    /// A sequence that yields elements in pre-order.
    public var preOrder: PreOrderSequence {
        PreOrderSequence(tree: self)
    }

    /// A sequence that yields elements in post-order.
    public var postOrder: PostOrderSequence {
        PostOrderSequence(tree: self)
    }

    /// A sequence that yields elements in level-order.
    public var levelOrder: LevelOrderSequence {
        LevelOrderSequence(tree: self)
    }

    public struct PreOrderSequence: Sequence {
        let tree: Tree.N<Element, n>.Bounded

        public func makeIterator() -> PreOrderIterator {
            PreOrderIterator(tree: tree)
        }
    }

    public struct PreOrderIterator: IteratorProtocol {
        let tree: Tree.N<Element, n>.Bounded
        var pending: Stack<Int>

        init(tree: Tree.N<Element, n>.Bounded) {
            self.tree = tree
            self.pending = Stack<Int>()
            if tree._storage.header.rootIndex >= 0 {
                self.pending.push(tree._storage.header.rootIndex)
            }
        }

        public mutating func next() -> Element? {
            guard !pending.isEmpty else { return nil }

            let index = pending.pop()!
            let ptr = unsafe tree._cachedPtr
            let element = unsafe ptr[index].element

            for slot in stride(from: n - 1, through: 0, by: -1) {
                let childIndex = unsafe ptr[index].childIndices[slot]
                if childIndex >= 0 {
                    pending.push(childIndex)
                }
            }

            return element
        }
    }

    public struct PostOrderSequence: Sequence {
        let tree: Tree.N<Element, n>.Bounded

        public func makeIterator() -> PostOrderIterator {
            PostOrderIterator(tree: tree)
        }
    }

    public struct PostOrderIterator: IteratorProtocol {
        let tree: Tree.N<Element, n>.Bounded
        var pending: Stack<Int>
        var lastVisited: Int

        init(tree: Tree.N<Element, n>.Bounded) {
            self.tree = tree
            self.pending = Stack<Int>()
            self.lastVisited = -1
            if tree._storage.header.rootIndex >= 0 {
                pending.push(tree._storage.header.rootIndex)
            }
        }

        public mutating func next() -> Element? {
            let ptr = unsafe tree._cachedPtr

            while !pending.isEmpty {
                let current = pending.peek()!

                var hasUnvisitedChild = false
                for slot in stride(from: n - 1, through: 0, by: -1) {
                    let childIndex = unsafe ptr[current].childIndices[slot]
                    if childIndex >= 0 && childIndex != lastVisited {
                        var laterChildVisited = false
                        for laterSlot in (slot + 1)..<n {
                            if unsafe ptr[current].childIndices[laterSlot] == lastVisited {
                                laterChildVisited = true
                                break
                            }
                        }
                        if !laterChildVisited {
                            pending.push(childIndex)
                            hasUnvisitedChild = true
                            break
                        }
                    }
                }

                if !hasUnvisitedChild {
                    _ = pending.pop()
                    lastVisited = current
                    return unsafe ptr[current].element
                }
            }

            return nil
        }
    }

    public struct LevelOrderSequence: Sequence {
        let tree: Tree.N<Element, n>.Bounded

        public func makeIterator() -> LevelOrderIterator {
            LevelOrderIterator(tree: tree)
        }
    }

    public struct LevelOrderIterator: IteratorProtocol {
        let tree: Tree.N<Element, n>.Bounded
        var pending: Queue<Int>

        init(tree: Tree.N<Element, n>.Bounded) {
            self.tree = tree
            self.pending = Queue<Int>()
            if tree._storage.header.rootIndex >= 0 {
                pending.enqueue(tree._storage.header.rootIndex)
            }
        }

        public mutating func next() -> Element? {
            guard !pending.isEmpty else { return nil }

            let index = pending.dequeue()!
            let ptr = unsafe tree._cachedPtr
            let element = unsafe ptr[index].element

            for slot in 0..<n {
                let childIndex = unsafe ptr[index].childIndices[slot]
                if childIndex >= 0 {
                    pending.enqueue(childIndex)
                }
            }

            return element
        }
    }
}

// MARK: - Binary Tree In-Order Sequence (n == 2)

extension Tree.N.Bounded where Element: Copyable, n == 2 {

    /// A sequence that yields elements in in-order.
    public var inOrder: InOrderSequence {
        InOrderSequence(tree: self)
    }

    public struct InOrderSequence: Sequence {
        let tree: Tree.N<Element, n>.Bounded

        public func makeIterator() -> InOrderIterator {
            InOrderIterator(tree: tree)
        }
    }

    public struct InOrderIterator: IteratorProtocol {
        let tree: Tree.N<Element, n>.Bounded
        var pending: Stack<Int>
        var current: Int

        init(tree: Tree.N<Element, n>.Bounded) {
            self.tree = tree
            self.pending = Stack<Int>()
            self.current = tree._storage.header.rootIndex
        }

        public mutating func next() -> Element? {
            let ptr = unsafe tree._cachedPtr

            while current >= 0 || !pending.isEmpty {
                while current >= 0 {
                    pending.push(current)
                    current = unsafe ptr[current].childIndices[0]
                }

                current = pending.pop()!
                let element = unsafe ptr[current].element
                current = unsafe ptr[current].childIndices[1]

                return element
            }
            return nil
        }
    }
}

// MARK: - Conditional Copyable

extension Tree.N.Bounded: Copyable where Element: Copyable {}

// MARK: - Sendable

extension Tree.N.Bounded: @unchecked Sendable where Element: Sendable {}
