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
public import Buffer_Arena_Primitives

/// A dynamically-growing n-ary tree with compile-time bounded arity.
///
/// `Tree.N<n>` is the general-purpose bounded-arity tree primitive. It provides O(1)
/// node insertion and O(1) navigation with automatic capacity growth. Each node can
/// have at most `n` children, with child slots being sparse (holes permitted).
///
/// ## Example
///
/// ```swift
/// // Binary tree (n=2)
/// var tree = Tree<Int>.N<2>()
/// let root = try tree.insert(1, at: .root)
/// let left = try tree.insert(2, at: .left(of: root))
/// let right = try tree.insert(3, at: .right(of: root))
///
/// tree.forEachInOrder { element in
///     print(element)  // 2, 1, 3
/// }
///
/// // Quad tree (n=4)
/// var quad = Tree<Int>.N<4>()
/// let qroot = try quad.insert(0, at: .root)
/// _ = try quad.insert(1, at: .northwest(of: qroot))
/// _ = try quad.insert(2, at: .southeast(of: qroot))
/// ```
///
/// ## Sparse Child Slots
///
/// Per [TREE-003], `Tree<Element>.N<n>` uses sparse child slots. Each node
/// stores `childIndices[0..<n]` where `-1` denotes empty. Holes are permitted.
/// Insertion into an occupied slot fails with `.slotOccupied` error.
///
/// ## Variants
///
/// - ``N``: Dynamically-growing with amortized O(1) insert (this type)
/// - ``N/Bounded``: Fixed-capacity with upfront allocation, throws on overflow
/// - ``N/Inline``: Zero-allocation inline storage with compile-time capacity
/// - ``N/Small``: Inline storage with automatic spill to heap
///
/// ## Move-Only Support
///
/// Both the tree and its elements can be `~Copyable`:
///
/// ```swift
/// struct FileHandle: ~Copyable { ... }
/// var handles = Tree<FileHandle>.N<2>()
/// let root = try handles.insert(FileHandle(), at: .root)
/// ```
///
/// ## Copy-on-Write
///
/// When `Element` is `Copyable`, `Tree.N` uses copy-on-write semantics:
/// copies share storage until mutation, providing efficient value semantics.
///
/// ## Arena-Based Storage
///
/// Uses `Buffer<Node>.Arena` for storage — all nodes are stored contiguously
/// with generation-token validation, LIFO free-list recycling, and automatic
/// growth. Nodes reference each other by index rather than pointer.
///
/// - Note: This type is declared inside `Tree<Element>`'s primary struct
///   declaration (not in an extension) per [TREE-008] to ensure proper
///   `~Copyable` constraint propagation.
extension Tree {

    @safe
    public struct N<Element: ~Copyable, let n: Int>: ~Copyable {

        // MARK: - Typealiases

        /// Errors that can occur during n-ary tree operations.
        public typealias Error = __TreeNError

        /// A bounded child slot index (0..<n).
        public typealias ChildSlot = __TreeNChildSlot<n>

        /// Specifies where to insert a new node.
        public typealias InsertPosition = __TreeNInsertPosition<n>

        // MARK: - Node

        /// A node in the arena-based n-ary tree.
        @usableFromInline
        struct Node: ~Copyable {
            /// The element stored in this node.
            @usableFromInline var element: Element
            /// Child indices (-1 for empty slots). Uses sparse representation per [TREE-003].
            @usableFromInline var childIndices: InlineArray<n, Int>
            /// Number of occupied child slots.
            @usableFromInline var childCount: Int
            /// Index of parent (-1 for root).
            @usableFromInline var parentIndex: Int

            @usableFromInline
            init(element: consuming Element, parentIndex: Int = -1) {
                self.element = element
                self.childIndices = InlineArray(repeating: -1)
                self.childCount = 0
                self.parentIndex = parentIndex
            }
        }

        // MARK: - Storage

        @usableFromInline
        var _arena: Buffer<Node>.Arena

        /// Index of root node (-1 if empty).
        @usableFromInline
        var _rootIndex: Int

        // MARK: - Helpers

        /// Converts a raw Int index to a typed slot index.
        @inlinable
        func _slot(_ index: Int) -> Index<Node> {
            Index<Node>(Ordinal(UInt(index)))
        }

        // MARK: - Initialization

        /// Creates an empty n-ary tree.
        @inlinable
        public init() {
            self._arena = Buffer<Node>.Arena(minimumCapacity: .one)
            self._rootIndex = -1
        }

        /// Creates an empty n-ary tree with reserved capacity.
        ///
        /// - Parameter minimumCapacity: The minimum number of nodes to reserve space for.
        /// - Throws: ``Error/invalidCapacity`` if capacity is negative.
        @inlinable
        public init(minimumCapacity: Int) throws(__TreeNError) {
            guard minimumCapacity >= 0 else {
                throw .invalidCapacity
            }
            self._arena = Buffer<Node>.Arena(
                minimumCapacity: Index<Node>.Count(Cardinal(UInt(Swift.max(minimumCapacity, 1))))
            )
            self._rootIndex = -1
        }

        // MARK: - Properties

        /// The number of nodes in the tree.
        @inlinable
        public var count: Int { Int(bitPattern: _arena.occupied) }

        /// Whether the tree is empty.
        @inlinable
        public var isEmpty: Bool { _arena.isEmpty }

        /// The maximum arity (number of children per node).
        @inlinable
        public static var arity: Int { n }

        /// The position of the root node, or `nil` if the tree is empty.
        @inlinable
        public var root: Tree.Position? {
            guard _rootIndex >= 0 else { return nil }
            let token = _arena.token(at: _slot(_rootIndex))
            return Tree.Position(index: _rootIndex, token: token)
        }

        // MARK: - Position Validation

        /// Validates that a position refers to a currently-occupied slot.
        ///
        /// Token validation provides O(1) safety checking:
        /// - Stale positions (after removal) are detected and rejected
        /// - No node memory is accessed without validation
        /// - Tokens use odd/even scheme: odd = occupied, even = free
        @usableFromInline
        func _validate(_ position: Tree.Position) throws(__TreeNError) {
            guard position.index >= 0 else { throw .invalidPosition }
            let arenaPos = Buffer<Node>.Arena.Position(
                index: UInt32(position.index), token: position.token
            )
            guard _arena.isValid(arenaPos) else { throw .invalidPosition }
        }
    }
}

// MARK: - Navigation

extension Tree.N where Element: ~Copyable {

    /// Returns the position of the child at the given slot.
    ///
    /// - Parameters:
    ///   - position: The position of the parent node.
    ///   - slot: The child slot (0..<n).
    /// - Returns: The position of the child, or `nil` if the slot is empty.
    /// - Note: Returns `nil` if the position is invalid (stale or out of bounds).
    @inlinable
    public func child(of position: Tree.Position, slot: ChildSlot) -> Tree.Position? {
        do {
            try _validate(position)
        } catch {
            return nil
        }
        let nodePtr = unsafe _arena.pointer(at: _slot(position.index))
        let childIndex = unsafe nodePtr.pointee.childIndices[slot.index]
        guard childIndex >= 0 else { return nil }
        let token = _arena.token(at: _slot(childIndex))
        return Tree.Position(index: childIndex, token: token)
    }

    /// Returns the position of the parent of the node at the given position.
    ///
    /// - Parameter position: The position of the child node.
    /// - Returns: The position of the parent, or `nil` if the node is the root.
    /// - Note: Returns `nil` if the position is invalid (stale or out of bounds).
    @inlinable
    public func parent(of position: Tree.Position) -> Tree.Position? {
        do {
            try _validate(position)
        } catch {
            return nil
        }
        let parentIndex = unsafe _arena.pointer(at: _slot(position.index)).pointee.parentIndex
        guard parentIndex >= 0 else { return nil }
        let token = _arena.token(at: _slot(parentIndex))
        return Tree.Position(index: parentIndex, token: token)
    }

    /// Returns whether the node at the given position is a leaf (has no children).
    ///
    /// - Parameter position: The position to check.
    /// - Returns: `true` if the node has no children, `false` otherwise.
    /// - Note: Returns `false` if the position is invalid (stale or out of bounds).
    @inlinable
    public func isLeaf(_ position: Tree.Position) -> Bool {
        do {
            try _validate(position)
        } catch {
            return false
        }
        return unsafe _arena.pointer(at: _slot(position.index)).pointee.childCount == 0
    }

    /// Returns the number of children of the node at the given position.
    ///
    /// - Parameter position: The position to check.
    /// - Returns: The number of occupied child slots, or `nil` if position is invalid.
    @inlinable
    public func childCount(of position: Tree.Position) -> Int? {
        do {
            try _validate(position)
        } catch {
            return nil
        }
        return unsafe _arena.pointer(at: _slot(position.index)).pointee.childCount
    }

    /// Returns the position of the leftmost (first non-empty) child.
    ///
    /// - Parameter position: The position of the parent node.
    /// - Returns: The position of the leftmost child, or `nil` if no children exist.
    @inlinable
    public func leftmostChild(of position: Tree.Position) -> Tree.Position? {
        do {
            try _validate(position)
        } catch {
            return nil
        }
        let nodePtr = unsafe _arena.pointer(at: _slot(position.index))
        for slot in 0..<n {
            let childIndex = unsafe nodePtr.pointee.childIndices[slot]
            if childIndex >= 0 {
                let token = _arena.token(at: _slot(childIndex))
                return Tree.Position(index: childIndex, token: token)
            }
        }
        return nil
    }

    /// Returns the position of the rightmost (last non-empty) child.
    ///
    /// - Parameter position: The position of the parent node.
    /// - Returns: The position of the rightmost child, or `nil` if no children exist.
    @inlinable
    public func rightmostChild(of position: Tree.Position) -> Tree.Position? {
        do {
            try _validate(position)
        } catch {
            return nil
        }
        let nodePtr = unsafe _arena.pointer(at: _slot(position.index))
        for slot in stride(from: n - 1, through: 0, by: -1) {
            let childIndex = unsafe nodePtr.pointee.childIndices[slot]
            if childIndex >= 0 {
                let token = _arena.token(at: _slot(childIndex))
                return Tree.Position(index: childIndex, token: token)
            }
        }
        return nil
    }
}

// MARK: - Binary Tree Navigation Convenience (n == 2)

extension Tree.N where Element: ~Copyable, n == 2 {

    /// Returns the position of the left child of the node at the given position.
    ///
    /// - Parameter position: The position of the parent node.
    /// - Returns: The position of the left child, or `nil` if there is no left child.
    /// - Note: Returns `nil` if the position is invalid (stale or out of bounds).
    @inlinable
    public func left(of position: Tree.Position) -> Tree.Position? {
        child(of: position, slot: .left)
    }

    /// Returns the position of the right child of the node at the given position.
    ///
    /// - Parameter position: The position of the parent node.
    /// - Returns: The position of the right child, or `nil` if there is no right child.
    /// - Note: Returns `nil` if the position is invalid (stale or out of bounds).
    @inlinable
    public func right(of position: Tree.Position) -> Tree.Position? {
        child(of: position, slot: .right)
    }
}

// MARK: - Insert Operations (~Copyable)

extension Tree.N where Element: ~Copyable {

    /// Inserts an element at the specified position.
    ///
    /// - Parameters:
    ///   - element: The element to insert.
    ///   - position: Where to insert the element.
    /// - Returns: The position of the newly inserted node (with token for validation).
    /// - Throws: ``Error/slotOccupied`` if the child slot is already occupied,
    ///           ``Error/invalidPosition`` if the parent position is invalid or stale.
    @inlinable
    @discardableResult
    public mutating func insert(
        _ element: consuming Element,
        at position: InsertPosition
    ) throws(__TreeNError) -> Tree.Position {
        switch position {
        case .root:
            guard _rootIndex < 0 else {
                throw .slotOccupied
            }
            let arenaPos = _arena.insert(Node(element: element))
            _rootIndex = Int(arenaPos.index)
            return Tree.Position(index: Int(arenaPos.index), token: arenaPos.token)

        case .child(of: let parent, slot: let slot):
            // Validate parent position (token check)
            try _validate(parent)
            // Check child slot is empty (pointer valid before insert)
            do {
                let parentPtr = unsafe _arena.pointer(at: _slot(parent.index))
                guard unsafe parentPtr.pointee.childIndices[slot.index] < 0 else {
                    throw .slotOccupied
                }
            }
            // Insert (may grow, invalidating previous pointers)
            let arenaPos = _arena.insert(
                Node(element: element, parentIndex: parent.index)
            )
            let index = Int(arenaPos.index)
            // Get fresh pointer after possible growth
            let parentPtr = unsafe _arena.pointer(at: _slot(parent.index))
            unsafe (parentPtr.pointee.childIndices[slot.index] = index)
            unsafe (parentPtr.pointee.childCount += 1)
            return Tree.Position(index: index, token: arenaPos.token)
        }
    }

    /// Removes the leaf node at the specified position.
    ///
    /// - Parameter position: The position of the node to remove. Must be a leaf.
    /// - Returns: The element that was stored at the position.
    /// - Throws: ``Error/invalidPosition`` if the position is invalid or stale,
    ///           ``Error/cannotRemoveNonLeaf`` if the node has children.
    @inlinable
    @discardableResult
    public mutating func remove(at position: Tree.Position) throws(__TreeNError) -> Element {
        // Validate position (token check)
        try _validate(position)

        let nodePtr = unsafe _arena.pointer(at: _slot(position.index))
        guard unsafe nodePtr.pointee.childCount == 0 else {
            throw .cannotRemoveNonLeaf
        }

        // Update parent's child pointer
        let parentIndex = unsafe nodePtr.pointee.parentIndex
        if parentIndex >= 0 {
            let parentPtr = unsafe _arena.pointer(at: _slot(parentIndex))
            // Find which slot this child occupies
            for slot in 0..<n {
                if unsafe parentPtr.pointee.childIndices[slot] == position.index {
                    unsafe (parentPtr.pointee.childIndices[slot] = -1)
                    unsafe (parentPtr.pointee.childCount -= 1)
                    break
                }
            }
        } else {
            // This is the root
            _rootIndex = -1
        }

        // Move element out and release slot
        let node = _arena.remove(at: _slot(position.index))
        return node.element
    }

    /// Removes the subtree rooted at the specified position.
    ///
    /// All nodes in the subtree are removed and their elements are deinitialized
    /// in post-order (children before parents).
    ///
    /// - Parameter position: The position of the root of the subtree to remove.
    /// - Throws: ``Error/invalidPosition`` if the position is invalid or stale.
    @inlinable
    public mutating func removeSubtree(at position: Tree.Position) throws(__TreeNError) {
        // Validate position (token check)
        try _validate(position)

        // Update parent's child pointer
        let parentIndex = unsafe _arena.pointer(at: _slot(position.index)).pointee.parentIndex
        if parentIndex >= 0 {
            let parentPtr = unsafe _arena.pointer(at: _slot(parentIndex))
            // Find which slot this child occupies
            for slot in 0..<n {
                if unsafe parentPtr.pointee.childIndices[slot] == position.index {
                    unsafe (parentPtr.pointee.childIndices[slot] = -1)
                    unsafe (parentPtr.pointee.childCount -= 1)
                    break
                }
            }
        } else {
            // This is the root
            _rootIndex = -1
        }

        // Iterative post-order removal using explicit stack
        var pending = Stack<Int>()
        var lastVisited: Int = -1

        pending.push(position.index)

        while !pending.isEmpty {
            let current = pending.peek()!
            let nodePtr = unsafe _arena.pointer(at: _slot(current))
            let childIndices = unsafe nodePtr.pointee.childIndices

            // Find rightmost existing child index
            var rightmostChildIndex: Int = -1
            for slot in stride(from: n - 1, through: 0, by: -1) {
                if childIndices[slot] >= 0 {
                    rightmostChildIndex = childIndices[slot]
                    break
                }
            }

            // Find leftmost existing child index
            var leftmostChildIndex: Int = -1
            for slot in 0..<n {
                if childIndices[slot] >= 0 {
                    leftmostChildIndex = childIndices[slot]
                    break
                }
            }

            // Process current if:
            // 1. It's a leaf (no children), OR
            // 2. We came from the rightmost child, OR
            // 3. We came from leftmost child AND no other children exist
            let isLeaf = rightmostChildIndex < 0
            let cameFromRightmost = rightmostChildIndex >= 0 && rightmostChildIndex == lastVisited
            let cameFromLeftmostNoOther = leftmostChildIndex >= 0 && leftmostChildIndex == lastVisited && leftmostChildIndex == rightmostChildIndex

            if isLeaf || cameFromRightmost || cameFromLeftmostNoOther {
                _ = pending.pop()
                _arena.free(at: _slot(current))
                lastVisited = current
            } else {
                // Push children in reverse order (rightmost first so leftmost is processed first)
                for slot in stride(from: n - 1, through: 0, by: -1) {
                    let childIndex = childIndices[slot]
                    if childIndex >= 0 {
                        pending.push(childIndex)
                    }
                }
            }
        }
    }

    /// Accesses the element at the specified position via a borrowing closure.
    ///
    /// - Parameters:
    ///   - position: The position of the node.
    ///   - body: A closure that receives a borrowing reference to the element.
    /// - Returns: The value returned by `body`, or `nil` if the position is invalid or stale.
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
        _rootIndex = -1
    }

    /// Computes the height of the tree.
    ///
    /// The height is the length of the longest path from the root to a leaf.
    /// An empty tree has height -1, a single-node tree has height 0.
    ///
    /// Uses iterative traversal to avoid stack overflow on deep trees.
    @inlinable
    public var height: Int {
        guard _rootIndex >= 0 else { return -1 }

        var maxHeight = 0
        var pending = Stack<(index: Int, depth: Int)>()
        pending.push((_rootIndex, 0))

        while !pending.isEmpty {
            let (index, depth) = pending.pop()!
            maxHeight = Swift.max(maxHeight, depth)

            let nodePtr = unsafe _arena.pointer(at: _slot(index))
            for slot in 0..<n {
                let childIndex = unsafe nodePtr.pointee.childIndices[slot]
                if childIndex >= 0 {
                    pending.push((childIndex, depth + 1))
                }
            }
        }

        return maxHeight
    }
}

// MARK: - Traversal

extension Tree.N where Element: ~Copyable {

    /// Iterates over all elements in pre-order using a borrowing closure.
    ///
    /// Uses iterative traversal to avoid stack overflow on deep trees.
    /// - Parameter body: A closure called with each element in pre-order.
    @inlinable
    public func forEachPreOrder(_ body: (borrowing Element) -> Void) {
        var pending = Stack<Int>()
        if _rootIndex >= 0 {
            pending.push(_rootIndex)
        }

        while !pending.isEmpty {
            let index = pending.pop()!
            let nodePtr = unsafe _arena.pointer(at: _slot(index))
            unsafe body(nodePtr.pointee.element)

            // Push children in reverse order so first child is processed first
            for slot in stride(from: n - 1, through: 0, by: -1) {
                let childIndex = unsafe nodePtr.pointee.childIndices[slot]
                if childIndex >= 0 {
                    pending.push(childIndex)
                }
            }
        }
    }

    /// Iterates over all elements in post-order using a borrowing closure.
    ///
    /// Uses iterative traversal to avoid stack overflow on deep trees.
    /// - Parameter body: A closure called with each element in post-order.
    @inlinable
    public func forEachPostOrder(_ body: (borrowing Element) -> Void) {
        var pending = Stack<Int>()
        var lastVisited: Int = -1

        if _rootIndex >= 0 {
            pending.push(_rootIndex)
        }

        while !pending.isEmpty {
            let current = pending.peek()!
            let nodePtr = unsafe _arena.pointer(at: _slot(current))
            let childIndices = unsafe nodePtr.pointee.childIndices

            // Find rightmost existing child index
            var rightmostChildIndex: Int = -1
            for slot in stride(from: n - 1, through: 0, by: -1) {
                if childIndices[slot] >= 0 {
                    rightmostChildIndex = childIndices[slot]
                    break
                }
            }

            // Find leftmost existing child index
            var leftmostChildIndex: Int = -1
            for slot in 0..<n {
                if childIndices[slot] >= 0 {
                    leftmostChildIndex = childIndices[slot]
                    break
                }
            }

            // Process current if:
            // 1. It's a leaf (no children), OR
            // 2. We came from the rightmost child, OR
            // 3. We came from leftmost child AND no other children exist
            let isLeaf = rightmostChildIndex < 0
            let cameFromRightmost = rightmostChildIndex >= 0 && rightmostChildIndex == lastVisited
            let cameFromLeftmostNoOther = leftmostChildIndex >= 0 && leftmostChildIndex == lastVisited && leftmostChildIndex == rightmostChildIndex

            if isLeaf || cameFromRightmost || cameFromLeftmostNoOther {
                _ = pending.pop()
                unsafe body(nodePtr.pointee.element)
                lastVisited = current
            } else {
                // Push children in reverse order (rightmost first so leftmost is processed first)
                for slot in stride(from: n - 1, through: 0, by: -1) {
                    let childIndex = childIndices[slot]
                    if childIndex >= 0 {
                        pending.push(childIndex)
                    }
                }
            }
        }
    }

    /// Iterates over all elements in level-order (breadth-first) using a borrowing closure.
    ///
    /// - Parameter body: A closure called with each element in level-order.
    @inlinable
    public func forEachLevelOrder(_ body: (borrowing Element) -> Void) {
        guard _rootIndex >= 0 else { return }

        var pending = Queue<Int>()
        pending.enqueue(_rootIndex)

        while !pending.isEmpty {
            let index = pending.dequeue()!
            let nodePtr = unsafe _arena.pointer(at: _slot(index))

            unsafe body(nodePtr.pointee.element)

            for slot in 0..<n {
                let childIndex = unsafe nodePtr.pointee.childIndices[slot]
                if childIndex >= 0 {
                    pending.enqueue(childIndex)
                }
            }
        }
    }
}

// MARK: - Binary Tree In-Order Traversal (n == 2)

extension Tree.N where Element: ~Copyable, n == 2 {

    /// Iterates over all elements in in-order using a borrowing closure.
    ///
    /// In-order traversal visits left subtree, then root, then right subtree.
    /// Only available for binary trees (n == 2).
    ///
    /// Uses iterative traversal to avoid stack overflow on deep trees.
    /// - Parameter body: A closure called with each element in in-order.
    @inlinable
    public func forEachInOrder(_ body: (borrowing Element) -> Void) {
        var pending = Stack<Int>()
        var current = _rootIndex

        while current >= 0 || !pending.isEmpty {
            // Go to leftmost node
            while current >= 0 {
                pending.push(current)
                current = unsafe _arena.pointer(at: _slot(current)).pointee.childIndices[0]  // left child
            }

            // Process node
            current = pending.pop()!
            let nodePtr = unsafe _arena.pointer(at: _slot(current))
            unsafe body(nodePtr.pointee.element)

            // Move to right subtree
            current = unsafe nodePtr.pointee.childIndices[1]  // right child
        }
    }
}

// MARK: - Copyable Element Extensions

extension Tree.N where Element: Copyable {

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
        at position: InsertPosition
    ) throws(__TreeNError) -> Tree.Position {
        makeUnique()

        switch position {
        case .root:
            guard _rootIndex < 0 else {
                throw .slotOccupied
            }
            let arenaPos = _arena.insert(Node(element: element))
            _rootIndex = Int(arenaPos.index)
            return Tree.Position(index: Int(arenaPos.index), token: arenaPos.token)

        case .child(of: let parent, slot: let slot):
            // Validate parent position (token check)
            try _validate(parent)
            // Check child slot is empty (pointer valid before insert)
            do {
                let parentPtr = unsafe _arena.pointer(at: _slot(parent.index))
                guard unsafe parentPtr.pointee.childIndices[slot.index] < 0 else {
                    throw .slotOccupied
                }
            }
            // Insert (may grow, invalidating previous pointers)
            let arenaPos = _arena.insert(
                Node(element: element, parentIndex: parent.index)
            )
            let index = Int(arenaPos.index)
            // Get fresh pointer after possible growth
            let parentPtr = unsafe _arena.pointer(at: _slot(parent.index))
            unsafe (parentPtr.pointee.childIndices[slot.index] = index)
            unsafe (parentPtr.pointee.childCount += 1)
            return Tree.Position(index: index, token: arenaPos.token)
        }
    }

    /// Returns the element at the specified position.
    ///
    /// - Parameter position: The position of the node.
    /// - Returns: The element at the position, or `nil` if invalid or stale.
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

// MARK: - Conditional Copyable

extension Tree.N.Node: Copyable where Element: Copyable {}
extension Tree.N: Copyable where Element: Copyable {}

// MARK: - Sendable

extension Tree.N: @unchecked Sendable where Element: Sendable {}
