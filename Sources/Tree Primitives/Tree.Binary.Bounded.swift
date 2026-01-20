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

public import Stack_Primitives

// MARK: - Bounded Properties

extension Tree.Binary.Bounded where Element: ~Copyable {

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
    public var root: Tree.Binary<Element>.Position? {
        let rootIndex = _storage.header.rootIndex
        guard rootIndex >= 0, let tokens = unsafe _tokens else { return nil }
        return Tree.Binary<Element>.Position(index: rootIndex, token: unsafe tokens[rootIndex])
    }

    // MARK: - Position Validation

    /// Validates that a position refers to a currently-occupied slot.
    @usableFromInline
    func _validate(_ position: Tree.Binary<Element>.Position) throws(__TreeBinaryBoundedError) {
        guard position.index >= 0,
              position.index < capacity,
              let tokens = unsafe _tokens,
              unsafe tokens[position.index] == position.token,
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
        let leftIndex = unsafe _cachedPtr[position.index].leftIndex
        guard leftIndex >= 0, let tokens = unsafe _tokens else { return nil }
        return Tree.Binary<Element>.Position(index: leftIndex, token: unsafe tokens[leftIndex])
    }

    /// Returns the position of the right child of the node at the given position.
    @inlinable
    public func right(of position: Tree.Binary<Element>.Position) -> Tree.Binary<Element>.Position? {
        do {
            try _validate(position)
        } catch {
            return nil
        }
        let rightIndex = unsafe _cachedPtr[position.index].rightIndex
        guard rightIndex >= 0, let tokens = unsafe _tokens else { return nil }
        return Tree.Binary<Element>.Position(index: rightIndex, token: unsafe tokens[rightIndex])
    }

    /// Returns the position of the parent of the node at the given position.
    @inlinable
    public func parent(of position: Tree.Binary<Element>.Position) -> Tree.Binary<Element>.Position? {
        do {
            try _validate(position)
        } catch {
            return nil
        }
        let parentIndex = unsafe _cachedPtr[position.index].parentIndex
        guard parentIndex >= 0, let tokens = unsafe _tokens else { return nil }
        return Tree.Binary<Element>.Position(index: parentIndex, token: unsafe tokens[parentIndex])
    }

    /// Returns whether the node at the given position is a leaf.
    @inlinable
    public func isLeaf(_ position: Tree.Binary<Element>.Position) -> Bool {
        do {
            try _validate(position)
        } catch {
            return false
        }
        let leftIndex = unsafe _cachedPtr[position.index].leftIndex
        let rightIndex = unsafe _cachedPtr[position.index].rightIndex
        return leftIndex < 0 && rightIndex < 0
    }

    // MARK: - Slot Management

    /// Allocates a slot for a new node, returning a token-stamped position.
    @usableFromInline
    mutating func _allocateSlot() -> (index: Int, token: UInt32)? {
        let index: Int

        // Try to reuse from free list
        if _storage.header.freeHead >= 0 {
            index = _storage.header.freeHead
            if let nextFree = unsafe _nextFree {
                _storage.header.freeHead = unsafe nextFree[index]
            }
        } else if _storage.header.count < capacity {
            // Allocate at end if space available
            index = _storage.header.count
        } else {
            return nil
        }

        // Increment token: even (free) → odd (occupied)
        if let tokens = unsafe _tokens {
            unsafe (tokens[index] &+= 1)
            return (index, unsafe tokens[index])
        } else {
            return (index, 1)
        }
    }

    /// Returns a slot to the free list.
    @usableFromInline
    mutating func _freeSlot(_ index: Int) {
        // Increment token: odd (occupied) → even (free)
        if let tokens = unsafe _tokens {
            unsafe (tokens[index] &+= 1)
        }

        // Add to free list
        if let nextFree = unsafe _nextFree {
            unsafe (nextFree[index] = _storage.header.freeHead)
        }
        _storage.header.freeHead = index
    }
}

// MARK: - Bounded Insert Operations (~Copyable)

extension Tree.Binary.Bounded where Element: ~Copyable {

    /// Inserts an element at the specified position.
    ///
    /// - Parameters:
    ///   - element: The element to insert.
    ///   - position: Where to insert the element.
    /// - Returns: The position of the newly inserted node (with token for validation).
    /// - Throws: ``Error/overflow`` if the tree is full,
    ///           ``Error/positionOccupied`` if the position is already occupied,
    ///           ``Error/invalidPosition`` if the parent position is invalid or stale.
    @inlinable
    @discardableResult
    public mutating func insert(
        _ element: consuming Element,
        at position: Tree.Binary<Element>.InsertPosition
    ) throws(__TreeBinaryBoundedError) -> Tree.Binary<Element>.Position {
        switch position {
        case .root:
            guard _storage.header.rootIndex < 0 else {
                throw .positionOccupied
            }
            guard let (index, token) = _allocateSlot() else {
                throw .overflow
            }
            _storage._initializeNode(at: index, element: element)
            _storage.header.rootIndex = index
            _storage.header.count += 1
            return Tree.Binary<Element>.Position(index: index, token: token)

        case .left(of: let parent):
            // Validate parent position (token check)
            try _validate(parent)
            guard unsafe _cachedPtr[parent.index].leftIndex < 0 else {
                throw .positionOccupied
            }
            guard let (index, token) = _allocateSlot() else {
                throw .overflow
            }
            _storage._initializeNode(at: index, element: element, parentIndex: parent.index)
            unsafe (_cachedPtr[parent.index].leftIndex = index)
            _storage.header.count += 1
            return Tree.Binary<Element>.Position(index: index, token: token)

        case .right(of: let parent):
            // Validate parent position (token check)
            try _validate(parent)
            guard unsafe _cachedPtr[parent.index].rightIndex < 0 else {
                throw .positionOccupied
            }
            guard let (index, token) = _allocateSlot() else {
                throw .overflow
            }
            _storage._initializeNode(at: index, element: element, parentIndex: parent.index)
            unsafe (_cachedPtr[parent.index].rightIndex = index)
            _storage.header.count += 1
            return Tree.Binary<Element>.Position(index: index, token: token)
        }
    }

    /// Removes the leaf node at the specified position.
    @inlinable
    @discardableResult
    public mutating func remove(
        at position: Tree.Binary<Element>.Position
    ) throws(__TreeBinaryBoundedError) -> Element {
        // Validate position (token check)
        try _validate(position)

        let leftIndex = unsafe _cachedPtr[position.index].leftIndex
        let rightIndex = unsafe _cachedPtr[position.index].rightIndex
        guard leftIndex < 0 && rightIndex < 0 else {
            throw .cannotRemoveNonLeaf
        }

        // Update parent's child pointer
        let parentIndex = unsafe _cachedPtr[position.index].parentIndex
        if parentIndex >= 0 {
            if unsafe _cachedPtr[parentIndex].leftIndex == position.index {
                unsafe (_cachedPtr[parentIndex].leftIndex = -1)
            } else {
                unsafe (_cachedPtr[parentIndex].rightIndex = -1)
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
    public mutating func removeSubtree(
        at position: Tree.Binary<Element>.Position
    ) throws(__TreeBinaryBoundedError) {
        // Validate position (token check)
        try _validate(position)

        // Update parent's child pointer
        let parentIndex = unsafe _cachedPtr[position.index].parentIndex
        if parentIndex >= 0 {
            if unsafe _cachedPtr[parentIndex].leftIndex == position.index {
                unsafe (_cachedPtr[parentIndex].leftIndex = -1)
            } else {
                unsafe (_cachedPtr[parentIndex].rightIndex = -1)
            }
        } else {
            _storage.header.rootIndex = -1
        }

        // Iterative post-order removal using explicit stack
        var stack = Stack<Int>()
        var lastVisited: Int = -1

        stack.push(position.index)

        while !stack.isEmpty {
            let current = stack.peek()!
            let leftIndex = unsafe _cachedPtr[current].leftIndex
            let rightIndex = unsafe _cachedPtr[current].rightIndex

            let leftDone = leftIndex < 0 || leftIndex == lastVisited
            let rightDone = rightIndex < 0 || rightIndex == lastVisited

            if leftDone && rightDone {
                _ = stack.pop()
                _storage._deinitializeNode(at: current)
                _freeSlot(current)
                _storage.header.count -= 1
                lastVisited = current
            } else {
                if rightIndex >= 0 && rightIndex != lastVisited {
                    stack.push(rightIndex)
                }
                if leftIndex >= 0 && leftIndex != lastVisited {
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
        return unsafe body(_cachedPtr[position.index].element)
    }

    /// Clears all nodes from the tree.
    @inlinable
    public mutating func clear() {
        guard _storage.header.count > 0 else { return }

        // Iterative post-order traversal using explicit stack
        var stack = Stack<Int>()
        var lastVisited: Int = -1

        if _storage.header.rootIndex >= 0 {
            stack.push(_storage.header.rootIndex)
        }

        while !stack.isEmpty {
            let current = stack.peek()!
            let leftIndex = unsafe _cachedPtr[current].leftIndex
            let rightIndex = unsafe _cachedPtr[current].rightIndex

            let leftDone = leftIndex < 0 || leftIndex == lastVisited
            let rightDone = rightIndex < 0 || rightIndex == lastVisited

            if leftDone && rightDone {
                _ = stack.pop()
                _storage._deinitializeNode(at: current)
                _freeSlot(current)
                lastVisited = current
            } else {
                if rightIndex >= 0 && rightIndex != lastVisited {
                    stack.push(rightIndex)
                }
                if leftIndex >= 0 && leftIndex != lastVisited {
                    stack.push(leftIndex)
                }
            }
        }

        _storage.header.rootIndex = -1
        _storage.header.count = 0
        _storage.header.freeHead = -1
    }

    /// Iterates over all elements in pre-order.
    @inlinable
    public func forEachPreOrder(_ body: (borrowing Element) -> Void) {
        func traverse(at index: Int) {
            guard index >= 0 else { return }
            unsafe body(_cachedPtr[index].element)
            traverse(at: unsafe _cachedPtr[index].leftIndex)
            traverse(at: unsafe _cachedPtr[index].rightIndex)
        }
        traverse(at: _storage.header.rootIndex)
    }

    /// Iterates over all elements in in-order.
    @inlinable
    public func forEachInOrder(_ body: (borrowing Element) -> Void) {
        func traverse(at index: Int) {
            guard index >= 0 else { return }
            traverse(at: unsafe _cachedPtr[index].leftIndex)
            unsafe body(_cachedPtr[index].element)
            traverse(at: unsafe _cachedPtr[index].rightIndex)
        }
        traverse(at: _storage.header.rootIndex)
    }

    /// Iterates over all elements in post-order.
    @inlinable
    public func forEachPostOrder(_ body: (borrowing Element) -> Void) {
        func traverse(at index: Int) {
            guard index >= 0 else { return }
            traverse(at: unsafe _cachedPtr[index].leftIndex)
            traverse(at: unsafe _cachedPtr[index].rightIndex)
            unsafe body(_cachedPtr[index].element)
        }
        traverse(at: _storage.header.rootIndex)
    }

    /// Iterates over all elements in level-order.
    @inlinable
    public func forEachLevelOrder(_ body: (borrowing Element) -> Void) {
        guard _storage.header.rootIndex >= 0 else { return }

        var queue: [Int] = [_storage.header.rootIndex]
        var head = 0

        while head < queue.count {
            let index = queue[head]
            head += 1

            unsafe body(_cachedPtr[index].element)

            let leftIndex = unsafe _cachedPtr[index].leftIndex
            let rightIndex = unsafe _cachedPtr[index].rightIndex

            if leftIndex >= 0 { queue.append(leftIndex) }
            if rightIndex >= 0 { queue.append(rightIndex) }
        }
    }

    /// Computes the height of the tree.
    @inlinable
    public var height: Int {
        func computeHeight(at index: Int) -> Int {
            guard index >= 0 else { return -1 }
            let leftHeight = computeHeight(at: unsafe _cachedPtr[index].leftIndex)
            let rightHeight = computeHeight(at: unsafe _cachedPtr[index].rightIndex)
            return 1 + Swift.max(leftHeight, rightHeight)
        }
        return computeHeight(at: _storage.header.rootIndex)
    }
}

// MARK: - Bounded Copyable Extensions

extension Tree.Binary.Bounded where Element: Copyable {

    /// Single point of truth for storage transitions.
    @usableFromInline
    mutating func _replaceStorage(_ newStorage: Tree.Binary<Element>.Storage) {
        _storage = newStorage
        unsafe (_cachedPtr = newStorage._nodesPointer)
        unsafe (_tokens = newStorage._tokens)
        unsafe (_nextFree = newStorage._nextFree)
    }

    /// Makes the storage unique for copy-on-write.
    @usableFromInline
    mutating func makeUnique() {
        if !isKnownUniquelyReferenced(&_storage) {
            let newStorage = Tree.Binary<Element>.Storage.create(minimumCapacity: capacity)
            _storage._copyAllElements(to: newStorage)
            _replaceStorage(newStorage)
        }
    }

    /// Inserts an element at the specified position (CoW-aware).
    @inlinable
    @discardableResult
    public mutating func insert(
        _ element: Element,
        at position: Tree.Binary<Element>.InsertPosition
    ) throws(__TreeBinaryBoundedError) -> Tree.Binary<Element>.Position {
        makeUnique()

        switch position {
        case .root:
            guard _storage.header.rootIndex < 0 else {
                throw .positionOccupied
            }
            guard let (index, token) = _allocateSlot() else {
                throw .overflow
            }
            _storage._initializeNode(at: index, element: element)
            _storage.header.rootIndex = index
            _storage.header.count += 1
            return Tree.Binary<Element>.Position(index: index, token: token)

        case .left(of: let parent):
            // Validate parent position (token check)
            try _validate(parent)
            guard unsafe _cachedPtr[parent.index].leftIndex < 0 else {
                throw .positionOccupied
            }
            guard let (index, token) = _allocateSlot() else {
                throw .overflow
            }
            _storage._initializeNode(at: index, element: element, parentIndex: parent.index)
            unsafe (_cachedPtr[parent.index].leftIndex = index)
            _storage.header.count += 1
            return Tree.Binary<Element>.Position(index: index, token: token)

        case .right(of: let parent):
            // Validate parent position (token check)
            try _validate(parent)
            guard unsafe _cachedPtr[parent.index].rightIndex < 0 else {
                throw .positionOccupied
            }
            guard let (index, token) = _allocateSlot() else {
                throw .overflow
            }
            _storage._initializeNode(at: index, element: element, parentIndex: parent.index)
            unsafe (_cachedPtr[parent.index].rightIndex = index)
            _storage.header.count += 1
            return Tree.Binary<Element>.Position(index: index, token: token)
        }
    }

    /// Returns the element at the specified position.
    @inlinable
    public func peek(at position: Tree.Binary<Element>.Position) -> Element? {
        do {
            try _validate(position)
        } catch {
            return nil
        }
        return unsafe _cachedPtr[position.index].element
    }
}
