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

/// A dynamically-growing tree with unbounded arity (dynamic children per node).
///
/// `Tree.Unbounded` is the general-purpose tree primitive for arbitrary tree structures.
/// Each node can have any number of children, stored in a dynamic array. It provides O(1)
/// node insertion and O(1) navigation with automatic capacity growth.
///
/// ## Example
///
/// ```swift
/// var tree = Tree.Unbounded<String>()
/// let root = try tree.insert("root", at: .root)
/// let child1 = try tree.insert("child1", at: .appendChild(of: root))
/// let child2 = try tree.insert("child2", at: .appendChild(of: root))
/// let grandchild = try tree.insert("grandchild", at: .appendChild(of: child1))
///
/// tree.forEachPreOrder { element in
///     print(element)  // root, child1, grandchild, child2
/// }
/// ```
///
/// ## Dynamic Children
///
/// Unlike bounded-arity trees (`Tree.N<n>`), unbounded trees allow:
/// - Any number of children per node
/// - Insertion at specific indices or appending
/// - No compile-time arity constraint
///
/// ## Variants
///
/// - ``Unbounded``: Dynamically-growing with amortized O(1) insert (this type)
/// - ``Unbounded/Bounded``: Fixed node capacity with upfront allocation
/// - ``Unbounded/Small``: Inline node storage with per-node small-vector children
///
/// Note: There is no `.Inline` variant for unbounded trees per [TREE-001].
///
/// ## Move-Only Support
///
/// Both the tree and its elements can be `~Copyable`:
///
/// ```swift
/// struct FileHandle: ~Copyable { ... }
/// var handles = Tree.Unbounded<FileHandle>()
/// let root = try handles.insert(FileHandle(), at: .root)
/// ```
///
/// ## Copy-on-Write
///
/// When `Element` is `Copyable`, `Tree.Unbounded` uses copy-on-write semantics:
/// copies share storage until mutation, providing efficient value semantics.
///
/// ## Arena-Based Storage
///
/// Uses `Buffer<Node>.Arena` for storage — all nodes are stored contiguously
/// with generation-token validation, LIFO free-list recycling, and automatic
/// growth. Nodes reference each other by index rather than pointer.
extension Tree where Element: ~Copyable {

    @safe
    public struct Unbounded: ~Copyable {

        // MARK: - Typealiases

        /// Errors that can occur during unbounded tree operations.
        public typealias Error = __TreeUnboundedError

        /// Specifies where to insert a new node.
        public typealias InsertPosition = __TreeUnboundedInsertPosition

        /// Typed node count.
        public typealias Count = Index<Node>.Count

        // MARK: - Node

        /// A node in the arena-based unbounded tree.
        public struct Node: ~Copyable {
            /// The element stored in this node.
            @usableFromInline var element: Element
            /// Child indices (dynamic array, heap-allocated).
            ///
            // WORKAROUND: Swift.Array used for per-node dynamic child storage.
            // WHY: Array<Int> (ecosystem) uses typed Index<Int>/Count, and
            //   lacks Swift.Array APIs used here (firstIndex(of:), insert(_:at:),
            //   remove(at:) with bare Int). Replacement requires API parity or
            //   call-site rewrite to typed indices.
            // WHEN TO REMOVE: When Array exposes stdlib-compatible mutation APIs,
            //   or when childIndices migrates to typed Index<Node>.
            // TRACKING: Phase 5 / F-04 in tree-primitives remediation plan.
            @usableFromInline var childIndices: Swift.Array<Int>
            /// Index of parent (nil for root).
            @usableFromInline var parentIndex: Index<Node>?

            @usableFromInline
            init(element: consuming Element, parentIndex: Index<Node>? = nil) {
                self.element = element
                self.childIndices = []
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

        /// Converts a raw Int index to a typed slot index.
        /// Used internally where childIndices (Array<Int>) provides bare Ints.
        @inlinable
        func _slot(_ index: Int) -> Index<Node> {
            Index<Node>(Ordinal(UInt(index)))
        }

        /// Converts a Position's typed index to a typed arena slot index.
        @inlinable
        func _slot(_ index: Index<Tree.Position>) -> Index<Node> {
            index.retag(Node.self)
        }

        /// Converts a typed index to a raw Int for the bare-Int traversal domain.
        @inlinable
        func _rawIndex(_ index: Index<Node>) -> Int {
            Int(bitPattern: index)
        }

        // MARK: - Initialization

        /// Creates an empty unbounded tree.
        @inlinable
        public init() {
            self._arena = Buffer<Node>.Arena(minimumCapacity: .one)
            self._rootIndex = nil
        }

        /// Creates an empty unbounded tree with reserved capacity.
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
        func _validate(_ position: Tree.Position) throws(__TreeUnboundedError) {
            let arenaPos = Buffer<Node>.Arena.Position(
                index: UInt32(Int(bitPattern: position.index)), token: position.token
            )
            guard _arena.isValid(arenaPos) else { throw .invalidPosition }
        }
    }
}

// MARK: - Navigation

extension Tree.Unbounded where Element: ~Copyable {

    /// Returns the position of the child at the given index.
    ///
    /// - Parameters:
    ///   - position: The position of the parent node.
    ///   - index: The child index (0..<childCount).
    /// - Returns: The position of the child, or `nil` if the index is out of bounds.
    /// - Note: Returns `nil` if the position is invalid (stale or out of bounds).
    @inlinable
    public func child(of position: Tree.Position, at index: Int) -> Tree.Position? {
        do {
            try _validate(position)
        } catch {
            return nil
        }
        let childIndices = unsafe _arena.pointer(at: _slot(position.index)).pointee.childIndices
        guard index >= 0, index < childIndices.count else { return nil }
        let childIndex = childIndices[index]
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
        return unsafe _arena.pointer(at: _slot(position.index)).pointee.childIndices.isEmpty
    }

    /// Returns the number of children of the node at the given position.
    ///
    /// - Parameter position: The position to check.
    /// - Returns: The number of children, or `nil` if position is invalid.
    @inlinable
    public func childCount(of position: Tree.Position) -> Int? {
        do {
            try _validate(position)
        } catch {
            return nil
        }
        return unsafe _arena.pointer(at: _slot(position.index)).pointee.childIndices.count
    }

    /// Returns the position of the first child.
    ///
    /// - Parameter position: The position of the parent node.
    /// - Returns: The position of the first child, or `nil` if no children exist.
    @inlinable
    public func firstChild(of position: Tree.Position) -> Tree.Position? {
        child(of: position, at: 0)
    }

    /// Returns the position of the last child.
    ///
    /// - Parameter position: The position of the parent node.
    /// - Returns: The position of the last child, or `nil` if no children exist.
    @inlinable
    public func lastChild(of position: Tree.Position) -> Tree.Position? {
        do {
            try _validate(position)
        } catch {
            return nil
        }
        let childIndices = unsafe _arena.pointer(at: _slot(position.index)).pointee.childIndices
        guard !childIndices.isEmpty else { return nil }
        let childIndex = childIndices[childIndices.count - 1]
        let token = _arena.token(at: _slot(childIndex))
        return Tree.Position(index: childIndex, token: token)
    }
}

// MARK: - Insert Operations (~Copyable)

extension Tree.Unbounded where Element: ~Copyable {

    /// Inserts an element at the specified position.
    ///
    /// - Parameters:
    ///   - element: The element to insert.
    ///   - position: Where to insert the element.
    /// - Returns: The position of the newly inserted node (with token for validation).
    /// - Throws: ``Error/rootOccupied`` if inserting at root when it exists,
    ///           ``Error/invalidPosition`` if the parent position is invalid or stale,
    ///           ``Error/childIndexOutOfBounds`` if the child index exceeds childCount.
    @inlinable
    @discardableResult
    public mutating func insert(
        _ element: consuming Element,
        at position: InsertPosition
    ) throws(__TreeUnboundedError) -> Tree.Position {
        switch position {
        case .root:
            guard _rootIndex == nil else {
                throw .rootOccupied
            }
            let arenaPos = _arena.insert(Node(element: element))
            _rootIndex = arenaPos.slot
            return Tree.Position(index: arenaPos.slot, token: arenaPos.token)

        case .child(of: let parent, at: let childIndex):
            // Validate parent position (token check)
            try _validate(parent)
            let currentChildCount = unsafe _arena.pointer(at: _slot(parent.index)).pointee.childIndices.count
            guard childIndex >= 0, childIndex <= currentChildCount else {
                throw .childIndexOutOfBounds
            }
            let arenaPos = _arena.insert(
                Node(element: element, parentIndex: _slot(parent.index))
            )
            let index = _rawIndex(arenaPos.slot)
            // Get fresh pointer after possible growth
            let parentPtr = unsafe _arena.pointer(at: _slot(parent.index))
            unsafe (parentPtr.pointee.childIndices.insert(index, at: childIndex))
            return Tree.Position(index: index, token: arenaPos.token)

        case .appendChild(of: let parent):
            // Validate parent position (token check)
            try _validate(parent)
            let arenaPos = _arena.insert(
                Node(element: element, parentIndex: _slot(parent.index))
            )
            let index = _rawIndex(arenaPos.slot)
            // Get fresh pointer after possible growth
            let parentPtr = unsafe _arena.pointer(at: _slot(parent.index))
            unsafe (parentPtr.pointee.childIndices.append(index))
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
    public mutating func remove(at position: Tree.Position) throws(__TreeUnboundedError) -> Element {
        // Validate position (token check)
        try _validate(position)

        guard unsafe _arena.pointer(at: _slot(position.index)).pointee.childIndices.isEmpty else {
            throw .cannotRemoveNonLeaf
        }

        // Update parent's child array
        if let parentIndex = unsafe _arena.pointer(at: _slot(position.index)).pointee.parentIndex {
            let parentPtr = unsafe _arena.pointer(at: parentIndex)
            if let childSlot = unsafe parentPtr.pointee.childIndices.firstIndex(of: Int(bitPattern: position.index)) {
                unsafe (parentPtr.pointee.childIndices.remove(at: childSlot))
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
    public mutating func removeSubtree(at position: Tree.Position) throws(__TreeUnboundedError) {
        // Validate position (token check)
        try _validate(position)

        // Update parent's child array
        if let parentIndex = unsafe _arena.pointer(at: _slot(position.index)).pointee.parentIndex {
            let parentPtr = unsafe _arena.pointer(at: parentIndex)
            if let childSlot = unsafe parentPtr.pointee.childIndices.firstIndex(of: Int(bitPattern: position.index)) {
                unsafe (parentPtr.pointee.childIndices.remove(at: childSlot))
            }
        } else {
            // This is the root
            _rootIndex = nil
        }

        // Iterative post-order removal using explicit stack
        var pending = Stack<Int>()
        var lastVisited: Int = -1

        pending.push(Int(bitPattern: position.index))

        while !pending.isEmpty {
            let current = pending.peek()!
            let childIndices = unsafe _arena.pointer(at: _slot(current)).pointee.childIndices

            // Find rightmost unvisited child
            var hasUnvisitedChild = false
            for slot in stride(from: childIndices.count - 1, through: 0, by: -1) {
                let childIndex = childIndices[slot]
                if childIndex != lastVisited {
                    // Check if we've already processed any later children
                    var laterChildVisited = false
                    for laterSlot in (slot + 1)..<childIndices.count {
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
                _arena.free(at: _slot(current))
                lastVisited = current
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

        var maxHeight = 0
        var pending = Stack<(index: Int, depth: Int)>()
        pending.push((_rawIndex(rootIndex), 0))

        while !pending.isEmpty {
            let (index, depth) = pending.pop()!
            maxHeight = Swift.max(maxHeight, depth)

            let childIndices = unsafe _arena.pointer(at: _slot(index)).pointee.childIndices
            for childIndex in childIndices {
                pending.push((childIndex, depth + 1))
            }
        }

        return Count(Cardinal(UInt(maxHeight)))
    }
}

// MARK: - Traversal

extension Tree.Unbounded where Element: ~Copyable {

    /// Iterates over all elements in pre-order using a borrowing closure.
    ///
    /// Uses iterative traversal to avoid stack overflow on deep trees.
    /// - Parameter body: A closure called with each element in pre-order.
    @inlinable
    public func forEachPreOrder(_ body: (borrowing Element) -> Void) {
        guard let rootIndex = _rootIndex else { return }
        var pending = Stack<Int>()
        pending.push(_rawIndex(rootIndex))

        while !pending.isEmpty {
            let index = pending.pop()!
            let nodePtr = unsafe _arena.pointer(at: _slot(index))
            unsafe body(nodePtr.pointee.element)

            // Push children in reverse order so first child is processed first
            let childIndices = unsafe nodePtr.pointee.childIndices
            for i in stride(from: childIndices.count - 1, through: 0, by: -1) {
                pending.push(childIndices[i])
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
        var pending = Stack<Int>()
        var lastVisited: Int = -1
        pending.push(_rawIndex(rootIndex))

        while !pending.isEmpty {
            let current = pending.peek()!
            let nodePtr = unsafe _arena.pointer(at: _slot(current))
            let childIndices = unsafe nodePtr.pointee.childIndices

            // Find rightmost unvisited child
            var hasUnvisitedChild = false
            for slot in stride(from: childIndices.count - 1, through: 0, by: -1) {
                let childIndex = childIndices[slot]
                if childIndex != lastVisited {
                    // Check if we've already processed any later children
                    var laterChildVisited = false
                    for laterSlot in (slot + 1)..<childIndices.count {
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
                unsafe body(nodePtr.pointee.element)
                lastVisited = current
            }
        }
    }

    /// Iterates over all elements in level-order (breadth-first) using a borrowing closure.
    ///
    /// - Parameter body: A closure called with each element in level-order.
    @inlinable
    public func forEachLevelOrder(_ body: (borrowing Element) -> Void) {
        guard let rootIndex = _rootIndex else { return }

        var pending = Queue<Int>()
        pending.enqueue(_rawIndex(rootIndex))

        while !pending.isEmpty {
            let index = pending.dequeue()!
            let nodePtr = unsafe _arena.pointer(at: _slot(index))

            unsafe body(nodePtr.pointee.element)

            let childIndices = unsafe nodePtr.pointee.childIndices
            for childIndex in childIndices {
                pending.enqueue(childIndex)
            }
        }
    }
}

// MARK: - Copyable Element Extensions

extension Tree.Unbounded where Element: Copyable {

    /// Makes the storage unique, copying if necessary for copy-on-write.
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
    ) throws(__TreeUnboundedError) -> Tree.Position {
        makeUnique()

        switch position {
        case .root:
            guard _rootIndex == nil else {
                throw .rootOccupied
            }
            let arenaPos = _arena.insert(Node(element: element))
            _rootIndex = arenaPos.slot
            return Tree.Position(index: arenaPos.slot, token: arenaPos.token)

        case .child(of: let parent, at: let childIndex):
            // Validate parent position (token check)
            try _validate(parent)
            let currentChildCount = unsafe _arena.pointer(at: _slot(parent.index)).pointee.childIndices.count
            guard childIndex >= 0, childIndex <= currentChildCount else {
                throw .childIndexOutOfBounds
            }
            let arenaPos = _arena.insert(
                Node(element: element, parentIndex: _slot(parent.index))
            )
            let index = _rawIndex(arenaPos.slot)
            // Get fresh pointer after possible growth
            let parentPtr = unsafe _arena.pointer(at: _slot(parent.index))
            unsafe (parentPtr.pointee.childIndices.insert(index, at: childIndex))
            return Tree.Position(index: index, token: arenaPos.token)

        case .appendChild(of: let parent):
            // Validate parent position (token check)
            try _validate(parent)
            let arenaPos = _arena.insert(
                Node(element: element, parentIndex: _slot(parent.index))
            )
            let index = _rawIndex(arenaPos.slot)
            // Get fresh pointer after possible growth
            let parentPtr = unsafe _arena.pointer(at: _slot(parent.index))
            unsafe (parentPtr.pointee.childIndices.append(index))
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

extension Tree.Unbounded.Node: Copyable where Element: Copyable {}
extension Tree.Unbounded: Copyable where Element: Copyable {}

// MARK: - Sendable

extension Tree.Unbounded: @unchecked Sendable where Element: Sendable {}
