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

// MARK: - Inline Properties

extension Tree.Binary.Inline where Element: ~Copyable {

    /// The number of nodes in the tree.
    @inlinable
    public var count: Int { _count }

    /// Whether the tree is empty.
    @inlinable
    public var isEmpty: Bool { _count == 0 }

    /// Whether the tree is full.
    @inlinable
    public var isFull: Bool { _count >= capacity }

    /// The position of the root node, or `nil` if the tree is empty.
    @inlinable
    public var root: Tree.Binary<Element>.Position? {
        guard _rootIndex >= 0 else { return nil }
        return Tree.Binary<Element>.Position(index: _rootIndex, token: _tokens[_rootIndex])
    }

    // MARK: - Position Validation

    /// Validates that a position refers to a currently-occupied slot.
    @usableFromInline
    func _validate(_ position: Tree.Binary<Element>.Position) throws(__TreeBinaryInlineError) {
        guard position.index >= 0,
              position.index < capacity,
              _tokens[position.index] == position.token,
              position.token & 1 == 1 else {
            throw .invalidPosition
        }
    }

    // MARK: - Navigation

    /// Returns the position of the left child of the node at the given position.
    @inlinable
    public func left(of position: Tree.Binary<Element>.Position) -> Tree.Binary<Element>.Position? {
        do {
            try _validate(position)
        } catch {
            return nil
        }
        let leftIndex = _storage[position.index].leftIndex
        guard leftIndex >= 0 else { return nil }
        return Tree.Binary<Element>.Position(index: leftIndex, token: _tokens[leftIndex])
    }

    /// Returns the position of the right child of the node at the given position.
    @inlinable
    public func right(of position: Tree.Binary<Element>.Position) -> Tree.Binary<Element>.Position? {
        do {
            try _validate(position)
        } catch {
            return nil
        }
        let rightIndex = _storage[position.index].rightIndex
        guard rightIndex >= 0 else { return nil }
        return Tree.Binary<Element>.Position(index: rightIndex, token: _tokens[rightIndex])
    }

    /// Returns the position of the parent of the node at the given position.
    @inlinable
    public func parent(of position: Tree.Binary<Element>.Position) -> Tree.Binary<Element>.Position? {
        do {
            try _validate(position)
        } catch {
            return nil
        }
        let parentIndex = _storage[position.index].parentIndex
        guard parentIndex >= 0 else { return nil }
        return Tree.Binary<Element>.Position(index: parentIndex, token: _tokens[parentIndex])
    }

    /// Returns whether the node at the given position is a leaf.
    @inlinable
    public func isLeaf(_ position: Tree.Binary<Element>.Position) -> Bool {
        do {
            try _validate(position)
        } catch {
            return false
        }
        let node = _storage[position.index]
        return node.leftIndex < 0 && node.rightIndex < 0
    }

    // MARK: - Slot Management

    /// Allocates a slot for a new node, returning a token-stamped position.
    @usableFromInline
    mutating func _allocateSlot() -> (index: Int, token: UInt32)? {
        let index: Int

        // Try to reuse from free list
        if _freeHead >= 0 {
            index = _freeHead
            _freeHead = _nextFree[index]
        } else if _count < capacity {
            // Find first unoccupied slot
            var found = false
            index = _count  // Default to count
            for i in 0..<capacity {
                if !_storage[i].isOccupied {
                    // Use this slot
                    found = true
                    // Can't reassign index in this scope, handle differently
                    break
                }
            }
            if !found {
                return nil
            }
            // Find the actual slot
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
            // Increment token: even (free) → odd (occupied)
            _tokens[actualIndex] &+= 1
            return (actualIndex, _tokens[actualIndex])
        } else {
            return nil
        }

        // Increment token: even (free) → odd (occupied)
        _tokens[index] &+= 1
        return (index, _tokens[index])
    }

    /// Returns a slot to the free list.
    @usableFromInline
    mutating func _freeSlot(_ index: Int) {
        _storage[index].isOccupied = false
        // Increment token: odd (occupied) → even (free)
        _tokens[index] &+= 1
        // Add to free list
        _nextFree[index] = _freeHead
        _freeHead = index
    }

    /// Returns a pointer to the element in a slot.
    @usableFromInline
    @unsafe
    mutating func _elementPointer(at index: Int) -> UnsafeMutablePointer<Element> {
        unsafe Swift.withUnsafeMutablePointer(to: &_storage[index].slot) { slotPtr in
            unsafe UnsafeMutableRawPointer(slotPtr).assumingMemoryBound(to: Element.self)
        }
    }

    /// Returns a read pointer to the element in a slot.
    @usableFromInline
    @unsafe
    func _readElementPointer(at index: Int) -> UnsafePointer<Element> {
        unsafe Swift.withUnsafePointer(to: _storage[index].slot) { slotPtr in
            unsafe UnsafeRawPointer(slotPtr).assumingMemoryBound(to: Element.self)
        }
    }
}

// MARK: - Inline Insert Operations (~Copyable)

extension Tree.Binary.Inline where Element: ~Copyable {

    /// Inserts an element at the specified position.
    @inlinable
    @discardableResult
    public mutating func insert(
        _ element: consuming Element,
        at position: Tree.Binary<Element>.InsertPosition
    ) throws(__TreeBinaryInlineError) -> Tree.Binary<Element>.Position {
        switch position {
        case .root:
            guard _rootIndex < 0 else {
                throw .positionOccupied
            }
            guard let (index, token) = _allocateSlot() else {
                throw .overflow
            }
            unsafe _elementPointer(at: index).initialize(to: element)
            _storage[index].leftIndex = -1
            _storage[index].rightIndex = -1
            _storage[index].parentIndex = -1
            _storage[index].isOccupied = true
            _rootIndex = index
            _count += 1
            return Tree.Binary<Element>.Position(index: index, token: token)

        case .left(of: let parent):
            // Validate parent position (token check)
            try _validate(parent)
            guard _storage[parent.index].leftIndex < 0 else {
                throw .positionOccupied
            }
            guard let (index, token) = _allocateSlot() else {
                throw .overflow
            }
            unsafe _elementPointer(at: index).initialize(to: element)
            _storage[index].leftIndex = -1
            _storage[index].rightIndex = -1
            _storage[index].parentIndex = parent.index
            _storage[index].isOccupied = true
            _storage[parent.index].leftIndex = index
            _count += 1
            return Tree.Binary<Element>.Position(index: index, token: token)

        case .right(of: let parent):
            // Validate parent position (token check)
            try _validate(parent)
            guard _storage[parent.index].rightIndex < 0 else {
                throw .positionOccupied
            }
            guard let (index, token) = _allocateSlot() else {
                throw .overflow
            }
            unsafe _elementPointer(at: index).initialize(to: element)
            _storage[index].leftIndex = -1
            _storage[index].rightIndex = -1
            _storage[index].parentIndex = parent.index
            _storage[index].isOccupied = true
            _storage[parent.index].rightIndex = index
            _count += 1
            return Tree.Binary<Element>.Position(index: index, token: token)
        }
    }

    /// Removes the leaf node at the specified position.
    @inlinable
    @discardableResult
    public mutating func remove(
        at position: Tree.Binary<Element>.Position
    ) throws(__TreeBinaryInlineError) -> Element {
        // Validate position (token check)
        try _validate(position)

        let node = _storage[position.index]
        guard node.leftIndex < 0 && node.rightIndex < 0 else {
            throw .cannotRemoveNonLeaf
        }

        // Update parent's child pointer
        let parentIndex = node.parentIndex
        if parentIndex >= 0 {
            if _storage[parentIndex].leftIndex == position.index {
                _storage[parentIndex].leftIndex = -1
            } else {
                _storage[parentIndex].rightIndex = -1
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
    public mutating func removeSubtree(
        at position: Tree.Binary<Element>.Position
    ) throws(__TreeBinaryInlineError) {
        // Validate position (token check)
        try _validate(position)

        // Update parent's child pointer
        let parentIndex = _storage[position.index].parentIndex
        if parentIndex >= 0 {
            if _storage[parentIndex].leftIndex == position.index {
                _storage[parentIndex].leftIndex = -1
            } else {
                _storage[parentIndex].rightIndex = -1
            }
        } else {
            _rootIndex = -1
        }

        // Iterative post-order removal using explicit stack
        var stack = Stack<Int>()
        var lastVisited: Int = -1

        stack.push(position.index)

        while !stack.isEmpty {
            let current = stack.peek()!
            guard _storage[current].isOccupied else {
                _ = stack.pop()
                continue
            }

            let leftIndex = _storage[current].leftIndex
            let rightIndex = _storage[current].rightIndex

            let leftDone = leftIndex < 0 || leftIndex == lastVisited || !_storage[leftIndex].isOccupied
            let rightDone = rightIndex < 0 || rightIndex == lastVisited || !_storage[rightIndex].isOccupied

            if leftDone && rightDone {
                _ = stack.pop()
                unsafe _elementPointer(at: current).deinitialize(count: 1)
                _freeSlot(current)
                _count -= 1
                lastVisited = current
            } else {
                if rightIndex >= 0 && rightIndex != lastVisited && _storage[rightIndex].isOccupied {
                    stack.push(rightIndex)
                }
                if leftIndex >= 0 && leftIndex != lastVisited && _storage[leftIndex].isOccupied {
                    stack.push(leftIndex)
                }
            }
        }
    }

    /// Accesses the element at the specified position via a borrowing closure.
    @inlinable
    public func peek<R>(
        at position: Tree.Binary<Element>.Position,
        _ body: (borrowing Element) -> R
    ) -> R? {
        do {
            try _validate(position)
        } catch {
            return nil
        }
        return unsafe body(_readElementPointer(at: position.index).pointee)
    }

    /// Clears all nodes from the tree.
    @inlinable
    public mutating func clear() {
        guard _count > 0 else { return }

        // Iterative post-order traversal using explicit stack
        var stack = Stack<Int>()
        var lastVisited: Int = -1

        if _rootIndex >= 0 {
            stack.push(_rootIndex)
        }

        while !stack.isEmpty {
            let current = stack.peek()!
            guard _storage[current].isOccupied else {
                _ = stack.pop()
                continue
            }

            let leftIndex = _storage[current].leftIndex
            let rightIndex = _storage[current].rightIndex

            let leftDone = leftIndex < 0 || leftIndex == lastVisited || !_storage[leftIndex].isOccupied
            let rightDone = rightIndex < 0 || rightIndex == lastVisited || !_storage[rightIndex].isOccupied

            if leftDone && rightDone {
                _ = stack.pop()
                unsafe _elementPointer(at: current).deinitialize(count: 1)
                _freeSlot(current)
                lastVisited = current
            } else {
                if rightIndex >= 0 && rightIndex != lastVisited && _storage[rightIndex].isOccupied {
                    stack.push(rightIndex)
                }
                if leftIndex >= 0 && leftIndex != lastVisited && _storage[leftIndex].isOccupied {
                    stack.push(leftIndex)
                }
            }
        }

        _rootIndex = -1
        _count = 0
        _freeHead = -1
    }

    /// Iterates over all elements in pre-order.
    @inlinable
    public func forEachPreOrder(_ body: (borrowing Element) -> Void) {
        func traverse(at index: Int) {
            guard index >= 0 && _storage[index].isOccupied else { return }
            unsafe body(_readElementPointer(at: index).pointee)
            traverse(at: _storage[index].leftIndex)
            traverse(at: _storage[index].rightIndex)
        }
        traverse(at: _rootIndex)
    }

    /// Iterates over all elements in in-order.
    @inlinable
    public func forEachInOrder(_ body: (borrowing Element) -> Void) {
        func traverse(at index: Int) {
            guard index >= 0 && _storage[index].isOccupied else { return }
            traverse(at: _storage[index].leftIndex)
            unsafe body(_readElementPointer(at: index).pointee)
            traverse(at: _storage[index].rightIndex)
        }
        traverse(at: _rootIndex)
    }

    /// Iterates over all elements in post-order.
    @inlinable
    public func forEachPostOrder(_ body: (borrowing Element) -> Void) {
        func traverse(at index: Int) {
            guard index >= 0 && _storage[index].isOccupied else { return }
            traverse(at: _storage[index].leftIndex)
            traverse(at: _storage[index].rightIndex)
            unsafe body(_readElementPointer(at: index).pointee)
        }
        traverse(at: _rootIndex)
    }

    /// Iterates over all elements in level-order.
    @inlinable
    public func forEachLevelOrder(_ body: (borrowing Element) -> Void) {
        guard _rootIndex >= 0 else { return }

        var queue = Queue<Int>()
        queue.enqueue(_rootIndex)

        while !queue.isEmpty {
            let index = queue.dequeue()!

            guard _storage[index].isOccupied else { continue }

            unsafe body(_readElementPointer(at: index).pointee)

            let leftIndex = _storage[index].leftIndex
            let rightIndex = _storage[index].rightIndex

            if leftIndex >= 0 { queue.enqueue(leftIndex) }
            if rightIndex >= 0 { queue.enqueue(rightIndex) }
        }
    }

    /// Computes the height of the tree.
    @inlinable
    public var height: Int {
        func computeHeight(at index: Int) -> Int {
            guard index >= 0 && _storage[index].isOccupied else { return -1 }
            let leftHeight = computeHeight(at: _storage[index].leftIndex)
            let rightHeight = computeHeight(at: _storage[index].rightIndex)
            return 1 + Swift.max(leftHeight, rightHeight)
        }
        return computeHeight(at: _rootIndex)
    }
}

// MARK: - Inline Copyable Extensions

extension Tree.Binary.Inline where Element: Copyable {

    /// Returns the element at the specified position.
    @inlinable
    public func peek(at position: Tree.Binary<Element>.Position) -> Element? {
        do {
            try _validate(position)
        } catch {
            return nil
        }
        return unsafe _readElementPointer(at: position.index).pointee
    }
}
