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

// MARK: - Small Properties

extension Tree.Binary.Small where Element: ~Copyable {

    /// The number of nodes in the tree.
    @inlinable
    public var count: Int { _count }

    /// Whether the tree is empty.
    @inlinable
    public var isEmpty: Bool { _count == 0 }

    /// The position of the root node, or `nil` if the tree is empty.
    @inlinable
    public var root: Tree.Binary<Element>.Position? {
        guard _rootIndex >= 0 else { return nil }
        if let heapTokens = unsafe _heapTokens {
            return Tree.Binary<Element>.Position(index: _rootIndex, token: unsafe heapTokens[_rootIndex])
        } else {
            return Tree.Binary<Element>.Position(index: _rootIndex, token: _inlineTokens[_rootIndex])
        }
    }

    // MARK: - Position Validation

    /// Validates that a position refers to a currently-occupied slot.
    @usableFromInline
    func _validate(_ position: Tree.Binary<Element>.Position) throws(__TreeBinarySmallError) {
        if let heapTokens = unsafe _heapTokens, let heap = _heap {
            guard position.index >= 0,
                  position.index < heap.header.capacity,
                  unsafe heapTokens[position.index] == position.token,
                  position.token & 1 == 1 else {
                throw .invalidPosition
            }
        } else {
            guard position.index >= 0,
                  position.index < inlineCapacity,
                  _inlineTokens[position.index] == position.token,
                  position.token & 1 == 1 else {
                throw .invalidPosition
            }
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

        if let heapPtr = unsafe _heapPtr, let heapTokens = unsafe _heapTokens {
            let leftIndex = unsafe heapPtr[position.index].leftIndex
            guard leftIndex >= 0 else { return nil }
            return Tree.Binary<Element>.Position(index: leftIndex, token: unsafe heapTokens[leftIndex])
        } else {
            let leftIndex = _inline[position.index].leftIndex
            guard leftIndex >= 0 else { return nil }
            return Tree.Binary<Element>.Position(index: leftIndex, token: _inlineTokens[leftIndex])
        }
    }

    /// Returns the position of the right child of the node at the given position.
    @inlinable
    public func right(of position: Tree.Binary<Element>.Position) -> Tree.Binary<Element>.Position? {
        do {
            try _validate(position)
        } catch {
            return nil
        }

        if let heapPtr = unsafe _heapPtr, let heapTokens = unsafe _heapTokens {
            let rightIndex = unsafe heapPtr[position.index].rightIndex
            guard rightIndex >= 0 else { return nil }
            return Tree.Binary<Element>.Position(index: rightIndex, token: unsafe heapTokens[rightIndex])
        } else {
            let rightIndex = _inline[position.index].rightIndex
            guard rightIndex >= 0 else { return nil }
            return Tree.Binary<Element>.Position(index: rightIndex, token: _inlineTokens[rightIndex])
        }
    }

    /// Returns the position of the parent of the node at the given position.
    @inlinable
    public func parent(of position: Tree.Binary<Element>.Position) -> Tree.Binary<Element>.Position? {
        do {
            try _validate(position)
        } catch {
            return nil
        }

        if let heapPtr = unsafe _heapPtr, let heapTokens = unsafe _heapTokens {
            let parentIndex = unsafe heapPtr[position.index].parentIndex
            guard parentIndex >= 0 else { return nil }
            return Tree.Binary<Element>.Position(index: parentIndex, token: unsafe heapTokens[parentIndex])
        } else {
            let parentIndex = _inline[position.index].parentIndex
            guard parentIndex >= 0 else { return nil }
            return Tree.Binary<Element>.Position(index: parentIndex, token: _inlineTokens[parentIndex])
        }
    }

    /// Returns whether the node at the given position is a leaf.
    @inlinable
    public func isLeaf(_ position: Tree.Binary<Element>.Position) -> Bool {
        do {
            try _validate(position)
        } catch {
            return false
        }

        if let heapPtr = unsafe _heapPtr {
            let leftIndex = unsafe heapPtr[position.index].leftIndex
            let rightIndex = unsafe heapPtr[position.index].rightIndex
            return leftIndex < 0 && rightIndex < 0
        } else {
            let leftIndex = _inline[position.index].leftIndex
            let rightIndex = _inline[position.index].rightIndex
            return leftIndex < 0 && rightIndex < 0
        }
    }

    // MARK: - Inline Helpers

    /// Returns a pointer to the element in an inline slot.
    @usableFromInline
    @unsafe
    mutating func _inlineElementPointer(at index: Int) -> UnsafeMutablePointer<Element> {
        unsafe Swift.withUnsafeMutablePointer(to: &_inline[index].slot) { slotPtr in
            unsafe UnsafeMutableRawPointer(slotPtr).assumingMemoryBound(to: Element.self)
        }
    }

    /// Returns a read pointer to the element in an inline slot.
    @usableFromInline
    @unsafe
    func _inlineReadElementPointer(at index: Int) -> UnsafePointer<Element> {
        unsafe Swift.withUnsafePointer(to: _inline[index].slot) { slotPtr in
            unsafe UnsafeRawPointer(slotPtr).assumingMemoryBound(to: Element.self)
        }
    }

    // MARK: - Spill to Heap

    /// Spills inline storage to heap.
    @usableFromInline
    mutating func _spillToHeap(minimumCapacity: Int) {
        let newCapacity = Swift.max(minimumCapacity, Swift.max(inlineCapacity * 2, 8))
        let newStorage = Tree.Binary<Element>.Storage.create(minimumCapacity: newCapacity)

        // Copy tokens from inline to heap (1:1 for inline capacity range)
        if let heapTokens = newStorage._tokens {
            for i in 0..<inlineCapacity {
                unsafe (heapTokens[i] = _inlineTokens[i])
            }
        }

        // Copy nextFree from inline to heap
        if let heapNextFree = newStorage._nextFree {
            for i in 0..<inlineCapacity {
                unsafe (heapNextFree[i] = _inlineNextFree[i])
            }
        }

        // Move elements from inline to heap via post-order traversal (maintaining indices)
        func moveSubtree(at index: Int) {
            guard index >= 0 && _inline[index].isOccupied else { return }
            let leftIndex = _inline[index].leftIndex
            let rightIndex = _inline[index].rightIndex
            let parentIndex = _inline[index].parentIndex

            moveSubtree(at: leftIndex)
            moveSubtree(at: rightIndex)

            // Move element
            let element = unsafe _inlineElementPointer(at: index).move()
            newStorage._initializeNode(
                at: index,
                element: element,
                leftIndex: leftIndex,
                rightIndex: rightIndex,
                parentIndex: parentIndex
            )
            _inline[index].isOccupied = false
        }

        moveSubtree(at: _rootIndex)

        newStorage.header.rootIndex = _rootIndex
        newStorage.header.count = _count
        newStorage.header.freeHead = _freeHead

        _heap = newStorage
        unsafe (_heapPtr = newStorage._nodesPointer)
        unsafe (_heapTokens = newStorage._tokens)
        unsafe (_heapNextFree = newStorage._nextFree)
    }

    // MARK: - Heap Storage Transition Helper

    /// Updates cached pointers after heap storage change.
    @usableFromInline
    mutating func _updateHeapPointers(_ newStorage: Tree.Binary<Element>.Storage) {
        _heap = newStorage
        unsafe (_heapPtr = newStorage._nodesPointer)
        unsafe (_heapTokens = newStorage._tokens)
        unsafe (_heapNextFree = newStorage._nextFree)
    }
}

// MARK: - Small Insert Operations (~Copyable)

extension Tree.Binary.Small where Element: ~Copyable {

    /// Inserts an element at the specified position.
    @inlinable
    @discardableResult
    public mutating func insert(
        _ element: consuming Element,
        at position: Tree.Binary<Element>.InsertPosition
    ) throws(__TreeBinarySmallError) -> Tree.Binary<Element>.Position {
        // If spilled to heap, use heap storage
        if _heap != nil {
            switch position {
            case .root:
                guard _rootIndex < 0 else {
                    throw .positionOccupied
                }

                // Allocate slot from heap
                var index: Int
                if _heap!.header.freeHead >= 0 {
                    index = _heap!.header.freeHead
                    _heap!.header.freeHead = unsafe _heapNextFree![index]
                } else {
                    // Grow if needed
                    if _heap!.header.count >= _heap!.header.capacity {
                        let newCapacity = Swift.max(_heap!.header.capacity * 2, 8)
                        let newStorage = Tree.Binary<Element>.Storage.create(minimumCapacity: newCapacity)
                        _heap!._moveAllElements(to: newStorage)
                        _updateHeapPointers(newStorage)
                    }
                    index = _heap!.header.count
                }

                // Increment token (use fresh pointers after potential growth)
                unsafe (_heapTokens![index] &+= 1)
                let token = unsafe _heapTokens![index]

                _heap!._initializeNode(at: index, element: element)
                _heap!.header.rootIndex = index
                _heap!.header.count += 1
                _rootIndex = index
                _count += 1
                return Tree.Binary<Element>.Position(index: index, token: token)

            case .left(of: let parent):
                // Validate parent position
                try _validate(parent)
                guard unsafe _heapPtr![parent.index].leftIndex < 0 else {
                    throw .positionOccupied
                }

                var index: Int
                if _heap!.header.freeHead >= 0 {
                    index = _heap!.header.freeHead
                    _heap!.header.freeHead = unsafe _heapNextFree![index]
                } else {
                    if _heap!.header.count >= _heap!.header.capacity {
                        let newCapacity = Swift.max(_heap!.header.capacity * 2, 8)
                        let newStorage = Tree.Binary<Element>.Storage.create(minimumCapacity: newCapacity)
                        _heap!._moveAllElements(to: newStorage)
                        _updateHeapPointers(newStorage)
                    }
                    index = _heap!.header.count
                }

                // Increment token (use fresh pointers after potential growth)
                unsafe (_heapTokens![index] &+= 1)
                let token = unsafe _heapTokens![index]

                _heap!._initializeNode(at: index, element: element, parentIndex: parent.index)
                unsafe (_heapPtr![parent.index].leftIndex = index)
                _heap!.header.count += 1
                _count += 1
                return Tree.Binary<Element>.Position(index: index, token: token)

            case .right(of: let parent):
                // Validate parent position
                try _validate(parent)
                guard unsafe _heapPtr![parent.index].rightIndex < 0 else {
                    throw .positionOccupied
                }

                var index: Int
                if _heap!.header.freeHead >= 0 {
                    index = _heap!.header.freeHead
                    _heap!.header.freeHead = unsafe _heapNextFree![index]
                } else {
                    if _heap!.header.count >= _heap!.header.capacity {
                        let newCapacity = Swift.max(_heap!.header.capacity * 2, 8)
                        let newStorage = Tree.Binary<Element>.Storage.create(minimumCapacity: newCapacity)
                        _heap!._moveAllElements(to: newStorage)
                        _updateHeapPointers(newStorage)
                    }
                    index = _heap!.header.count
                }

                // Increment token (use fresh pointers after potential growth)
                unsafe (_heapTokens![index] &+= 1)
                let token = unsafe _heapTokens![index]

                _heap!._initializeNode(at: index, element: element, parentIndex: parent.index)
                unsafe (_heapPtr![parent.index].rightIndex = index)
                _heap!.header.count += 1
                _count += 1
                return Tree.Binary<Element>.Position(index: index, token: token)
            }
        }

        // Using inline storage
        switch position {
        case .root:
            guard _rootIndex < 0 else {
                throw .positionOccupied
            }

            // Check if need to spill
            if _count >= inlineCapacity {
                _spillToHeap(minimumCapacity: _count + 1)
                return try insert(element, at: position)
            }

            // Find free slot
            var index: Int
            if _freeHead >= 0 {
                index = _freeHead
                _freeHead = _inlineNextFree[index]
            } else {
                // Find first unoccupied slot
                index = -1
                for i in 0..<inlineCapacity {
                    if !_inline[i].isOccupied {
                        index = i
                        break
                    }
                }
                if index < 0 {
                    _spillToHeap(minimumCapacity: _count + 1)
                    return try insert(element, at: position)
                }
            }

            // Increment token
            _inlineTokens[index] &+= 1
            let token = _inlineTokens[index]

            unsafe _inlineElementPointer(at: index).initialize(to: element)
            _inline[index].leftIndex = -1
            _inline[index].rightIndex = -1
            _inline[index].parentIndex = -1
            _inline[index].isOccupied = true
            _rootIndex = index
            _count += 1
            return Tree.Binary<Element>.Position(index: index, token: token)

        case .left(of: let parent):
            // Validate parent position
            try _validate(parent)
            guard _inline[parent.index].leftIndex < 0 else {
                throw .positionOccupied
            }

            if _count >= inlineCapacity {
                _spillToHeap(minimumCapacity: _count + 1)
                return try insert(element, at: position)
            }

            var index: Int
            if _freeHead >= 0 {
                index = _freeHead
                _freeHead = _inlineNextFree[index]
            } else {
                index = -1
                for i in 0..<inlineCapacity {
                    if !_inline[i].isOccupied {
                        index = i
                        break
                    }
                }
                if index < 0 {
                    _spillToHeap(minimumCapacity: _count + 1)
                    return try insert(element, at: position)
                }
            }

            // Increment token
            _inlineTokens[index] &+= 1
            let token = _inlineTokens[index]

            unsafe _inlineElementPointer(at: index).initialize(to: element)
            _inline[index].leftIndex = -1
            _inline[index].rightIndex = -1
            _inline[index].parentIndex = parent.index
            _inline[index].isOccupied = true
            _inline[parent.index].leftIndex = index
            _count += 1
            return Tree.Binary<Element>.Position(index: index, token: token)

        case .right(of: let parent):
            // Validate parent position
            try _validate(parent)
            guard _inline[parent.index].rightIndex < 0 else {
                throw .positionOccupied
            }

            if _count >= inlineCapacity {
                _spillToHeap(minimumCapacity: _count + 1)
                return try insert(element, at: position)
            }

            var index: Int
            if _freeHead >= 0 {
                index = _freeHead
                _freeHead = _inlineNextFree[index]
            } else {
                index = -1
                for i in 0..<inlineCapacity {
                    if !_inline[i].isOccupied {
                        index = i
                        break
                    }
                }
                if index < 0 {
                    _spillToHeap(minimumCapacity: _count + 1)
                    return try insert(element, at: position)
                }
            }

            // Increment token
            _inlineTokens[index] &+= 1
            let token = _inlineTokens[index]

            unsafe _inlineElementPointer(at: index).initialize(to: element)
            _inline[index].leftIndex = -1
            _inline[index].rightIndex = -1
            _inline[index].parentIndex = parent.index
            _inline[index].isOccupied = true
            _inline[parent.index].rightIndex = index
            _count += 1
            return Tree.Binary<Element>.Position(index: index, token: token)
        }
    }

    /// Removes the leaf node at the specified position.
    @inlinable
    @discardableResult
    public mutating func remove(
        at position: Tree.Binary<Element>.Position
    ) throws(__TreeBinarySmallError) -> Element {
        // Validate position
        try _validate(position)

        if let heapPtr = unsafe _heapPtr, let heapTokens = unsafe _heapTokens,
           let heapNextFree = unsafe _heapNextFree {
            let leftIndex = unsafe heapPtr[position.index].leftIndex
            let rightIndex = unsafe heapPtr[position.index].rightIndex
            guard leftIndex < 0 && rightIndex < 0 else {
                throw .cannotRemoveNonLeaf
            }

            let parentIndex = unsafe heapPtr[position.index].parentIndex
            if parentIndex >= 0 {
                if unsafe heapPtr[parentIndex].leftIndex == position.index {
                    unsafe (_heapPtr![parentIndex].leftIndex = -1)
                } else {
                    unsafe (_heapPtr![parentIndex].rightIndex = -1)
                }
            } else {
                _rootIndex = -1
                _heap!.header.rootIndex = -1
            }

            let element = _heap!._moveElement(at: position.index)

            // Increment token (occupied → free)
            unsafe (heapTokens[position.index] &+= 1)
            // Add to free list
            unsafe (heapNextFree[position.index] = _heap!.header.freeHead)
            _heap!.header.freeHead = position.index
            _heap!.header.count -= 1
            _count -= 1

            return element
        } else {
            guard _inline[position.index].isOccupied else {
                throw .invalidPosition
            }

            let node = _inline[position.index]
            guard node.leftIndex < 0 && node.rightIndex < 0 else {
                throw .cannotRemoveNonLeaf
            }

            let parentIndex = node.parentIndex
            if parentIndex >= 0 {
                if _inline[parentIndex].leftIndex == position.index {
                    _inline[parentIndex].leftIndex = -1
                } else {
                    _inline[parentIndex].rightIndex = -1
                }
            } else {
                _rootIndex = -1
            }

            let element = unsafe _inlineElementPointer(at: position.index).move()
            _inline[position.index].isOccupied = false

            // Increment token (occupied → free)
            _inlineTokens[position.index] &+= 1
            // Add to free list
            _inlineNextFree[position.index] = _freeHead
            _freeHead = position.index
            _count -= 1

            return element
        }
    }

    /// Removes the subtree rooted at the specified position.
    @inlinable
    public mutating func removeSubtree(
        at position: Tree.Binary<Element>.Position
    ) throws(__TreeBinarySmallError) {
        // Validate position
        try _validate(position)

        if _heap != nil {
            let parentIndex = unsafe _heapPtr![position.index].parentIndex
            if parentIndex >= 0 {
                if unsafe _heapPtr![parentIndex].leftIndex == position.index {
                    unsafe (_heapPtr![parentIndex].leftIndex = -1)
                } else {
                    unsafe (_heapPtr![parentIndex].rightIndex = -1)
                }
            } else {
                _rootIndex = -1
                _heap!.header.rootIndex = -1
            }

            // Iterative post-order removal using explicit stack
            var stack = Stack<Int>()
            var lastVisited: Int = -1

            stack.push(position.index)

            while !stack.isEmpty {
                let current = stack.peek()!
                let leftIndex = unsafe _heapPtr![current].leftIndex
                let rightIndex = unsafe _heapPtr![current].rightIndex

                let leftDone = leftIndex < 0 || leftIndex == lastVisited
                let rightDone = rightIndex < 0 || rightIndex == lastVisited

                if leftDone && rightDone {
                    _ = stack.pop()
                    _heap!._deinitializeNode(at: current)
                    unsafe (_heapTokens![current] &+= 1)
                    unsafe (_heapNextFree![current] = _heap!.header.freeHead)
                    _heap!.header.freeHead = current
                    _heap!.header.count -= 1
                    _count -= 1
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
        } else {
            guard _inline[position.index].isOccupied else {
                throw .invalidPosition
            }

            let parentIndex = _inline[position.index].parentIndex
            if parentIndex >= 0 {
                if _inline[parentIndex].leftIndex == position.index {
                    _inline[parentIndex].leftIndex = -1
                } else {
                    _inline[parentIndex].rightIndex = -1
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
                guard _inline[current].isOccupied else {
                    _ = stack.pop()
                    continue
                }

                let leftIndex = _inline[current].leftIndex
                let rightIndex = _inline[current].rightIndex

                let leftDone = leftIndex < 0 || leftIndex == lastVisited || !_inline[leftIndex].isOccupied
                let rightDone = rightIndex < 0 || rightIndex == lastVisited || !_inline[rightIndex].isOccupied

                if leftDone && rightDone {
                    _ = stack.pop()
                    unsafe _inlineElementPointer(at: current).deinitialize(count: 1)
                    _inline[current].isOccupied = false
                    _inlineTokens[current] &+= 1
                    _inlineNextFree[current] = _freeHead
                    _freeHead = current
                    _count -= 1
                    lastVisited = current
                } else {
                    if rightIndex >= 0 && rightIndex != lastVisited && _inline[rightIndex].isOccupied {
                        stack.push(rightIndex)
                    }
                    if leftIndex >= 0 && leftIndex != lastVisited && _inline[leftIndex].isOccupied {
                        stack.push(leftIndex)
                    }
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

        if let heapPtr = unsafe _heapPtr {
            return unsafe body(heapPtr[position.index].element)
        } else {
            return unsafe body(_inlineReadElementPointer(at: position.index).pointee)
        }
    }

    /// Clears all nodes from the tree.
    @inlinable
    public mutating func clear() {
        guard _count > 0 else { return }

        if let heap = _heap {
            // Reset heap - deinit will handle cleanup
            heap.header.rootIndex = _rootIndex
            heap.header.count = _count
            _heap = nil
            unsafe (_heapPtr = nil)
            unsafe (_heapTokens = nil)
            unsafe (_heapNextFree = nil)
        } else {
            // Iterative post-order traversal using explicit stack
            var stack = Stack<Int>()
            var lastVisited: Int = -1

            if _rootIndex >= 0 {
                stack.push(_rootIndex)
            }

            while !stack.isEmpty {
                let current = stack.peek()!
                guard _inline[current].isOccupied else {
                    _ = stack.pop()
                    continue
                }

                let leftIndex = _inline[current].leftIndex
                let rightIndex = _inline[current].rightIndex

                let leftDone = leftIndex < 0 || leftIndex == lastVisited || !_inline[leftIndex].isOccupied
                let rightDone = rightIndex < 0 || rightIndex == lastVisited || !_inline[rightIndex].isOccupied

                if leftDone && rightDone {
                    _ = stack.pop()
                    unsafe _inlineElementPointer(at: current).deinitialize(count: 1)
                    _inline[current].isOccupied = false
                    _inlineTokens[current] &+= 1
                    lastVisited = current
                } else {
                    if rightIndex >= 0 && rightIndex != lastVisited && _inline[rightIndex].isOccupied {
                        stack.push(rightIndex)
                    }
                    if leftIndex >= 0 && leftIndex != lastVisited && _inline[leftIndex].isOccupied {
                        stack.push(leftIndex)
                    }
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
        if let heapPtr = unsafe _heapPtr {
            func traverse(at index: Int) {
                guard index >= 0 else { return }
                unsafe body(heapPtr[index].element)
                traverse(at: unsafe heapPtr[index].leftIndex)
                traverse(at: unsafe heapPtr[index].rightIndex)
            }
            traverse(at: _rootIndex)
        } else {
            func traverse(at index: Int) {
                guard index >= 0 && _inline[index].isOccupied else { return }
                unsafe body(_inlineReadElementPointer(at: index).pointee)
                traverse(at: _inline[index].leftIndex)
                traverse(at: _inline[index].rightIndex)
            }
            traverse(at: _rootIndex)
        }
    }

    /// Iterates over all elements in in-order.
    @inlinable
    public func forEachInOrder(_ body: (borrowing Element) -> Void) {
        if let heapPtr = unsafe _heapPtr {
            func traverse(at index: Int) {
                guard index >= 0 else { return }
                traverse(at: unsafe heapPtr[index].leftIndex)
                unsafe body(heapPtr[index].element)
                traverse(at: unsafe heapPtr[index].rightIndex)
            }
            traverse(at: _rootIndex)
        } else {
            func traverse(at index: Int) {
                guard index >= 0 && _inline[index].isOccupied else { return }
                traverse(at: _inline[index].leftIndex)
                unsafe body(_inlineReadElementPointer(at: index).pointee)
                traverse(at: _inline[index].rightIndex)
            }
            traverse(at: _rootIndex)
        }
    }

    /// Iterates over all elements in post-order.
    @inlinable
    public func forEachPostOrder(_ body: (borrowing Element) -> Void) {
        if let heapPtr = unsafe _heapPtr {
            func traverse(at index: Int) {
                guard index >= 0 else { return }
                traverse(at: unsafe heapPtr[index].leftIndex)
                traverse(at: unsafe heapPtr[index].rightIndex)
                unsafe body(heapPtr[index].element)
            }
            traverse(at: _rootIndex)
        } else {
            func traverse(at index: Int) {
                guard index >= 0 && _inline[index].isOccupied else { return }
                traverse(at: _inline[index].leftIndex)
                traverse(at: _inline[index].rightIndex)
                unsafe body(_inlineReadElementPointer(at: index).pointee)
            }
            traverse(at: _rootIndex)
        }
    }

    /// Iterates over all elements in level-order.
    @inlinable
    public func forEachLevelOrder(_ body: (borrowing Element) -> Void) {
        guard _rootIndex >= 0 else { return }

        if let heapPtr = unsafe _heapPtr {
            var queue: [Int] = [_rootIndex]
            var head = 0

            while head < queue.count {
                let index = queue[head]
                head += 1

                unsafe body(heapPtr[index].element)

                let leftIndex = unsafe heapPtr[index].leftIndex
                let rightIndex = unsafe heapPtr[index].rightIndex

                if leftIndex >= 0 { queue.append(leftIndex) }
                if rightIndex >= 0 { queue.append(rightIndex) }
            }
        } else {
            var queue: [Int] = [_rootIndex]
            var head = 0

            while head < queue.count {
                let index = queue[head]
                head += 1

                guard _inline[index].isOccupied else { continue }

                unsafe body(_inlineReadElementPointer(at: index).pointee)

                let leftIndex = _inline[index].leftIndex
                let rightIndex = _inline[index].rightIndex

                if leftIndex >= 0 { queue.append(leftIndex) }
                if rightIndex >= 0 { queue.append(rightIndex) }
            }
        }
    }

    /// Computes the height of the tree.
    @inlinable
    public var height: Int {
        if let heapPtr = unsafe _heapPtr {
            func computeHeight(at index: Int) -> Int {
                guard index >= 0 else { return -1 }
                let leftHeight = computeHeight(at: unsafe heapPtr[index].leftIndex)
                let rightHeight = computeHeight(at: unsafe heapPtr[index].rightIndex)
                return 1 + Swift.max(leftHeight, rightHeight)
            }
            return computeHeight(at: _rootIndex)
        } else {
            func computeHeight(at index: Int) -> Int {
                guard index >= 0 && _inline[index].isOccupied else { return -1 }
                let leftHeight = computeHeight(at: _inline[index].leftIndex)
                let rightHeight = computeHeight(at: _inline[index].rightIndex)
                return 1 + Swift.max(leftHeight, rightHeight)
            }
            return computeHeight(at: _rootIndex)
        }
    }
}

// MARK: - Small Copyable Extensions

extension Tree.Binary.Small where Element: Copyable {

    /// Returns the element at the specified position.
    @inlinable
    public func peek(at position: Tree.Binary<Element>.Position) -> Element? {
        do {
            try _validate(position)
        } catch {
            return nil
        }

        if let heapPtr = unsafe _heapPtr {
            return unsafe heapPtr[position.index].element
        } else {
            return unsafe _inlineReadElementPointer(at: position.index).pointee
        }
    }
}
