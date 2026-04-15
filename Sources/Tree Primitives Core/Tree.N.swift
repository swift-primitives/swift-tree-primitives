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

public import Queue_Primitives_Core
public import Queue_Dynamic_Primitives
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
/// stores `childIndices[0..<n]` where `nil` denotes empty. Holes are permitted.
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
/// - Note: Declared in an extension. Swift 6.2.4 resolved the value-generic
///   nested type extension restriction ([COPY-FIX-002]).
extension Tree where Element: ~Copyable {

    @safe
    public struct N<let n: Int>: ~Copyable {

        // MARK: - Typealiases

        /// Errors that can occur during n-ary tree operations.
        public typealias Error = __TreeNError

        /// A bounded child slot index (0..<n).
        public typealias ChildSlot = __TreeNChildSlot<n>

        /// Specifies where to insert a new node.
        public typealias InsertPosition = __TreeNInsertPosition<n>

        /// Typed node count.
        public typealias Count = Index<Node>.Count

        // MARK: - Node

        /// A node in the arena-based n-ary tree.
        @frozen
        public struct Node: ~Copyable {
            /// The element stored in this node.
            public var element: Element
            /// Child indices (nil for empty slots). Uses sparse representation per [TREE-003].
            public var childIndices: InlineArray<n, Index<Node>?>
            /// Number of occupied child slots.
            public var childCount: Count
            /// Index of parent (nil for root).
            public var parentIndex: Index<Node>?

            @inlinable
            public init(element: consuming Element, parentIndex: Index<Node>? = nil) {
                self.element = element
                self.childIndices = InlineArray(repeating: nil)
                self.childCount = .zero
                self.parentIndex = parentIndex
            }
        }

        // MARK: - Storage

        @usableFromInline
        var _arena: Buffer<Node>.Arena

        /// Index of root node (nil if empty).
        @usableFromInline
        var _rootIndex: Index<Node>?

        // MARK: - Helpers

        /// Converts a Position's typed index to a typed arena slot index.
        /// Boundary overload per [IMPL-010]: re-tags Position → Node domain.
        @inlinable
        func _slot(_ index: Index<Tree.Position>) -> Index<Node> {
            index.retag(Node.self)
        }

        // MARK: - Initialization

        /// Creates an empty n-ary tree.
        @inlinable
        public init() {
            self._arena = Buffer<Node>.Arena(minimumCapacity: .one)
            self._rootIndex = nil
        }

        /// Creates an empty n-ary tree with reserved capacity.
        ///
        /// - Parameter minimumCapacity: The minimum number of nodes to reserve space for.
        @inlinable
        public init(minimumCapacity: Count) {
            self._arena = Buffer<Node>.Arena(minimumCapacity: minimumCapacity)
            self._rootIndex = nil
        }

        // MARK: - Properties

        /// The number of nodes in the tree.
        @inlinable
        public var count: Count { _arena.occupied }

        /// Whether the tree is empty.
        @inlinable
        public var isEmpty: Bool { _arena.isEmpty }

        /// The maximum arity (number of children per node).
        @inlinable
        public static var arity: Int { n }

        /// The position of the root node, or `nil` if the tree is empty.
        @inlinable
        public var root: Tree.Position? {
            guard let rootIndex = _rootIndex else { return nil }
            let token = _arena.token(at: rootIndex)
            return Tree.Position(index: rootIndex, token: token)
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
            let arenaPos = Buffer<Node>.Arena.Position(
                index: UInt32(Int(bitPattern: position.index)), token: position.token
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
        guard let child = unsafe nodePtr.pointee.childIndices[slot.index] else { return nil }
        let token = _arena.token(at: child)
        return Tree.Position(index: child, token: token)
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
        guard let parentIndex = unsafe _arena.pointer(at: _slot(position.index)).pointee.parentIndex else {
            return nil
        }
        let token = _arena.token(at: parentIndex)
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
        return unsafe _arena.pointer(at: _slot(position.index)).pointee.childCount == .zero
    }

    /// Returns the number of children of the node at the given position.
    ///
    /// - Parameter position: The position to check.
    /// - Returns: The number of occupied child slots, or `nil` if position is invalid.
    @inlinable
    public func childCount(of position: Tree.Position) -> Count? {
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
            if let child = unsafe nodePtr.pointee.childIndices[slot] {
                let token = _arena.token(at: child)
                return Tree.Position(index: child, token: token)
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
            if let child = unsafe nodePtr.pointee.childIndices[slot] {
                let token = _arena.token(at: child)
                return Tree.Position(index: child, token: token)
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
            guard _rootIndex == nil else {
                throw .slotOccupied
            }
            let arenaPos = _arena.insert(Node(element: element))
            _rootIndex = arenaPos.slot
            return Tree.Position(index: arenaPos.slot, token: arenaPos.token)

        case .child(of: let parent, slot: let slot):
            // Validate parent position (token check)
            try _validate(parent)
            // Check child slot is empty (pointer valid before insert)
            do {
                let parentPtr = unsafe _arena.pointer(at: _slot(parent.index))
                guard unsafe parentPtr.pointee.childIndices[slot.index] == nil else {
                    throw .slotOccupied
                }
            }
            // Insert (may grow, invalidating previous pointers)
            let arenaPos = _arena.insert(
                Node(element: element, parentIndex: _slot(parent.index))
            )
            // Get fresh pointer after possible growth
            let parentPtr = unsafe _arena.pointer(at: _slot(parent.index))
            unsafe (parentPtr.pointee.childIndices[slot.index] = arenaPos.slot)
            unsafe (parentPtr.pointee.childCount += .one)
            return Tree.Position(index: arenaPos.slot, token: arenaPos.token)
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
        guard unsafe nodePtr.pointee.childCount == .zero else {
            throw .cannotRemoveNonLeaf
        }

        // Update parent's child pointer
        if let parentIndex = unsafe nodePtr.pointee.parentIndex {
            let parentPtr = unsafe _arena.pointer(at: parentIndex)
            // Find which slot this child occupies
            for slot in 0..<n {
                if unsafe parentPtr.pointee.childIndices[slot] == _slot(position.index) {
                    unsafe (parentPtr.pointee.childIndices[slot] = nil)
                    unsafe (parentPtr.pointee.childCount = parentPtr.pointee.childCount.subtract.saturating(.one))
                    break
                }
            }
        } else {
            // This is the root
            _rootIndex = nil
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
        if let parentIndex = unsafe _arena.pointer(at: _slot(position.index)).pointee.parentIndex {
            let parentPtr = unsafe _arena.pointer(at: parentIndex)
            // Find which slot this child occupies
            for slot in 0..<n {
                if unsafe parentPtr.pointee.childIndices[slot] == _slot(position.index) {
                    unsafe (parentPtr.pointee.childIndices[slot] = nil)
                    unsafe (parentPtr.pointee.childCount = parentPtr.pointee.childCount.subtract.saturating(.one))
                    break
                }
            }
        } else {
            // This is the root
            _rootIndex = nil
        }

        // Iterative post-order removal using explicit stack
        var pending = Stack<Index<Node>>()
        var lastVisited: Index<Node>? = nil

        pending.push(_slot(position.index))

        while !pending.isEmpty {
            let current = pending.peek()!
            let nodePtr = unsafe _arena.pointer(at: current)
            let childIndices = unsafe nodePtr.pointee.childIndices

            // Find rightmost existing child
            var rightmostChild: Index<Node>? = nil
            for slot in stride(from: n - 1, through: 0, by: -1) {
                if let child = childIndices[slot] {
                    rightmostChild = child
                    break
                }
            }

            // Find leftmost existing child
            var leftmostChild: Index<Node>? = nil
            for slot in 0..<n {
                if let child = childIndices[slot] {
                    leftmostChild = child
                    break
                }
            }

            // Process current if:
            // 1. It's a leaf (no children), OR
            // 2. We came from the rightmost child, OR
            // 3. We came from leftmost child AND no other children exist
            let isLeaf = rightmostChild == nil
            let cameFromRightmost = rightmostChild != nil && rightmostChild == lastVisited
            let cameFromLeftmostNoOther = leftmostChild != nil && leftmostChild == lastVisited && leftmostChild == rightmostChild

            if isLeaf || cameFromRightmost || cameFromLeftmostNoOther {
                _ = pending.pop()
                _arena.free(at: current)
                lastVisited = current
            } else {
                // Push children in reverse order (rightmost first so leftmost is processed first)
                for slot in stride(from: n - 1, through: 0, by: -1) {
                    if let child = childIndices[slot] {
                        pending.push(child)
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
        _rootIndex = nil
    }

    /// Computes the height of the tree.
    ///
    /// The height is the length of the longest path from the root to a leaf.
    /// An empty tree returns `nil`, a single-node tree has height `.zero`.
    ///
    /// Uses iterative traversal to avoid stack overflow on deep trees.
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

extension Tree.N where Element: ~Copyable {

    /// Iterates over all elements in pre-order using a borrowing closure.
    ///
    /// Uses iterative traversal to avoid stack overflow on deep trees.
    /// - Parameter body: A closure called with each element in pre-order.
    @inlinable
    public func forEachPreOrder(_ body: (borrowing Element) -> Void) {
        guard let rootIndex = _rootIndex else { return }
        var pending = Stack<Index<Node>>()
        pending.push(rootIndex)

        while !pending.isEmpty {
            let index = pending.pop()!
            let nodePtr = unsafe _arena.pointer(at: index)
            unsafe body(nodePtr.pointee.element)

            // Push children in reverse order so first child is processed first
            for slot in stride(from: n - 1, through: 0, by: -1) {
                if let child = unsafe nodePtr.pointee.childIndices[slot] {
                    pending.push(child)
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
        guard let rootIndex = _rootIndex else { return }
        var pending = Stack<Index<Node>>()
        var lastVisited: Index<Node>? = nil
        pending.push(rootIndex)

        while !pending.isEmpty {
            let current = pending.peek()!
            let nodePtr = unsafe _arena.pointer(at: current)
            let childIndices = unsafe nodePtr.pointee.childIndices

            // Find rightmost existing child
            var rightmostChild: Index<Node>? = nil
            for slot in stride(from: n - 1, through: 0, by: -1) {
                if let child = childIndices[slot] {
                    rightmostChild = child
                    break
                }
            }

            // Find leftmost existing child
            var leftmostChild: Index<Node>? = nil
            for slot in 0..<n {
                if let child = childIndices[slot] {
                    leftmostChild = child
                    break
                }
            }

            // Process current if:
            // 1. It's a leaf (no children), OR
            // 2. We came from the rightmost child, OR
            // 3. We came from leftmost child AND no other children exist
            let isLeaf = rightmostChild == nil
            let cameFromRightmost = rightmostChild != nil && rightmostChild == lastVisited
            let cameFromLeftmostNoOther = leftmostChild != nil && leftmostChild == lastVisited && leftmostChild == rightmostChild

            if isLeaf || cameFromRightmost || cameFromLeftmostNoOther {
                _ = pending.pop()
                unsafe body(nodePtr.pointee.element)
                lastVisited = current
            } else {
                // Push children in reverse order (rightmost first so leftmost is processed first)
                for slot in stride(from: n - 1, through: 0, by: -1) {
                    if let child = childIndices[slot] {
                        pending.push(child)
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
        guard let rootIndex = _rootIndex else { return }
        var pending = Stack<Index<Node>>()
        var current: Index<Node>? = rootIndex

        while current != nil || !pending.isEmpty {
            // Go to leftmost node
            while let c = current {
                pending.push(c)
                current = unsafe _arena.pointer(at: c).pointee.childIndices[0]
            }

            // Process node
            let c = pending.pop()!
            let nodePtr = unsafe _arena.pointer(at: c)
            unsafe body(nodePtr.pointee.element)

            // Move to right subtree
            current = unsafe nodePtr.pointee.childIndices[1]
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
            guard _rootIndex == nil else {
                throw .slotOccupied
            }
            let arenaPos = _arena.insert(Node(element: element))
            _rootIndex = arenaPos.slot
            return Tree.Position(index: arenaPos.slot, token: arenaPos.token)

        case .child(of: let parent, slot: let slot):
            // Validate parent position (token check)
            try _validate(parent)
            // Check child slot is empty (pointer valid before insert)
            do {
                let parentPtr = unsafe _arena.pointer(at: _slot(parent.index))
                guard unsafe parentPtr.pointee.childIndices[slot.index] == nil else {
                    throw .slotOccupied
                }
            }
            // Insert (may grow, invalidating previous pointers)
            let arenaPos = _arena.insert(
                Node(element: element, parentIndex: _slot(parent.index))
            )
            // Get fresh pointer after possible growth
            let parentPtr = unsafe _arena.pointer(at: _slot(parent.index))
            unsafe (parentPtr.pointee.childIndices[slot.index] = arenaPos.slot)
            unsafe (parentPtr.pointee.childCount += .one)
            return Tree.Position(index: arenaPos.slot, token: arenaPos.token)
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

extension Tree.N: @unsafe @unchecked Sendable where Element: Sendable {}
