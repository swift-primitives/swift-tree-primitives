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
        _rootIndex >= 0 ? Tree.Binary<Element>.Position(index: _rootIndex) : nil
    }

    // MARK: - Navigation

    /// Returns the position of the left child of the node at the given position.
    @inlinable
    public func left(of position: Tree.Binary<Element>.Position) -> Tree.Binary<Element>.Position? {
        let leftIndex = _storage[position.index].leftIndex
        return leftIndex >= 0 ? Tree.Binary<Element>.Position(index: leftIndex) : nil
    }

    /// Returns the position of the right child of the node at the given position.
    @inlinable
    public func right(of position: Tree.Binary<Element>.Position) -> Tree.Binary<Element>.Position? {
        let rightIndex = _storage[position.index].rightIndex
        return rightIndex >= 0 ? Tree.Binary<Element>.Position(index: rightIndex) : nil
    }

    /// Returns the position of the parent of the node at the given position.
    @inlinable
    public func parent(of position: Tree.Binary<Element>.Position) -> Tree.Binary<Element>.Position? {
        let parentIndex = _storage[position.index].parentIndex
        return parentIndex >= 0 ? Tree.Binary<Element>.Position(index: parentIndex) : nil
    }

    /// Returns whether the node at the given position is a leaf.
    @inlinable
    public func isLeaf(_ position: Tree.Binary<Element>.Position) -> Bool {
        let node = _storage[position.index]
        return node.leftIndex < 0 && node.rightIndex < 0
    }

    // MARK: - Slot Management

    /// Allocates a slot for a new node.
    @usableFromInline
    mutating func _allocateSlot() -> Int? {
        // Try to reuse from free list
        if _freeHead >= 0 {
            let index = _freeHead
            // Load next free from the slot - capture into local to avoid overlap
            var nextFree: Int = -1
            unsafe Swift.withUnsafePointer(to: _storage[index].slot) { slotPtr in
                let ptr = unsafe UnsafeRawPointer(slotPtr)
                nextFree = unsafe ptr.load(as: Int.self)
            }
            _freeHead = nextFree
            return index
        }

        // Allocate at end if space available
        if _count < capacity {
            // Find first unoccupied slot
            for i in 0..<capacity {
                if !_storage[i].isOccupied {
                    return i
                }
            }
        }

        return nil
    }

    /// Returns a slot to the free list.
    @usableFromInline
    mutating func _freeSlot(_ index: Int) {
        _storage[index].isOccupied = false
        // Store current free head in the slot - capture to avoid overlap
        let oldFreeHead = _freeHead
        unsafe Swift.withUnsafeMutablePointer(to: &_storage[index].slot) { slotPtr in
            let ptr = unsafe UnsafeMutableRawPointer(slotPtr)
            unsafe ptr.storeBytes(of: oldFreeHead, as: Int.self)
        }
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
            guard let index = _allocateSlot() else {
                throw .overflow
            }
            unsafe _elementPointer(at: index).initialize(to: element)
            _storage[index].leftIndex = -1
            _storage[index].rightIndex = -1
            _storage[index].parentIndex = -1
            _storage[index].isOccupied = true
            _rootIndex = index
            _count += 1
            return Tree.Binary<Element>.Position(index: index)

        case .left(of: let parent):
            guard parent.index >= 0 && parent.index < capacity else {
                throw .invalidPosition
            }
            guard _storage[parent.index].leftIndex < 0 else {
                throw .positionOccupied
            }
            guard let index = _allocateSlot() else {
                throw .overflow
            }
            unsafe _elementPointer(at: index).initialize(to: element)
            _storage[index].leftIndex = -1
            _storage[index].rightIndex = -1
            _storage[index].parentIndex = parent.index
            _storage[index].isOccupied = true
            _storage[parent.index].leftIndex = index
            _count += 1
            return Tree.Binary<Element>.Position(index: index)

        case .right(of: let parent):
            guard parent.index >= 0 && parent.index < capacity else {
                throw .invalidPosition
            }
            guard _storage[parent.index].rightIndex < 0 else {
                throw .positionOccupied
            }
            guard let index = _allocateSlot() else {
                throw .overflow
            }
            unsafe _elementPointer(at: index).initialize(to: element)
            _storage[index].leftIndex = -1
            _storage[index].rightIndex = -1
            _storage[index].parentIndex = parent.index
            _storage[index].isOccupied = true
            _storage[parent.index].rightIndex = index
            _count += 1
            return Tree.Binary<Element>.Position(index: index)
        }
    }

    /// Removes the leaf node at the specified position.
    @inlinable
    @discardableResult
    public mutating func remove(
        at position: Tree.Binary<Element>.Position
    ) throws(__TreeBinaryInlineError) -> Element {
        guard position.index >= 0 && position.index < capacity else {
            throw .invalidPosition
        }
        guard _storage[position.index].isOccupied else {
            throw .invalidPosition
        }

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
        guard position.index >= 0 && position.index < capacity else {
            throw .invalidPosition
        }
        guard _storage[position.index].isOccupied else {
            throw .invalidPosition
        }

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

        // Post-order removal
        func removeNode(at index: Int) {
            guard index >= 0 && _storage[index].isOccupied else { return }
            let leftIndex = _storage[index].leftIndex
            let rightIndex = _storage[index].rightIndex
            removeNode(at: leftIndex)
            removeNode(at: rightIndex)
            unsafe _elementPointer(at: index).deinitialize(count: 1)
            _freeSlot(index)
            _count -= 1
        }

        removeNode(at: position.index)
    }

    /// Accesses the element at the specified position via a borrowing closure.
    @inlinable
    public func peek<R>(
        at position: Tree.Binary<Element>.Position,
        _ body: (borrowing Element) -> R
    ) -> R? {
        guard position.index >= 0 && position.index < capacity else {
            return nil
        }
        guard _storage[position.index].isOccupied else {
            return nil
        }
        return unsafe body(_readElementPointer(at: position.index).pointee)
    }

    /// Clears all nodes from the tree.
    @inlinable
    public mutating func clear() {
        guard _count > 0 else { return }

        func clearSubtree(at index: Int) {
            guard index >= 0 && _storage[index].isOccupied else { return }
            let leftIndex = _storage[index].leftIndex
            let rightIndex = _storage[index].rightIndex
            clearSubtree(at: leftIndex)
            clearSubtree(at: rightIndex)
            unsafe _elementPointer(at: index).deinitialize(count: 1)
            _storage[index].isOccupied = false
        }

        clearSubtree(at: _rootIndex)
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

        var queue: [Int] = [_rootIndex]
        var head = 0

        while head < queue.count {
            let index = queue[head]
            head += 1

            guard _storage[index].isOccupied else { continue }

            unsafe body(_readElementPointer(at: index).pointee)

            let leftIndex = _storage[index].leftIndex
            let rightIndex = _storage[index].rightIndex

            if leftIndex >= 0 { queue.append(leftIndex) }
            if rightIndex >= 0 { queue.append(rightIndex) }
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
        guard position.index >= 0 && position.index < capacity else {
            return nil
        }
        guard _storage[position.index].isOccupied else {
            return nil
        }
        return unsafe _readElementPointer(at: position.index).pointee
    }
}
