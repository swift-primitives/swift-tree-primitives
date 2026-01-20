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
    /// `N.Inline` is unconditionally `~Copyable` (move-only) because it requires
    /// a deinitializer to clean up inline storage.
    public struct Inline<let capacity: Int>: ~Copyable {

        // MARK: - Typealiases

        /// Errors that can occur during inline n-ary tree operations.
        public typealias Error = __TreeNInlineError

        /// Maximum node stride supported by inline storage (128 bytes per slot).
        @usableFromInline
        static var _maxStride: Int { 128 }

        /// Inline node with fixed indices.
        @usableFromInline
        struct InlineNode {
            @usableFromInline
            var slot: (Int, Int, Int, Int, Int, Int, Int, Int, Int, Int, Int, Int, Int, Int, Int, Int)
            @usableFromInline
            var childIndices: InlineArray<n, Int>
            @usableFromInline
            var childCount: Int
            @usableFromInline
            var parentIndex: Int
            @usableFromInline
            var isOccupied: Bool

            @usableFromInline
            init() {
                self.slot = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
                self.childIndices = InlineArray(repeating: -1)
                self.childCount = 0
                self.parentIndex = -1
                self.isOccupied = false
            }
        }

        /// Raw storage for nodes.
        @usableFromInline
        var _storage: InlineArray<capacity, InlineNode>

        /// Token buffer for position validation.
        @usableFromInline
        var _tokens: InlineArray<capacity, UInt32>

        /// Free-list next pointers.
        @usableFromInline
        var _nextFree: InlineArray<capacity, Int>

        @usableFromInline
        var _rootIndex: Int

        @usableFromInline
        var _count: Int

        @usableFromInline
        var _freeHead: Int

        /// Workaround for Swift compiler bug with ~Copyable deinit.
        @usableFromInline
        var _deinitWorkaround: AnyObject? = nil

        /// Creates an empty inline n-ary tree.
        ///
        /// - Throws: ``Error/elementStrideTooLarge`` if the element stride exceeds inline storage,
        ///           ``Error/elementAlignmentTooLarge`` if the element alignment exceeds inline slot alignment.
        @inlinable
        public init() throws(__TreeNInlineError) {
            guard MemoryLayout<Element>.stride <= Self._maxStride else {
                throw .elementStrideTooLarge
            }
            guard MemoryLayout<Element>.alignment <= MemoryLayout<Int>.alignment else {
                throw .elementAlignmentTooLarge
            }
            self._storage = InlineArray(repeating: InlineNode())
            self._tokens = InlineArray(repeating: 0)
            self._nextFree = InlineArray(repeating: -1)
            self._rootIndex = -1
            self._count = 0
            self._freeHead = -1
        }

        deinit {
            let count = _count
            guard count > 0 else { return }

            var `deinit` = Queue<Int>()
            `deinit`.reserve(count)

            var pending = Stack<Int>()
            var lastVisited: Int = -1

            if _rootIndex >= 0 {
                pending.push(_rootIndex)
            }

            while !pending.isEmpty {
                let current = pending.peek()!

                var hasUnvisitedChild = false
                for slot in stride(from: n - 1, through: 0, by: -1) {
                    let childIndex = _storage[current].childIndices[slot]
                    if childIndex >= 0 && childIndex != lastVisited {
                        var laterChildVisited = false
                        for laterSlot in (slot + 1)..<n {
                            if _storage[current].childIndices[laterSlot] == lastVisited {
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
                    `deinit`.enqueue(current)
                    lastVisited = current
                }
            }

            let nodeStride = MemoryLayout<InlineNode>.stride
            let slotOffset = MemoryLayout<InlineNode>.offset(of: \.slot) ?? 0

            unsafe Swift.withUnsafePointer(to: _storage) { storagePtr in
                let basePtr = unsafe UnsafeMutableRawPointer(mutating: unsafe UnsafeRawPointer(storagePtr))
                while !`deinit`.isEmpty {
                    let index = `deinit`.dequeue()!
                    let nodePtr = unsafe basePtr + index * nodeStride
                    let elementPtr = unsafe (nodePtr + slotOffset)
                        .assumingMemoryBound(to: Element.self)
                    unsafe elementPtr.deinitialize(count: 1)
                }
            }
        }

        // MARK: - Properties

        /// The number of nodes in the tree.
        @inlinable
        public var count: Int { _count }

        /// Whether the tree is empty.
        @inlinable
        public var isEmpty: Bool { _count == 0 }

        /// Whether the tree is full.
        @inlinable
        public var isFull: Bool { _count >= capacity }

        /// The position of the root node.
        @inlinable
        public var root: Tree.Position? {
            guard _rootIndex >= 0 else { return nil }
            return Tree.Position(index: _rootIndex, token: _tokens[_rootIndex])
        }

        // MARK: - Position Validation

        @usableFromInline
        func _validate(_ position: Tree.Position) throws(__TreeNInlineError) {
            guard position.index >= 0,
                  position.index < capacity,
                  _tokens[position.index] == position.token,
                  position.token & 1 == 1 else {
                throw .invalidPosition
            }
        }

        // MARK: - Slot Management

        @usableFromInline
        mutating func _allocateSlot() -> (index: Int, token: UInt32)? {
            let index: Int

            if _freeHead >= 0 {
                index = _freeHead
                _freeHead = _nextFree[index]
            } else if _count < capacity {
                var actualIndex = -1
                for i in 0..<capacity {
                    if !_storage[i].isOccupied {
                        actualIndex = i
                        break
                    }
                }
                if actualIndex < 0 {
                    return nil
                }
                _tokens[actualIndex] &+= 1
                return (actualIndex, _tokens[actualIndex])
            } else {
                return nil
            }

            _tokens[index] &+= 1
            return (index, _tokens[index])
        }

        @usableFromInline
        mutating func _freeSlot(_ index: Int) {
            _storage[index].isOccupied = false
            _tokens[index] &+= 1
            _nextFree[index] = _freeHead
            _freeHead = index
        }

        @usableFromInline
        @unsafe
        mutating func _elementPointer(at index: Int) -> UnsafeMutablePointer<Element> {
            unsafe Swift.withUnsafeMutablePointer(to: &_storage[index].slot) { slotPtr in
                unsafe UnsafeMutableRawPointer(slotPtr).assumingMemoryBound(to: Element.self)
            }
        }

        @usableFromInline
        @unsafe
        func _readElementPointer(at index: Int) -> UnsafePointer<Element> {
            unsafe Swift.withUnsafePointer(to: _storage[index].slot) { slotPtr in
                unsafe UnsafeRawPointer(slotPtr).assumingMemoryBound(to: Element.self)
            }
        }
    }
}

// MARK: - Navigation

extension Tree.N.Inline where Element: ~Copyable {

    /// Returns the position of the child at the given slot.
    @inlinable
    public func child(of position: Tree.Position, slot: Tree.N<Element, n>.ChildSlot) -> Tree.Position? {
        do {
            try _validate(position)
        } catch {
            return nil
        }
        let childIndex = _storage[position.index].childIndices[slot.index]
        guard childIndex >= 0 else { return nil }
        return Tree.Position(index: childIndex, token: _tokens[childIndex])
    }

    /// Returns the position of the parent.
    @inlinable
    public func parent(of position: Tree.Position) -> Tree.Position? {
        do {
            try _validate(position)
        } catch {
            return nil
        }
        let parentIndex = _storage[position.index].parentIndex
        guard parentIndex >= 0 else { return nil }
        return Tree.Position(index: parentIndex, token: _tokens[parentIndex])
    }

    /// Returns whether the node is a leaf.
    @inlinable
    public func isLeaf(_ position: Tree.Position) -> Bool {
        do {
            try _validate(position)
        } catch {
            return false
        }
        return _storage[position.index].childCount == 0
    }

    /// Returns the number of children.
    @inlinable
    public func childCount(of position: Tree.Position) -> Int? {
        do {
            try _validate(position)
        } catch {
            return nil
        }
        return _storage[position.index].childCount
    }
}

// MARK: - Binary Tree Navigation (n == 2)

extension Tree.N.Inline where Element: ~Copyable, n == 2 {

    @inlinable
    public func left(of position: Tree.Position) -> Tree.Position? {
        child(of: position, slot: .left)
    }

    @inlinable
    public func right(of position: Tree.Position) -> Tree.Position? {
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
            guard let (index, token) = _allocateSlot() else {
                throw .overflow
            }
            unsafe _elementPointer(at: index).initialize(to: element)
            _storage[index].childIndices = InlineArray(repeating: -1)
            _storage[index].childCount = 0
            _storage[index].parentIndex = -1
            _storage[index].isOccupied = true
            _rootIndex = index
            _count += 1
            return Tree.Position(index: index, token: token)

        case .child(of: let parent, slot: let slot):
            try _validate(parent)
            guard _storage[parent.index].childIndices[slot.index] < 0 else {
                throw .slotOccupied
            }
            guard let (index, token) = _allocateSlot() else {
                throw .overflow
            }
            unsafe _elementPointer(at: index).initialize(to: element)
            _storage[index].childIndices = InlineArray(repeating: -1)
            _storage[index].childCount = 0
            _storage[index].parentIndex = parent.index
            _storage[index].isOccupied = true
            _storage[parent.index].childIndices[slot.index] = index
            _storage[parent.index].childCount += 1
            _count += 1
            return Tree.Position(index: index, token: token)
        }
    }

    /// Removes the leaf node at the specified position.
    @inlinable
    @discardableResult
    public mutating func remove(at position: Tree.Position) throws(__TreeNInlineError) -> Element {
        try _validate(position)

        guard _storage[position.index].childCount == 0 else {
            throw .cannotRemoveNonLeaf
        }

        let parentIndex = _storage[position.index].parentIndex
        if parentIndex >= 0 {
            for slot in 0..<n {
                if _storage[parentIndex].childIndices[slot] == position.index {
                    _storage[parentIndex].childIndices[slot] = -1
                    _storage[parentIndex].childCount -= 1
                    break
                }
            }
        } else {
            _rootIndex = -1
        }

        let element = unsafe _elementPointer(at: position.index).move()
        _freeSlot(position.index)
        _count -= 1

        return element
    }

    /// Removes the subtree rooted at the specified position.
    @inlinable
    public mutating func removeSubtree(at position: Tree.Position) throws(__TreeNInlineError) {
        try _validate(position)

        let parentIndex = _storage[position.index].parentIndex
        if parentIndex >= 0 {
            for slot in 0..<n {
                if _storage[parentIndex].childIndices[slot] == position.index {
                    _storage[parentIndex].childIndices[slot] = -1
                    _storage[parentIndex].childCount -= 1
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

            var hasUnvisitedChild = false
            for slot in stride(from: n - 1, through: 0, by: -1) {
                let childIndex = _storage[current].childIndices[slot]
                if childIndex >= 0 && childIndex != lastVisited {
                    var laterChildVisited = false
                    for laterSlot in (slot + 1)..<n {
                        if _storage[current].childIndices[laterSlot] == lastVisited {
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
                _ = unsafe _elementPointer(at: current).move()
                _freeSlot(current)
                _count -= 1
                lastVisited = current
            }
        }
    }

    /// Accesses the element via a borrowing closure.
    @inlinable
    public func peek<R>(at position: Tree.Position, _ body: (borrowing Element) -> R) -> R? {
        do {
            try _validate(position)
        } catch {
            return nil
        }
        return unsafe body(_readElementPointer(at: position.index).pointee)
    }

    /// Clears all nodes.
    @inlinable
    public mutating func clear() {
        guard _count > 0 else { return }

        var pending = Stack<Int>()
        var lastVisited: Int = -1

        if _rootIndex >= 0 {
            pending.push(_rootIndex)
        }

        while !pending.isEmpty {
            let current = pending.peek()!

            var hasUnvisitedChild = false
            for slot in stride(from: n - 1, through: 0, by: -1) {
                let childIndex = _storage[current].childIndices[slot]
                if childIndex >= 0 && childIndex != lastVisited {
                    var laterChildVisited = false
                    for laterSlot in (slot + 1)..<n {
                        if _storage[current].childIndices[laterSlot] == lastVisited {
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
                _ = unsafe _elementPointer(at: current).move()
                _freeSlot(current)
                lastVisited = current
            }
        }

        _rootIndex = -1
        _count = 0
        _freeHead = -1
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

            for slot in 0..<n {
                let childIndex = _storage[index].childIndices[slot]
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
    public func forEachPreOrder(_ body: (borrowing Element) -> Void) {
        var pending = Stack<Int>()
        if _rootIndex >= 0 {
            pending.push(_rootIndex)
        }

        while !pending.isEmpty {
            let index = pending.pop()!
            unsafe body(_readElementPointer(at: index).pointee)

            for slot in stride(from: n - 1, through: 0, by: -1) {
                let childIndex = _storage[index].childIndices[slot]
                if childIndex >= 0 {
                    pending.push(childIndex)
                }
            }
        }
    }

    @inlinable
    public func forEachPostOrder(_ body: (borrowing Element) -> Void) {
        var pending = Stack<Int>()
        var lastVisited: Int = -1

        if _rootIndex >= 0 {
            pending.push(_rootIndex)
        }

        while !pending.isEmpty {
            let current = pending.peek()!

            var hasUnvisitedChild = false
            for slot in stride(from: n - 1, through: 0, by: -1) {
                let childIndex = _storage[current].childIndices[slot]
                if childIndex >= 0 && childIndex != lastVisited {
                    var laterChildVisited = false
                    for laterSlot in (slot + 1)..<n {
                        if _storage[current].childIndices[laterSlot] == lastVisited {
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
                unsafe body(_readElementPointer(at: current).pointee)
                lastVisited = current
            }
        }
    }

    @inlinable
    public func forEachLevelOrder(_ body: (borrowing Element) -> Void) {
        guard _rootIndex >= 0 else { return }

        var pending = Queue<Int>()
        pending.enqueue(_rootIndex)

        while !pending.isEmpty {
            let index = pending.dequeue()!

            unsafe body(_readElementPointer(at: index).pointee)

            for slot in 0..<n {
                let childIndex = _storage[index].childIndices[slot]
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
    public func forEachInOrder(_ body: (borrowing Element) -> Void) {
        var pending = Stack<Int>()
        var current = _rootIndex

        while current >= 0 || !pending.isEmpty {
            while current >= 0 {
                pending.push(current)
                current = _storage[current].childIndices[0]
            }

            current = pending.pop()!
            unsafe body(_readElementPointer(at: current).pointee)
            current = _storage[current].childIndices[1]
        }
    }
}

// MARK: - Copyable Extensions

extension Tree.N.Inline where Element: Copyable {

    /// Returns the element at the specified position.
    @inlinable
    public func peek(at position: Tree.Position) -> Element? {
        do {
            try _validate(position)
        } catch {
            return nil
        }
        return unsafe _readElementPointer(at: position.index).pointee
    }
}

// MARK: - Sendable

extension Tree.N.Inline: @unchecked Sendable where Element: Sendable {}
