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
public import Dictionary_Primitives

/// A dynamically-growing keyed tree with dictionary-indexed children.
///
/// `Tree.Keyed<Key, Value>` is the general-purpose keyed tree primitive. Each node
/// stores a value and a set of children indexed by unique keys. It provides O(1)
/// child lookup by key, O(1) parent navigation, and O(d) key-path reconstruction.
///
/// ## Example
///
/// ```swift
/// var tree = Tree.Keyed<String, Int>()
/// let root = try tree.insert(0, at: .root)
/// let child = try tree.insert(1, at: .child(of: root, key: "left"))
/// let grandchild = try tree.insert(2, at: .child(of: child, key: "inner"))
///
/// tree.forEachPreOrder { value in
///     print(value)  // 0, 1, 2
/// }
/// ```
///
/// ## Arena-Based Storage
///
/// Uses `Buffer<Node>.Arena` for storage — all nodes are stored contiguously
/// with generation-token validation, LIFO free-list recycling, and automatic
/// growth. Nodes reference each other by index rather than pointer.
///
/// ## Dictionary-Indexed Children
///
/// Each node's children are stored in a `Dictionary<Key, Index<Node>>.Ordered`,
/// providing O(1) keyed lookup and ordered iteration in insertion order.
///
/// ## Move-Only Support
///
/// Both the tree and its values can be `~Copyable`:
///
/// ```swift
/// struct FileHandle: ~Copyable { ... }
/// var handles = Tree.Keyed<String, FileHandle>()
/// let root = try handles.insert(FileHandle(), at: .root)
/// ```
///
/// ## Copy-on-Write
///
/// When `Value` is `Copyable`, `Tree.Keyed` uses copy-on-write semantics:
/// copies share storage until mutation, providing efficient value semantics.
extension Tree where Element: ~Copyable {

    @safe
    public struct Keyed<Key: Hash.`Protocol`>: ~Copyable {

        /// The value stored at each node. Equivalent to the tree's `Element` type.
        public typealias Value = Element

        // MARK: - Typealiases

        /// Errors that can occur during keyed tree operations.
        public typealias Error = __TreeKeyedError<Key>

        /// Specifies where to insert a new node.
        public typealias InsertPosition = __TreeKeyedInsertPosition<Key>

        /// Typed node count.
        public typealias Count = Index<Node>.Count

        // MARK: - Node

        /// A node in the arena-based keyed tree.
        @frozen
        public struct Node: ~Copyable {
            /// The value stored in this node.
            public var value: Value
            /// Children indexed by key. Uses `Dictionary.Ordered` for O(1) lookup
            /// with insertion-order iteration.
            public var _children: Dictionary_Primitives.Dictionary<Key, Index<Node>>.Ordered
            /// Index of parent (nil for root).
            public var parentIndex: Index<Node>?
            /// Key under which this node is stored in its parent's children (nil for root).
            public var parentKey: Key?

            @inlinable
            public init(
                value: consuming Value,
                parentIndex: Index<Node>? = nil,
                parentKey: Key? = nil
            ) {
                self.value = value
                self._children = Dictionary_Primitives.Dictionary<Key, Index<Node>>.Ordered()
                self.parentIndex = parentIndex
                self.parentKey = parentKey
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

        /// Creates an empty keyed tree.
        @inlinable
        public init() {
            self._arena = Buffer<Node>.Arena(minimumCapacity: .one)
            self._rootIndex = nil
        }

        /// Creates a tree with a single root node.
        ///
        /// - Parameter rootValue: The value for the root node.
        @inlinable
        public init(rootValue: consuming Value) {
            self._arena = Buffer<Node>.Arena(minimumCapacity: .one)
            let arenaPos = _arena.insert(Node(value: rootValue))
            self._rootIndex = arenaPos.slot
        }

        /// Creates an empty keyed tree with reserved capacity.
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
        func _validate(_ position: Tree.Position) throws(__TreeKeyedError<Key>) {
            let arenaPos = Buffer<Node>.Arena.Position(
                index: UInt32(Int(bitPattern: position.index)), token: position.token
            )
            guard _arena.isValid(arenaPos) else { throw .invalidPosition }
        }
    }
}

// MARK: - Insert Operations (~Copyable)

extension Tree.Keyed where Element: ~Copyable {

    /// Inserts a value at the specified position.
    ///
    /// - Parameters:
    ///   - value: The value to insert.
    ///   - position: Where to insert the value.
    /// - Returns: The position of the newly inserted node (with token for validation).
    /// - Throws: ``Error/rootOccupied`` if inserting at root when it exists,
    ///           ``Error/invalidPosition`` if the parent position is invalid or stale,
    ///           ``Error/keyOccupied(_:)`` if the child key already exists at the parent.
    @inlinable
    @discardableResult
    public mutating func insert(
        _ value: consuming Value,
        at position: InsertPosition
    ) throws(__TreeKeyedError<Key>) -> Tree.Position {
        switch position {
        case .root:
            guard _rootIndex == nil else {
                throw .rootOccupied
            }
            let arenaPos = _arena.insert(Node(value: value))
            _rootIndex = arenaPos.slot
            return Tree.Position(index: arenaPos.slot, token: arenaPos.token)

        case .child(of: let parent, key: let key):
            try _validate(parent)
            // Check child key is not already occupied
            let occupied = unsafe _arena.pointer(at: _slot(parent.index)).pointee._children.contains(key)
            guard !occupied else {
                throw .keyOccupied(key)
            }
            // Insert (may grow, invalidating previous pointers)
            let arenaPos = _arena.insert(
                Node(value: value, parentIndex: _slot(parent.index), parentKey: key)
            )
            // Get fresh pointer after possible growth
            let parentPtr = unsafe _arena.pointer(at: _slot(parent.index))
            unsafe (parentPtr.pointee._children.set(key, arenaPos.slot))
            return Tree.Position(index: arenaPos.slot, token: arenaPos.token)
        }
    }

    /// Removes the leaf node at the specified position.
    ///
    /// - Parameter position: The position of the node to remove. Must be a leaf.
    /// - Returns: The value that was stored at the position.
    /// - Throws: ``Error/invalidPosition`` if the position is invalid or stale,
    ///           ``Error/cannotRemoveNonLeaf`` if the node has children.
    @inlinable
    @discardableResult
    public mutating func remove(at position: Tree.Position) throws(__TreeKeyedError<Key>) -> Value {
        try _validate(position)

        let nodePtr = unsafe _arena.pointer(at: _slot(position.index))
        guard unsafe nodePtr.pointee._children.isEmpty else {
            throw .cannotRemoveNonLeaf
        }

        // Update parent's child dictionary
        if let parentIndex = unsafe nodePtr.pointee.parentIndex,
           let parentKey = unsafe nodePtr.pointee.parentKey {
            let parentPtr = unsafe _arena.pointer(at: parentIndex)
            unsafe (parentPtr.pointee._children.remove(parentKey))
        } else {
            _rootIndex = nil
        }

        let node = _arena.remove(at: _slot(position.index))
        return node.value
    }

    /// Removes the subtree rooted at the specified position.
    ///
    /// All nodes in the subtree are removed and their values are deinitialized
    /// in post-order (children before parents).
    ///
    /// - Parameter position: The position of the root of the subtree to remove.
    /// - Throws: ``Error/invalidPosition`` if the position is invalid or stale.
    @inlinable
    public mutating func removeSubtree(at position: Tree.Position) throws(__TreeKeyedError<Key>) {
        try _validate(position)

        // Update parent's child dictionary
        let nodePtr = unsafe _arena.pointer(at: _slot(position.index))
        if let parentIndex = unsafe nodePtr.pointee.parentIndex,
           let parentKey = unsafe nodePtr.pointee.parentKey {
            let parentPtr = unsafe _arena.pointer(at: parentIndex)
            unsafe (parentPtr.pointee._children.remove(parentKey))
        } else {
            _rootIndex = nil
        }

        // Iterative post-order removal using explicit stack
        var pending = Stack<Index<Node>>()
        var visited = Stack<Index<Node>>()

        pending.push(_slot(position.index))

        // Phase 1: Build reverse-post-order via pre-order push
        while !pending.isEmpty {
            let current = pending.pop()!
            visited.push(current)

            let currentPtr = unsafe _arena.pointer(at: current)
            unsafe currentPtr.pointee._children.forEach { _, childIndex in
                pending.push(childIndex)
            }
        }

        // Phase 2: Free in post-order (reverse of pre-order)
        while !visited.isEmpty {
            let index = visited.pop()!
            _arena.free(at: index)
        }
    }

    /// Accesses the value at the specified position via a borrowing closure.
    ///
    /// - Parameters:
    ///   - position: The position of the node.
    ///   - body: A closure that receives a borrowing reference to the value.
    /// - Returns: The value returned by `body`, or `nil` if the position is invalid or stale.
    @inlinable
    public func peek<R>(at position: Tree.Position, _ body: (borrowing Value) -> R) -> R? {
        do {
            try _validate(position)
        } catch {
            return nil
        }
        return unsafe body(_arena.pointer(at: _slot(position.index)).pointee.value)
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
            unsafe nodePtr.pointee._children.forEach { _, childIndex in
                pending.push((childIndex, depth + .one))
            }
        }

        return maxHeight
    }
}

// MARK: - Copyable Value Extensions

extension Tree.Keyed where Element: Copyable {

    /// Ensures unique storage, copying if necessary for copy-on-write.
    @usableFromInline
    mutating func makeUnique() {
        _arena.ensureUnique()
    }

    /// The root node's value, or nil if the tree is empty.
    ///
    /// Setting to a non-nil value updates the root (or creates it if empty).
    /// Setting to nil is a no-op — the setter exists for optional chaining
    /// writeback (e.g. `tree.rootValue?.field = x`). To set a sparse tree's
    /// root value to `Optional.none`, use the sparse subscript:
    /// `tree[[] as [Key]] = nil`.
    @inlinable
    public var rootValue: Value? {
        get {
            guard let rootIndex = _rootIndex else { return nil }
            return unsafe _arena.pointer(at: rootIndex).pointee.value
        }
        set {
            guard let newValue else { return }
            makeUnique()
            if let rootIndex = _rootIndex {
                let nodePtr = unsafe _arena.pointer(at: rootIndex)
                unsafe (nodePtr.pointee.value = newValue)
            } else {
                let arenaPos = _arena.insert(Node(value: newValue))
                _rootIndex = arenaPos.slot
            }
        }
    }

    /// Inserts a value at the specified position (CoW-aware).
    @inlinable
    @discardableResult
    public mutating func insert(
        _ value: Value,
        at position: InsertPosition
    ) throws(__TreeKeyedError<Key>) -> Tree.Position {
        makeUnique()

        switch position {
        case .root:
            guard _rootIndex == nil else {
                throw .rootOccupied
            }
            let arenaPos = _arena.insert(Node(value: value))
            _rootIndex = arenaPos.slot
            return Tree.Position(index: arenaPos.slot, token: arenaPos.token)

        case .child(of: let parent, key: let key):
            try _validate(parent)
            let occupied = unsafe _arena.pointer(at: _slot(parent.index)).pointee._children.contains(key)
            guard !occupied else {
                throw .keyOccupied(key)
            }
            let arenaPos = _arena.insert(
                Node(value: value, parentIndex: _slot(parent.index), parentKey: key)
            )
            let parentPtr = unsafe _arena.pointer(at: _slot(parent.index))
            unsafe (parentPtr.pointee._children.set(key, arenaPos.slot))
            return Tree.Position(index: arenaPos.slot, token: arenaPos.token)
        }
    }

    /// Returns the value at the specified position.
    ///
    /// - Parameter position: The position of the node.
    /// - Returns: The value at the position, or `nil` if invalid or stale.
    @inlinable
    public func peek(at position: Tree.Position) -> Value? {
        do {
            try _validate(position)
        } catch {
            return nil
        }
        return unsafe _arena.pointer(at: _slot(position.index)).pointee.value
    }

    /// Replaces the value at the specified position.
    ///
    /// - Parameters:
    ///   - position: The position of the node.
    ///   - newValue: The new value.
    /// - Throws: ``Error/invalidPosition`` if the position is invalid or stale.
    @inlinable
    public mutating func update(at position: Tree.Position, _ newValue: Value) throws(__TreeKeyedError<Key>) {
        makeUnique()
        try _validate(position)
        let nodePtr = unsafe _arena.pointer(at: _slot(position.index))
        unsafe (nodePtr.pointee.value = newValue)
    }
}

// MARK: - Conditional Copyable

extension Tree.Keyed.Node: Copyable where Element: Copyable {}
extension Tree.Keyed: Copyable where Element: Copyable {}

// MARK: - Sendable

extension Tree.Keyed: @unsafe @unchecked Sendable where Key: Sendable, Element: Sendable {}
