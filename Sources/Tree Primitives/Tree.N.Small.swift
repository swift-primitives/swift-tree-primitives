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

/// A small-buffer optimized n-ary tree with inline storage and spill to heap.
///
/// `Tree.N.Small<inlineCapacity>` uses inline storage for up to `inlineCapacity` nodes,
/// automatically spilling to heap storage when the inline capacity is exceeded.
/// This provides the best of both worlds: zero allocation for small trees and
/// automatic growth for larger ones.
///
/// ## Example
///
/// ```swift
/// // Binary tree with inline capacity of 7 nodes (e.g., a complete tree of depth 2)
/// var tree = Tree<Int>.N<2>.Small<7>()
/// let root = try tree.insert(1, at: .root)
/// let left = try tree.insert(2, at: .left(of: root))
/// let right = try tree.insert(3, at: .right(of: root))
/// print(tree.isSpilled)  // false - still using inline storage
/// ```
///
/// ## Spill Behavior
///
/// When the tree exceeds `inlineCapacity` nodes, all nodes are moved to heap-based
/// storage (`Tree.N<Element, n>.Storage`). The `isSpilled` property indicates whether
/// the tree has transitioned to heap storage. Once spilled, the tree never returns
/// to inline storage.
///
/// ## Move-Only
///
/// `Tree.N.Small` is unconditionally `~Copyable` (move-only) because it requires
/// a deinitializer to clean up inline storage.
extension Tree.N where Element: ~Copyable {

    @safe
    public struct Small<let inlineCapacity: Int>: ~Copyable {
        /// Maximum node stride supported by inline storage (128 bytes per slot).
        @usableFromInline
        static var _maxStride: Int { 128 }

        /// Inline node with n-ary child indices.
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

        /// Raw storage for inline nodes.
        @usableFromInline
        var _inline: InlineArray<inlineCapacity, InlineNode>

        /// Token buffer for inline position validation.
        @usableFromInline
        var _inlineTokens: InlineArray<inlineCapacity, UInt32>

        /// Free-list next pointers for inline storage.
        @usableFromInline
        var _inlineNextFree: InlineArray<inlineCapacity, Int>

        @usableFromInline
        var _rootIndex: Int

        @usableFromInline
        var _count: Int

        @usableFromInline
        var _freeHead: Int

        /// Heap storage when spilled. Nil when using inline storage.
        @usableFromInline
        var _heap: Tree.N<Element, n>.Storage?

        /// Cached pointer to heap nodes. Only valid when _heap is non-nil.
        @usableFromInline
        var _heapPtr: UnsafeMutablePointer<Tree.N<Element, n>.Node>?

        /// Cached pointer to heap tokens. Only valid when _heap is non-nil.
        @usableFromInline
        var _heapTokens: UnsafeMutablePointer<UInt32>?

        /// Cached pointer to heap nextFree. Only valid when _heap is non-nil.
        @usableFromInline
        var _heapNextFree: UnsafeMutablePointer<Int>?

        /// Creates an empty small n-ary tree.
        @inlinable
        public init() {
            precondition(
                MemoryLayout<Element>.stride <= Self._maxStride,
                "Element stride (\(MemoryLayout<Element>.stride)) exceeds inline storage slot size (\(Self._maxStride) bytes). Use N.Bounded instead."
            )
            precondition(
                MemoryLayout<Element>.alignment <= MemoryLayout<Int>.alignment,
                "Element alignment (\(MemoryLayout<Element>.alignment)) exceeds inline slot alignment (\(MemoryLayout<Int>.alignment) bytes). Use N.Bounded instead."
            )
            self._inline = InlineArray(repeating: InlineNode())
            self._inlineTokens = InlineArray(repeating: 0)  // All start as free (even)
            self._inlineNextFree = InlineArray(repeating: -1)
            self._rootIndex = -1
            self._count = 0
            self._freeHead = -1
            self._heap = nil
            unsafe (self._heapPtr = nil)
            unsafe (self._heapTokens = nil)
            unsafe (self._heapNextFree = nil)
        }

        /// Whether the tree is currently using heap storage.
        @inlinable
        public var isSpilled: Bool { _heap != nil }

        deinit {
            let count = _count
            guard count > 0 else { return }

            if let heap = _heap {
                // Elements are on heap - Storage handles cleanup via its deinit
                heap.header.rootIndex = _rootIndex
                heap.header.count = _count
            } else {
                // Iterative post-order collection using explicit stack
                var `deinit` = Queue<Int>()
                `deinit`.reserve(count)

                var pending = Stack<Int>()
                var lastVisited: Int = -1

                if _rootIndex >= 0 {
                    pending.push(_rootIndex)
                }

                while !pending.isEmpty {
                    let current = pending.peek()!
                    let childIndices = _inline[current].childIndices

                    // Find rightmost unvisited child
                    var hasUnvisitedChild = false
                    for slot in stride(from: n - 1, through: 0, by: -1) {
                        let childIndex = childIndices[slot]
                        if childIndex >= 0 && childIndex != lastVisited {
                            // Check if we've already processed any later children
                            var laterChildVisited = false
                            for laterSlot in (slot + 1)..<n {
                                if childIndices[laterSlot] == lastVisited {
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

                // Deinitialize using immutable pointer cast to mutable
                let nodeStride = MemoryLayout<InlineNode>.stride
                let slotOffset = MemoryLayout<InlineNode>.offset(of: \.slot) ?? 0

                unsafe Swift.withUnsafePointer(to: _inline) { storagePtr in
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
        }
    }
}

// MARK: - Small Properties

extension Tree.N.Small {

    /// The number of nodes in the tree.
    @inlinable
    public var count: Int { _count }

    /// Whether the tree is empty.
    @inlinable
    public var isEmpty: Bool { _count == 0 }

    /// The position of the root node, or `nil` if the tree is empty.
    @inlinable
    public var root: Tree.Position? {
        guard _rootIndex >= 0 else { return nil }
        if let heapTokens = unsafe _heapTokens {
            return Tree.Position(index: _rootIndex, token: unsafe heapTokens[_rootIndex])
        } else {
            return Tree.Position(index: _rootIndex, token: _inlineTokens[_rootIndex])
        }
    }

    // MARK: - Position Validation

    /// Validates that a position refers to a currently-occupied slot.
    @usableFromInline
    func _validate(_ position: Tree.Position) throws(__TreeNSmallError) {
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

    /// Returns the position of a child at the given slot of the node at the given position.
    @inlinable
    public func child(of position: Tree.Position, slot: Tree.N<Element, n>.ChildSlot) -> Tree.Position? {
        do {
            try _validate(position)
        } catch {
            return nil
        }

        if let heapPtr = unsafe _heapPtr, let heapTokens = unsafe _heapTokens {
            let childIndex = unsafe heapPtr[position.index].childIndices[slot.index]
            guard childIndex >= 0 else { return nil }
            return Tree.Position(index: childIndex, token: unsafe heapTokens[childIndex])
        } else {
            let childIndex = _inline[position.index].childIndices[slot.index]
            guard childIndex >= 0 else { return nil }
            return Tree.Position(index: childIndex, token: _inlineTokens[childIndex])
        }
    }

    /// Returns the position of the parent of the node at the given position.
    @inlinable
    public func parent(of position: Tree.Position) -> Tree.Position? {
        do {
            try _validate(position)
        } catch {
            return nil
        }

        if let heapPtr = unsafe _heapPtr, let heapTokens = unsafe _heapTokens {
            let parentIndex = unsafe heapPtr[position.index].parentIndex
            guard parentIndex >= 0 else { return nil }
            return Tree.Position(index: parentIndex, token: unsafe heapTokens[parentIndex])
        } else {
            let parentIndex = _inline[position.index].parentIndex
            guard parentIndex >= 0 else { return nil }
            return Tree.Position(index: parentIndex, token: _inlineTokens[parentIndex])
        }
    }

    /// Returns the number of children of the node at the given position.
    @inlinable
    public func childCount(of position: Tree.Position) -> Int {
        do {
            try _validate(position)
        } catch {
            return 0
        }

        if let heapPtr = unsafe _heapPtr {
            return unsafe heapPtr[position.index].childCount
        } else {
            return _inline[position.index].childCount
        }
    }

    /// Returns whether the node at the given position is a leaf.
    @inlinable
    public func isLeaf(_ position: Tree.Position) -> Bool {
        do {
            try _validate(position)
        } catch {
            return false
        }

        if let heapPtr = unsafe _heapPtr {
            return unsafe heapPtr[position.index].childCount == 0
        } else {
            return _inline[position.index].childCount == 0
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
        let newStorage = Tree.N<Element, n>.Storage.create(minimumCapacity: newCapacity)

        // Copy tokens from inline to heap (1:1 for inline capacity range)
        if let heapTokens = unsafe newStorage._tokens {
            for i in 0..<inlineCapacity {
                unsafe (heapTokens[i] = _inlineTokens[i])
            }
        }

        // Copy nextFree from inline to heap
        if let heapNextFree = unsafe newStorage._nextFree {
            for i in 0..<inlineCapacity {
                unsafe (heapNextFree[i] = _inlineNextFree[i])
            }
        }

        // Move elements from inline to heap via pre-order traversal (maintaining indices)
        // Uses iterative traversal for consistency with other tree operations
        var pending = Stack<Int>()
        if _rootIndex >= 0 {
            pending.push(_rootIndex)
        }

        while !pending.isEmpty {
            let index = pending.pop()!
            guard _inline[index].isOccupied else { continue }

            let childIndices = _inline[index].childIndices
            let childCount = _inline[index].childCount
            let parentIndex = _inline[index].parentIndex

            // Move element
            let element = unsafe _inlineElementPointer(at: index).move()
            newStorage._initializeNode(
                at: index,
                element: element,
                parentIndex: parentIndex
            )
            // Copy child indices to new node
            let ptr = unsafe newStorage._nodesPointer
            unsafe (ptr[index].childIndices = childIndices)
            unsafe (ptr[index].childCount = childCount)
            _inline[index].isOccupied = false

            // Push children in reverse order so first child is processed first
            for slot in stride(from: n - 1, through: 0, by: -1) {
                let childIndex = childIndices[slot]
                if childIndex >= 0 { pending.push(childIndex) }
            }
        }

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
    mutating func _updateHeapPointers(_ newStorage: Tree.N<Element, n>.Storage) {
        _heap = newStorage
        unsafe (_heapPtr = newStorage._nodesPointer)
        unsafe (_heapTokens = newStorage._tokens)
        unsafe (_heapNextFree = newStorage._nextFree)
    }
}

// MARK: - Binary Tree Navigation (n == 2)

extension Tree.N.Small where n == 2 {

    /// Returns the position of the left child of the node at the given position.
    @inlinable
    public func left(of position: Tree.Position) -> Tree.Position? {
        child(of: position, slot: .left)
    }

    /// Returns the position of the right child of the node at the given position.
    @inlinable
    public func right(of position: Tree.Position) -> Tree.Position? {
        child(of: position, slot: .right)
    }
}

// MARK: - Small Insert Operations

extension Tree.N.Small {

    /// Inserts an element at the specified position.
    @inlinable
    @discardableResult
    public mutating func insert(
        _ element: consuming Element,
        at position: Tree.N<Element, n>.InsertPosition
    ) throws(__TreeNSmallError) -> Tree.Position {
        // If spilled to heap, use heap storage
        if _heap != nil {
            switch position {
            case .root:
                guard _rootIndex < 0 else {
                    throw .slotOccupied
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
                        let newStorage = Tree.N<Element, n>.Storage.create(minimumCapacity: newCapacity)
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
                return Tree.Position(index: index, token: token)

            case .child(of: let parent, slot: let slot):
                // Validate parent position
                try _validate(parent)
                guard unsafe _heapPtr![parent.index].childIndices[slot.index] < 0 else {
                    throw .slotOccupied
                }

                var index: Int
                if _heap!.header.freeHead >= 0 {
                    index = _heap!.header.freeHead
                    _heap!.header.freeHead = unsafe _heapNextFree![index]
                } else {
                    if _heap!.header.count >= _heap!.header.capacity {
                        let newCapacity = Swift.max(_heap!.header.capacity * 2, 8)
                        let newStorage = Tree.N<Element, n>.Storage.create(minimumCapacity: newCapacity)
                        _heap!._moveAllElements(to: newStorage)
                        _updateHeapPointers(newStorage)
                    }
                    index = _heap!.header.count
                }

                // Increment token (use fresh pointers after potential growth)
                unsafe (_heapTokens![index] &+= 1)
                let token = unsafe _heapTokens![index]

                _heap!._initializeNode(at: index, element: element, parentIndex: parent.index)
                unsafe (_heapPtr![parent.index].childIndices[slot.index] = index)
                unsafe (_heapPtr![parent.index].childCount += 1)
                _heap!.header.count += 1
                _count += 1
                return Tree.Position(index: index, token: token)
            }
        }

        // Using inline storage
        switch position {
        case .root:
            guard _rootIndex < 0 else {
                throw .slotOccupied
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
            _inline[index].childIndices = InlineArray(repeating: -1)
            _inline[index].childCount = 0
            _inline[index].parentIndex = -1
            _inline[index].isOccupied = true
            _rootIndex = index
            _count += 1
            return Tree.Position(index: index, token: token)

        case .child(of: let parent, slot: let slot):
            // Validate parent position
            try _validate(parent)
            guard _inline[parent.index].childIndices[slot.index] < 0 else {
                throw .slotOccupied
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
            _inline[index].childIndices = InlineArray(repeating: -1)
            _inline[index].childCount = 0
            _inline[index].parentIndex = parent.index
            _inline[index].isOccupied = true
            _inline[parent.index].childIndices[slot.index] = index
            _inline[parent.index].childCount += 1
            _count += 1
            return Tree.Position(index: index, token: token)
        }
    }

    /// Removes the leaf node at the specified position.
    @inlinable
    @discardableResult
    public mutating func remove(
        at position: Tree.Position
    ) throws(__TreeNSmallError) -> Element {
        // Validate position
        try _validate(position)

        if let heapPtr = unsafe _heapPtr, let heapTokens = unsafe _heapTokens,
           let heapNextFree = unsafe _heapNextFree {
            guard unsafe heapPtr[position.index].childCount == 0 else {
                throw .cannotRemoveNonLeaf
            }

            let parentIndex = unsafe heapPtr[position.index].parentIndex
            if parentIndex >= 0 {
                // Find and clear the child slot in parent
                for slot in 0..<n {
                    if unsafe heapPtr[parentIndex].childIndices[slot] == position.index {
                        unsafe (_heapPtr![parentIndex].childIndices[slot] = -1)
                        unsafe (_heapPtr![parentIndex].childCount -= 1)
                        break
                    }
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

            guard _inline[position.index].childCount == 0 else {
                throw .cannotRemoveNonLeaf
            }

            let parentIndex = _inline[position.index].parentIndex
            if parentIndex >= 0 {
                // Find and clear the child slot in parent
                for slot in 0..<n {
                    if _inline[parentIndex].childIndices[slot] == position.index {
                        _inline[parentIndex].childIndices[slot] = -1
                        _inline[parentIndex].childCount -= 1
                        break
                    }
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
        at position: Tree.Position
    ) throws(__TreeNSmallError) {
        // Validate position
        try _validate(position)

        if _heap != nil {
            let parentIndex = unsafe _heapPtr![position.index].parentIndex
            if parentIndex >= 0 {
                // Find and clear the child slot in parent
                for slot in 0..<n {
                    if unsafe _heapPtr![parentIndex].childIndices[slot] == position.index {
                        unsafe (_heapPtr![parentIndex].childIndices[slot] = -1)
                        unsafe (_heapPtr![parentIndex].childCount -= 1)
                        break
                    }
                }
            } else {
                _rootIndex = -1
                _heap!.header.rootIndex = -1
            }

            // Iterative post-order removal using explicit stack
            var pending = Stack<Int>()
            var lastVisited: Int = -1

            pending.push(position.index)

            while !pending.isEmpty {
                let current = pending.peek()!
                let childIndices = unsafe _heapPtr![current].childIndices

                // Find rightmost unvisited child
                var hasUnvisitedChild = false
                for slot in stride(from: n - 1, through: 0, by: -1) {
                    let childIndex = childIndices[slot]
                    if childIndex >= 0 && childIndex != lastVisited {
                        // Check if we've already processed any later children
                        var laterChildVisited = false
                        for laterSlot in (slot + 1)..<n {
                            if childIndices[laterSlot] == lastVisited {
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
                    _heap!._deinitializeNode(at: current)
                    unsafe (_heapTokens![current] &+= 1)
                    unsafe (_heapNextFree![current] = _heap!.header.freeHead)
                    _heap!.header.freeHead = current
                    _heap!.header.count -= 1
                    _count -= 1
                    lastVisited = current
                }
            }
        } else {
            guard _inline[position.index].isOccupied else {
                throw .invalidPosition
            }

            let parentIndex = _inline[position.index].parentIndex
            if parentIndex >= 0 {
                // Find and clear the child slot in parent
                for slot in 0..<n {
                    if _inline[parentIndex].childIndices[slot] == position.index {
                        _inline[parentIndex].childIndices[slot] = -1
                        _inline[parentIndex].childCount -= 1
                        break
                    }
                }
            } else {
                _rootIndex = -1
            }

            // Iterative post-order removal using explicit stack
            var pending = Stack<Int>()
            var lastVisited: Int = -1

            pending.push(position.index)

            while !pending.isEmpty {
                let current = pending.peek()!
                guard _inline[current].isOccupied else {
                    _ = pending.pop()
                    continue
                }

                let childIndices = _inline[current].childIndices

                // Find rightmost unvisited child
                var hasUnvisitedChild = false
                for slot in stride(from: n - 1, through: 0, by: -1) {
                    let childIndex = childIndices[slot]
                    if childIndex >= 0 && _inline[childIndex].isOccupied && childIndex != lastVisited {
                        // Check if we've already processed any later children
                        var laterChildVisited = false
                        for laterSlot in (slot + 1)..<n {
                            if childIndices[laterSlot] == lastVisited {
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
                    unsafe _inlineElementPointer(at: current).deinitialize(count: 1)
                    _inline[current].isOccupied = false
                    _inlineTokens[current] &+= 1
                    _inlineNextFree[current] = _freeHead
                    _freeHead = current
                    _count -= 1
                    lastVisited = current
                }
            }
        }
    }

    /// Accesses the element at the specified position via a borrowing closure.
    @inlinable
    public func peek<R>(
        at position: Tree.Position,
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
            var pending = Stack<Int>()
            var lastVisited: Int = -1

            if _rootIndex >= 0 {
                pending.push(_rootIndex)
            }

            while !pending.isEmpty {
                let current = pending.peek()!
                guard _inline[current].isOccupied else {
                    _ = pending.pop()
                    continue
                }

                let childIndices = _inline[current].childIndices

                // Find rightmost unvisited child
                var hasUnvisitedChild = false
                for slot in stride(from: n - 1, through: 0, by: -1) {
                    let childIndex = childIndices[slot]
                    if childIndex >= 0 && _inline[childIndex].isOccupied && childIndex != lastVisited {
                        // Check if we've already processed any later children
                        var laterChildVisited = false
                        for laterSlot in (slot + 1)..<n {
                            if childIndices[laterSlot] == lastVisited {
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
                    unsafe _inlineElementPointer(at: current).deinitialize(count: 1)
                    _inline[current].isOccupied = false
                    _inlineTokens[current] &+= 1
                    lastVisited = current
                }
            }
        }

        _rootIndex = -1
        _count = 0
        _freeHead = -1
    }

    /// Iterates over all elements in pre-order.
    ///
    /// Uses iterative traversal to avoid stack overflow on deep trees.
    @inlinable
    public func forEachPreOrder(_ body: (borrowing Element) -> Void) {
        var pending = Stack<Int>()
        if _rootIndex >= 0 {
            pending.push(_rootIndex)
        }

        if let heapPtr = unsafe _heapPtr {
            while !pending.isEmpty {
                let index = pending.pop()!
                unsafe body(heapPtr[index].element)

                // Push children in reverse order so first child is processed first
                let childIndices = unsafe heapPtr[index].childIndices
                for slot in stride(from: n - 1, through: 0, by: -1) {
                    let childIndex = childIndices[slot]
                    if childIndex >= 0 { pending.push(childIndex) }
                }
            }
        } else {
            while !pending.isEmpty {
                let index = pending.pop()!
                guard _inline[index].isOccupied else { continue }
                unsafe body(_inlineReadElementPointer(at: index).pointee)

                // Push children in reverse order so first child is processed first
                let childIndices = _inline[index].childIndices
                for slot in stride(from: n - 1, through: 0, by: -1) {
                    let childIndex = childIndices[slot]
                    if childIndex >= 0 { pending.push(childIndex) }
                }
            }
        }
    }

    /// Iterates over all elements in post-order.
    ///
    /// Uses iterative traversal to avoid stack overflow on deep trees.
    @inlinable
    public func forEachPostOrder(_ body: (borrowing Element) -> Void) {
        var pending = Stack<Int>()
        var lastVisited: Int = -1

        if _rootIndex >= 0 {
            pending.push(_rootIndex)
        }

        if let heapPtr = unsafe _heapPtr {
            while !pending.isEmpty {
                let current = pending.peek()!
                let childIndices = unsafe heapPtr[current].childIndices

                // Find rightmost unvisited child
                var hasUnvisitedChild = false
                for slot in stride(from: n - 1, through: 0, by: -1) {
                    let childIndex = childIndices[slot]
                    if childIndex >= 0 && childIndex != lastVisited {
                        // Check if we've already processed any later children
                        var laterChildVisited = false
                        for laterSlot in (slot + 1)..<n {
                            if childIndices[laterSlot] == lastVisited {
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
                    unsafe body(heapPtr[current].element)
                    lastVisited = current
                }
            }
        } else {
            while !pending.isEmpty {
                let current = pending.peek()!
                guard _inline[current].isOccupied else {
                    _ = pending.pop()
                    continue
                }

                let childIndices = _inline[current].childIndices

                // Find rightmost unvisited child
                var hasUnvisitedChild = false
                for slot in stride(from: n - 1, through: 0, by: -1) {
                    let childIndex = childIndices[slot]
                    if childIndex >= 0 && _inline[childIndex].isOccupied && childIndex != lastVisited {
                        // Check if we've already processed any later children
                        var laterChildVisited = false
                        for laterSlot in (slot + 1)..<n {
                            if childIndices[laterSlot] == lastVisited {
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
                    unsafe body(_inlineReadElementPointer(at: current).pointee)
                    lastVisited = current
                }
            }
        }
    }

    /// Iterates over all elements in level-order.
    @inlinable
    public func forEachLevelOrder(_ body: (borrowing Element) -> Void) {
        guard _rootIndex >= 0 else { return }

        if let heapPtr = unsafe _heapPtr {
            var pending = Queue<Int>()
            pending.enqueue(_rootIndex)

            while !pending.isEmpty {
                let index = pending.dequeue()!

                unsafe body(heapPtr[index].element)

                let childIndices = unsafe heapPtr[index].childIndices
                for slot in 0..<n {
                    let childIndex = childIndices[slot]
                    if childIndex >= 0 { pending.enqueue(childIndex) }
                }
            }
        } else {
            var pending = Queue<Int>()
            pending.enqueue(_rootIndex)

            while !pending.isEmpty {
                let index = pending.dequeue()!

                guard _inline[index].isOccupied else { continue }

                unsafe body(_inlineReadElementPointer(at: index).pointee)

                let childIndices = _inline[index].childIndices
                for slot in 0..<n {
                    let childIndex = childIndices[slot]
                    if childIndex >= 0 { pending.enqueue(childIndex) }
                }
            }
        }
    }

    /// Computes the height of the tree.
    ///
    /// Uses iterative traversal to avoid stack overflow on deep trees.
    @inlinable
    public var height: Int {
        guard _rootIndex >= 0 else { return -1 }

        var maxHeight = 0
        var pending = Stack<(index: Int, depth: Int)>()
        pending.push((_rootIndex, 0))

        if let heapPtr = unsafe _heapPtr {
            while !pending.isEmpty {
                let (index, depth) = pending.pop()!
                maxHeight = Swift.max(maxHeight, depth)

                let childIndices = unsafe heapPtr[index].childIndices
                for slot in 0..<n {
                    let childIndex = childIndices[slot]
                    if childIndex >= 0 {
                        pending.push((childIndex, depth + 1))
                    }
                }
            }
        } else {
            while !pending.isEmpty {
                let (index, depth) = pending.pop()!
                guard _inline[index].isOccupied else { continue }

                maxHeight = Swift.max(maxHeight, depth)

                let childIndices = _inline[index].childIndices
                for slot in 0..<n {
                    let childIndex = childIndices[slot]
                    if childIndex >= 0 {
                        pending.push((childIndex, depth + 1))
                    }
                }
            }
        }

        return maxHeight
    }
}

// MARK: - Binary Tree In-Order (n == 2)

extension Tree.N.Small where n == 2 {

    /// Iterates over all elements in in-order (left, root, right).
    ///
    /// Only available for binary trees (n == 2).
    /// Uses iterative traversal to avoid stack overflow on deep trees.
    @inlinable
    public func forEachInOrder(_ body: (borrowing Element) -> Void) {
        var pending = Stack<Int>()
        var current = _rootIndex

        if let heapPtr = unsafe _heapPtr {
            while current >= 0 || !pending.isEmpty {
                while current >= 0 {
                    pending.push(current)
                    current = unsafe heapPtr[current].childIndices[0]  // left child
                }

                current = pending.pop()!
                unsafe body(heapPtr[current].element)
                current = unsafe heapPtr[current].childIndices[1]  // right child
            }
        } else {
            while current >= 0 || !pending.isEmpty {
                while current >= 0 && _inline[current].isOccupied {
                    pending.push(current)
                    current = _inline[current].childIndices[0]  // left child
                }

                guard !pending.isEmpty else { break }
                current = pending.pop()!
                guard _inline[current].isOccupied else {
                    current = -1
                    continue
                }
                unsafe body(_inlineReadElementPointer(at: current).pointee)
                current = _inline[current].childIndices[1]  // right child
            }
        }
    }
}

// MARK: - Small Copyable Extensions

extension Tree.N.Small where Element: Copyable {

    /// Returns the element at the specified position.
    @inlinable
    public func peek(at position: Tree.Position) -> Element? {
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

// MARK: - Sendable

extension Tree.N.Small: @unchecked Sendable where Element: Sendable {}
