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
        _rootIndex >= 0 ? Tree.Binary<Element>.Position(index: _rootIndex) : nil
    }

    // MARK: - Navigation

    /// Returns the position of the left child of the node at the given position.
    @inlinable
    public func left(of position: Tree.Binary<Element>.Position) -> Tree.Binary<Element>.Position? {
        if let _ = _heap, let ptr = unsafe _heapPtr {
            let leftIndex = unsafe ptr[position.index].leftIndex
            return leftIndex >= 0 ? Tree.Binary<Element>.Position(index: leftIndex) : nil
        } else {
            let leftIndex = _inline[position.index].leftIndex
            return leftIndex >= 0 ? Tree.Binary<Element>.Position(index: leftIndex) : nil
        }
    }

    /// Returns the position of the right child of the node at the given position.
    @inlinable
    public func right(of position: Tree.Binary<Element>.Position) -> Tree.Binary<Element>.Position? {
        if let _ = _heap, let ptr = unsafe _heapPtr {
            let rightIndex = unsafe ptr[position.index].rightIndex
            return rightIndex >= 0 ? Tree.Binary<Element>.Position(index: rightIndex) : nil
        } else {
            let rightIndex = _inline[position.index].rightIndex
            return rightIndex >= 0 ? Tree.Binary<Element>.Position(index: rightIndex) : nil
        }
    }

    /// Returns the position of the parent of the node at the given position.
    @inlinable
    public func parent(of position: Tree.Binary<Element>.Position) -> Tree.Binary<Element>.Position? {
        if let _ = _heap, let ptr = unsafe _heapPtr {
            let parentIndex = unsafe ptr[position.index].parentIndex
            return parentIndex >= 0 ? Tree.Binary<Element>.Position(index: parentIndex) : nil
        } else {
            let parentIndex = _inline[position.index].parentIndex
            return parentIndex >= 0 ? Tree.Binary<Element>.Position(index: parentIndex) : nil
        }
    }

    /// Returns whether the node at the given position is a leaf.
    @inlinable
    public func isLeaf(_ position: Tree.Binary<Element>.Position) -> Bool {
        if let _ = _heap, let ptr = unsafe _heapPtr {
            let leftIndex = unsafe ptr[position.index].leftIndex
            let rightIndex = unsafe ptr[position.index].rightIndex
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

        // Copy free list pointers
        if _freeHead >= 0 {
            var freeIndex = _freeHead
            while freeIndex >= 0 && freeIndex < inlineCapacity {
                var nextFree = -1
                unsafe Swift.withUnsafePointer(to: _inline[freeIndex].slot) { slotPtr in
                    let ptr = unsafe UnsafeRawPointer(slotPtr)
                    nextFree = unsafe ptr.load(as: Int.self)
                }
                newStorage._storeFreeNext(at: freeIndex, next: nextFree)
                freeIndex = nextFree
            }
        }

        _heap = newStorage
        unsafe (_heapPtr = newStorage._nodesPointer)
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
        if let heap = _heap, let heapPtr = unsafe _heapPtr {
            switch position {
            case .root:
                guard _rootIndex < 0 else {
                    throw .positionOccupied
                }

                // Allocate slot from heap
                var index: Int
                if heap.header.freeHead >= 0 {
                    index = heap.header.freeHead
                    heap.header.freeHead = heap._loadFreeNext(at: index)
                } else {
                    // Grow if needed
                    if heap.header.count >= heap.capacity {
                        let newCapacity = Swift.max(heap.capacity * 2, 8)
                        let newStorage = Tree.Binary<Element>.Storage.create(minimumCapacity: newCapacity)
                        heap._moveAllElements(to: newStorage)
                        _heap = newStorage
                        unsafe (_heapPtr = newStorage._nodesPointer)
                    }
                    index = heap.header.count
                }

                _heap!._initializeNode(at: index, element: element)
                _heap!.header.rootIndex = index
                _heap!.header.count += 1
                _rootIndex = index
                _count += 1
                return Tree.Binary<Element>.Position(index: index)

            case .left(of: let parent):
                guard unsafe heapPtr[parent.index].leftIndex < 0 else {
                    throw .positionOccupied
                }

                var index: Int
                if heap.header.freeHead >= 0 {
                    index = heap.header.freeHead
                    heap.header.freeHead = heap._loadFreeNext(at: index)
                } else {
                    if heap.header.count >= heap.capacity {
                        let newCapacity = Swift.max(heap.capacity * 2, 8)
                        let newStorage = Tree.Binary<Element>.Storage.create(minimumCapacity: newCapacity)
                        heap._moveAllElements(to: newStorage)
                        _heap = newStorage
                        unsafe (_heapPtr = newStorage._nodesPointer)
                    }
                    index = heap.header.count
                }

                _heap!._initializeNode(at: index, element: element, parentIndex: parent.index)
                unsafe (_heapPtr![parent.index].leftIndex = index)
                _heap!.header.count += 1
                _count += 1
                return Tree.Binary<Element>.Position(index: index)

            case .right(of: let parent):
                guard unsafe heapPtr[parent.index].rightIndex < 0 else {
                    throw .positionOccupied
                }

                var index: Int
                if heap.header.freeHead >= 0 {
                    index = heap.header.freeHead
                    heap.header.freeHead = heap._loadFreeNext(at: index)
                } else {
                    if heap.header.count >= heap.capacity {
                        let newCapacity = Swift.max(heap.capacity * 2, 8)
                        let newStorage = Tree.Binary<Element>.Storage.create(minimumCapacity: newCapacity)
                        heap._moveAllElements(to: newStorage)
                        _heap = newStorage
                        unsafe (_heapPtr = newStorage._nodesPointer)
                    }
                    index = heap.header.count
                }

                _heap!._initializeNode(at: index, element: element, parentIndex: parent.index)
                unsafe (_heapPtr![parent.index].rightIndex = index)
                _heap!.header.count += 1
                _count += 1
                return Tree.Binary<Element>.Position(index: index)
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
                var nextFree: Int = -1
                unsafe Swift.withUnsafePointer(to: _inline[index].slot) { slotPtr in
                    let ptr = unsafe UnsafeRawPointer(slotPtr)
                    nextFree = unsafe ptr.load(as: Int.self)
                }
                _freeHead = nextFree
            } else {
                index = _count
            }

            unsafe _inlineElementPointer(at: index).initialize(to: element)
            _inline[index].leftIndex = -1
            _inline[index].rightIndex = -1
            _inline[index].parentIndex = -1
            _inline[index].isOccupied = true
            _rootIndex = index
            _count += 1
            return Tree.Binary<Element>.Position(index: index)

        case .left(of: let parent):
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
                var nextFree: Int = -1
                unsafe Swift.withUnsafePointer(to: _inline[index].slot) { slotPtr in
                    let ptr = unsafe UnsafeRawPointer(slotPtr)
                    nextFree = unsafe ptr.load(as: Int.self)
                }
                _freeHead = nextFree
            } else {
                index = _count
            }

            unsafe _inlineElementPointer(at: index).initialize(to: element)
            _inline[index].leftIndex = -1
            _inline[index].rightIndex = -1
            _inline[index].parentIndex = parent.index
            _inline[index].isOccupied = true
            _inline[parent.index].leftIndex = index
            _count += 1
            return Tree.Binary<Element>.Position(index: index)

        case .right(of: let parent):
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
                var nextFree: Int = -1
                unsafe Swift.withUnsafePointer(to: _inline[index].slot) { slotPtr in
                    let ptr = unsafe UnsafeRawPointer(slotPtr)
                    nextFree = unsafe ptr.load(as: Int.self)
                }
                _freeHead = nextFree
            } else {
                index = _count
            }

            unsafe _inlineElementPointer(at: index).initialize(to: element)
            _inline[index].leftIndex = -1
            _inline[index].rightIndex = -1
            _inline[index].parentIndex = parent.index
            _inline[index].isOccupied = true
            _inline[parent.index].rightIndex = index
            _count += 1
            return Tree.Binary<Element>.Position(index: index)
        }
    }

    /// Removes the leaf node at the specified position.
    @inlinable
    @discardableResult
    public mutating func remove(
        at position: Tree.Binary<Element>.Position
    ) throws(__TreeBinarySmallError) -> Element {
        if let _ = _heap, let heapPtr = unsafe _heapPtr {
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
            _heap!._storeFreeNext(at: position.index, next: _heap!.header.freeHead)
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
            let oldFreeHead = _freeHead
            unsafe Swift.withUnsafeMutablePointer(to: &_inline[position.index].slot) { slotPtr in
                let ptr = UnsafeMutableRawPointer(slotPtr)
                unsafe ptr.storeBytes(of: oldFreeHead, as: Int.self)
            }
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
        if let _ = _heap, let heapPtr = unsafe _heapPtr {
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

            func removeNode(at index: Int) {
                guard index >= 0 else { return }
                let leftIndex = unsafe heapPtr[index].leftIndex
                let rightIndex = unsafe heapPtr[index].rightIndex
                removeNode(at: leftIndex)
                removeNode(at: rightIndex)
                _heap!._deinitializeNode(at: index)
                _heap!._storeFreeNext(at: index, next: _heap!.header.freeHead)
                _heap!.header.freeHead = index
                _heap!.header.count -= 1
                _count -= 1
            }

            removeNode(at: position.index)
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

            func removeNode(at index: Int) {
                guard index >= 0 && _inline[index].isOccupied else { return }
                let leftIndex = _inline[index].leftIndex
                let rightIndex = _inline[index].rightIndex
                removeNode(at: leftIndex)
                removeNode(at: rightIndex)
                unsafe _inlineElementPointer(at: index).deinitialize(count: 1)
                _inline[index].isOccupied = false
                let oldFreeHead = _freeHead
                unsafe Swift.withUnsafeMutablePointer(to: &_inline[index].slot) { slotPtr in
                    let ptr = UnsafeMutableRawPointer(slotPtr)
                    unsafe ptr.storeBytes(of: oldFreeHead, as: Int.self)
                }
                _freeHead = index
                _count -= 1
            }

            removeNode(at: position.index)
        }
    }

    /// Accesses the element at the specified position via a borrowing closure.
    @inlinable
    public func peek<R>(
        at position: Tree.Binary<Element>.Position,
        _ body: (borrowing Element) -> R
    ) -> R? {
        if let _ = _heap, let heapPtr = unsafe _heapPtr {
            return unsafe body(heapPtr[position.index].element)
        } else {
            guard _inline[position.index].isOccupied else {
                return nil
            }
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
        } else {
            func clearSubtree(at index: Int) {
                guard index >= 0 && _inline[index].isOccupied else { return }
                let leftIndex = _inline[index].leftIndex
                let rightIndex = _inline[index].rightIndex
                clearSubtree(at: leftIndex)
                clearSubtree(at: rightIndex)
                unsafe _inlineElementPointer(at: index).deinitialize(count: 1)
                _inline[index].isOccupied = false
            }

            clearSubtree(at: _rootIndex)
        }

        _rootIndex = -1
        _count = 0
        _freeHead = -1
    }

    /// Iterates over all elements in pre-order.
    @inlinable
    public func forEachPreOrder(_ body: (borrowing Element) -> Void) {
        if let _ = _heap, let heapPtr = unsafe _heapPtr {
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
        if let _ = _heap, let heapPtr = unsafe _heapPtr {
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
        if let _ = _heap, let heapPtr = unsafe _heapPtr {
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

        if let _ = _heap, let heapPtr = unsafe _heapPtr {
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
        if let _ = _heap, let heapPtr = unsafe _heapPtr {
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
        if let _ = _heap, let heapPtr = unsafe _heapPtr {
            return unsafe heapPtr[position.index].element
        } else {
            guard _inline[position.index].isOccupied else {
                return nil
            }
            return unsafe _inlineReadElementPointer(at: position.index).pointee
        }
    }
}
