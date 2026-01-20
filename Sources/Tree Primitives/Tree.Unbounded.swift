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
/// Uses arena-based storage where all nodes are stored contiguously. Nodes
/// reference each other by index rather than pointer, improving cache locality.
/// Removed nodes are recycled via a free-list for efficient reuse.
extension Tree {

    @safe
    public struct Unbounded<Element: ~Copyable>: ~Copyable {

        // MARK: - Typealiases

        /// Errors that can occur during unbounded tree operations.
        public typealias Error = __TreeUnboundedError

        /// Specifies where to insert a new node.
        public typealias InsertPosition = __TreeUnboundedInsertPosition

        // MARK: - Header

        /// Header for arena-based unbounded tree storage.
        @usableFromInline
        struct Header {
            /// Index of root node (-1 if empty).
            @usableFromInline var rootIndex: Int
            /// Number of active nodes.
            @usableFromInline var count: Int
            /// Index of first free slot (-1 if none).
            @usableFromInline var freeHead: Int
            /// Total node capacity.
            @usableFromInline var capacity: Int

            @usableFromInline
            init() {
                self.rootIndex = -1
                self.count = 0
                self.freeHead = -1
                self.capacity = 0
            }
        }

        // MARK: - Node

        /// A node in the arena-based unbounded tree.
        @usableFromInline
        struct Node: ~Copyable {
            /// The element stored in this node.
            @usableFromInline var element: Element
            /// Child indices (dynamic array, heap-allocated).
            @usableFromInline var childIndices: Swift.Array<Int>
            /// Index of parent (-1 for root).
            @usableFromInline var parentIndex: Int

            @usableFromInline
            init(element: consuming Element, parentIndex: Int = -1) {
                self.element = element
                self.childIndices = []
                self.parentIndex = parentIndex
            }
        }

        // MARK: - Storage

        /// Internal storage class for arena-based unbounded tree.
        ///
        /// Uses `ManagedBuffer` for efficient single-allocation storage.
        /// Declared as a nested class so that `Element` inherits the `~Copyable`
        /// suppression from the outer type.
        ///
        /// Also owns auxiliary buffers for token validation and free-list management,
        /// ensuring they participate in the same CoW boundary as the node storage.
        @safe
        @usableFromInline
        final class Storage: ManagedBuffer<Header, Node> {

            /// Token buffer for position validation. Each slot's token alternates:
            /// even = free, odd = occupied. Incremented on allocate and free.
            @usableFromInline
            var _tokens: UnsafeMutablePointer<UInt32>?

            /// Free-list next pointers stored separately (not in freed node memory).
            /// _nextFree[i] contains the next free slot index when slot i is free.
            @usableFromInline
            var _nextFree: UnsafeMutablePointer<Int>?

            @usableFromInline
            static func create() -> Storage {
                let storage = Storage.create(minimumCapacity: 0) { _ in Header() }
                let result = unsafe unsafeDowncast(storage, to: Storage.self)
                unsafe (result._tokens = nil)
                unsafe (result._nextFree = nil)
                return result
            }

            @usableFromInline
            static func create(minimumCapacity: Int) -> Storage {
                var header = Header()
                header.capacity = minimumCapacity
                let storage = Storage.create(minimumCapacity: minimumCapacity) { _ in header }
                let result = unsafe unsafeDowncast(storage, to: Storage.self)

                if minimumCapacity > 0 {
                    // Allocate and initialize auxiliary buffers
                    let tokensPtr = UnsafeMutablePointer<UInt32>.allocate(capacity: minimumCapacity)
                    unsafe tokensPtr.initialize(repeating: 0, count: minimumCapacity)  // All start as free (even)
                    unsafe (result._tokens = tokensPtr)

                    let nextFreePtr = UnsafeMutablePointer<Int>.allocate(capacity: minimumCapacity)
                    unsafe nextFreePtr.initialize(repeating: -1, count: minimumCapacity)
                    unsafe (result._nextFree = nextFreePtr)
                } else {
                    unsafe (result._tokens = nil)
                    unsafe (result._nextFree = nil)
                }

                return result
            }

            deinit {
                // Deallocate auxiliary buffers
                if let tokens = unsafe _tokens {
                    unsafe tokens.deallocate()
                }
                if let nextFree = unsafe _nextFree {
                    unsafe nextFree.deallocate()
                }

                // Deinit nodes if any
                let count = header.count
                guard count > 0 else { return }

                // Iterative post-order traversal to deinit children before parents
                // Uses explicit stack to avoid stack overflow on deep trees
                _ = unsafe withUnsafeMutablePointerToElements { nodes in
                    var pending = Stack<Int>()
                    var lastVisited: Int = -1

                    if header.rootIndex >= 0 {
                        pending.push(header.rootIndex)
                    }

                    while !pending.isEmpty {
                        let current = pending.peek()!
                        let childIndices = unsafe nodes[current].childIndices

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
                            unsafe (nodes + current).deinitialize(count: 1)
                            lastVisited = current
                        }
                    }
                }
            }

            @usableFromInline
            var _nodesPointer: UnsafeMutablePointer<Node> {
                unsafe withUnsafeMutablePointerToElements { unsafe $0 }
            }

            /// Initializes a node at the given index.
            @usableFromInline
            func _initializeNode(
                at index: Int,
                element: consuming Element,
                parentIndex: Int = -1
            ) {
                let ptr = unsafe withUnsafeMutablePointerToElements { unsafe $0 + index }
                unsafe ptr.initialize(to: Node(
                    element: element,
                    parentIndex: parentIndex
                ))
            }

            /// Deinitializes the node at the given index.
            @usableFromInline
            func _deinitializeNode(at index: Int) {
                let ptr = unsafe _nodesPointer + index
                unsafe ptr.deinitialize(count: 1)
            }

            /// Moves element from the node at the given index.
            @usableFromInline
            func _moveElement(at index: Int) -> Element {
                unsafe withUnsafeMutablePointerToElements { nodes in
                    unsafe (nodes + index).move().element
                }
            }

            /// Moves all elements to new storage.
            ///
            /// After this call, `self` is in an empty state so that
            /// `deinit` won't double-destroy the moved elements.
            /// Auxiliary buffers (tokens, nextFree) are copied 1:1 for the old capacity range.
            @usableFromInline
            func _moveAllElements(to newStorage: Storage) {
                let count = header.count
                let oldCapacity = header.capacity

                // Copy auxiliary buffers (tokens and nextFree) for old capacity range
                if oldCapacity > 0, let srcTokens = unsafe _tokens, let dstTokens = unsafe newStorage._tokens {
                    unsafe dstTokens.update(from: srcTokens, count: oldCapacity)
                }
                if oldCapacity > 0, let srcNextFree = unsafe _nextFree, let dstNextFree = unsafe newStorage._nextFree {
                    unsafe dstNextFree.update(from: srcNextFree, count: oldCapacity)
                }

                guard count > 0 else {
                    // Copy header state even for empty trees (to preserve freeHead)
                    newStorage.header.rootIndex = header.rootIndex
                    newStorage.header.count = header.count
                    newStorage.header.freeHead = header.freeHead
                    // Reset old header
                    header.rootIndex = -1
                    header.count = 0
                    header.freeHead = -1
                    return
                }

                // Copy nodes maintaining their indices (for correct parent/child references)
                // Uses iterative traversal to avoid stack overflow on deep trees
                _ = unsafe withUnsafeMutablePointerToElements { src in
                    unsafe newStorage.withUnsafeMutablePointerToElements { dst in
                        var pending = Stack<Int>()
                        if header.rootIndex >= 0 {
                            pending.push(header.rootIndex)
                        }

                        while !pending.isEmpty {
                            let index = pending.pop()!

                            let childIndices = unsafe src[index].childIndices
                            let parentIndex = unsafe src[index].parentIndex

                            var newNode = Node(
                                element: unsafe (src + index).move().element,
                                parentIndex: parentIndex
                            )
                            newNode.childIndices = childIndices

                            unsafe (dst + index).initialize(to: newNode)

                            // Push children in reverse order so first child is processed first
                            for i in stride(from: childIndices.count - 1, through: 0, by: -1) {
                                pending.push(childIndices[i])
                            }
                        }
                    }
                }

                // Copy header state
                newStorage.header.rootIndex = header.rootIndex
                newStorage.header.count = header.count
                newStorage.header.freeHead = header.freeHead

                // Reset old header so deinit doesn't traverse moved nodes
                header.rootIndex = -1
                header.count = 0
                header.freeHead = -1
            }

            /// Copies all elements to new storage (for CoW).
            ///
            /// Unlike `_moveAllElements`, this preserves the source storage.
            /// Auxiliary buffers (tokens, nextFree) are copied 1:1.
            /// Only available for Copyable elements.
            @usableFromInline
            func _copyAllElements(to newStorage: Storage) where Element: Copyable {
                let count = header.count
                let oldCapacity = header.capacity

                // Copy auxiliary buffers (tokens and nextFree) 1:1
                if oldCapacity > 0, let srcTokens = unsafe _tokens, let dstTokens = unsafe newStorage._tokens {
                    unsafe dstTokens.update(from: srcTokens, count: oldCapacity)
                }
                if oldCapacity > 0, let srcNextFree = unsafe _nextFree, let dstNextFree = unsafe newStorage._nextFree {
                    unsafe dstNextFree.update(from: srcNextFree, count: oldCapacity)
                }

                // Copy header state (even for empty trees to preserve freeHead)
                newStorage.header.rootIndex = header.rootIndex
                newStorage.header.count = header.count
                newStorage.header.freeHead = header.freeHead

                guard count > 0 else { return }

                // Copy nodes maintaining their indices (for correct parent/child references)
                // Uses iterative traversal to avoid stack overflow on deep trees
                _ = unsafe withUnsafeMutablePointerToElements { src in
                    unsafe newStorage.withUnsafeMutablePointerToElements { dst in
                        var pending = Stack<Int>()
                        if header.rootIndex >= 0 {
                            pending.push(header.rootIndex)
                        }

                        while !pending.isEmpty {
                            let index = pending.pop()!

                            let element = unsafe src[index].element
                            let childIndices = unsafe src[index].childIndices
                            let parentIndex = unsafe src[index].parentIndex

                            var newNode = Node(
                                element: element,
                                parentIndex: parentIndex
                            )
                            newNode.childIndices = childIndices

                            unsafe (dst + index).initialize(to: newNode)

                            // Push children in reverse order so first child is processed first
                            for i in stride(from: childIndices.count - 1, through: 0, by: -1) {
                                pending.push(childIndices[i])
                            }
                        }
                    }
                }
                // NOTE: Do NOT reset old header - source storage remains valid
            }
        }

        @usableFromInline
        var _storage: Storage

        /// Cached pointer to node storage. Stored in struct to enable property-based access.
        /// CRITICAL: Must be updated whenever _storage is replaced (reallocation, CoW copy).
        @usableFromInline
        var _cachedPtr: UnsafeMutablePointer<Node>

        /// Cached pointer to token buffer (owned by Storage).
        /// CRITICAL: Must be updated whenever _storage is replaced.
        @usableFromInline
        var _tokens: UnsafeMutablePointer<UInt32>?

        /// Cached pointer to free-list next buffer (owned by Storage).
        /// CRITICAL: Must be updated whenever _storage is replaced.
        @usableFromInline
        var _nextFree: UnsafeMutablePointer<Int>?

        // MARK: - Initialization

        /// Creates an empty unbounded tree.
        @inlinable
        public init() {
            self._storage = Storage.create()
            unsafe (self._cachedPtr = self._storage._nodesPointer)
            unsafe (self._tokens = self._storage._tokens)
            unsafe (self._nextFree = self._storage._nextFree)
        }

        /// Creates an empty unbounded tree with reserved capacity.
        ///
        /// - Parameter minimumCapacity: The minimum number of nodes to reserve space for.
        /// - Throws: ``Error/invalidCapacity`` if capacity is negative.
        @inlinable
        public init(minimumCapacity: Int) throws(__TreeUnboundedError) {
            guard minimumCapacity >= 0 else {
                throw .invalidCapacity
            }
            self._storage = Storage.create(minimumCapacity: minimumCapacity)
            unsafe (self._cachedPtr = self._storage._nodesPointer)
            unsafe (self._tokens = self._storage._tokens)
            unsafe (self._nextFree = self._storage._nextFree)
        }

        // MARK: - Storage Transition Helper

        /// Single point of truth for all storage transitions.
        /// Updates _storage and all cached pointers atomically.
        @usableFromInline
        mutating func _replaceStorage(_ newStorage: Storage) {
            _storage = newStorage
            unsafe (_cachedPtr = newStorage._nodesPointer)
            unsafe (_tokens = newStorage._tokens)
            unsafe (_nextFree = newStorage._nextFree)
        }

        // MARK: - Properties

        /// The number of nodes in the tree.
        @inlinable
        public var count: Int { _storage.header.count }

        /// Whether the tree is empty.
        @inlinable
        public var isEmpty: Bool { _storage.header.count == 0 }

        /// The current capacity of the tree.
        @inlinable
        public var capacity: Int { _storage.header.capacity }

        /// The position of the root node, or `nil` if the tree is empty.
        @inlinable
        public var root: Tree.Position? {
            let rootIndex = _storage.header.rootIndex
            guard rootIndex >= 0, let tokens = unsafe _tokens else { return nil }
            return Tree.Position(index: rootIndex, token: unsafe tokens[rootIndex])
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
            guard position.index >= 0,
                  position.index < capacity,
                  let tokens = unsafe _tokens,
                  unsafe tokens[position.index] == position.token,
                  position.token & 1 == 1 else {  // explicit "occupied" check
                throw .invalidPosition
            }
        }

        // MARK: - Capacity Management

        /// Ensures the tree has capacity for at least the specified number of nodes.
        @usableFromInline
        mutating func ensureCapacity(_ minimumCapacity: Int) {
            guard minimumCapacity > _storage.header.capacity else { return }

            let newCapacity = Swift.max(minimumCapacity, Swift.max(_storage.header.capacity * 2, 4))
            let newStorage = Storage.create(minimumCapacity: newCapacity)
            _storage._moveAllElements(to: newStorage)
            _replaceStorage(newStorage)
        }

        /// Allocates a slot for a new node, returning a token-stamped position.
        ///
        /// The returned token is guaranteed to be odd (occupied state).
        @usableFromInline
        mutating func _allocateSlot() -> (index: Int, token: UInt32) {
            let index: Int

            // Try to reuse from free list
            if _storage.header.freeHead >= 0 {
                index = _storage.header.freeHead
                if let nextFree = unsafe _nextFree {
                    _storage.header.freeHead = unsafe nextFree[index]
                }
            } else {
                // Allocate at end
                ensureCapacity(_storage.header.count + 1)
                index = _storage.header.count
            }

            // Increment token: even (free) → odd (occupied)
            if let tokens = unsafe _tokens {
                unsafe (tokens[index] &+= 1)
                return (index, unsafe tokens[index])
            } else {
                // Zero capacity - should not happen after ensureCapacity
                return (index, 1)
            }
        }

        /// Returns a slot to the free list.
        ///
        /// Increments the token: odd (occupied) → even (free).
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
        let childIndices = unsafe _cachedPtr[position.index].childIndices
        guard index >= 0, index < childIndices.count else { return nil }
        let childIndex = childIndices[index]
        guard let tokens = unsafe _tokens else { return nil }
        return Tree.Position(index: childIndex, token: unsafe tokens[childIndex])
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
        let parentIndex = unsafe _cachedPtr[position.index].parentIndex
        guard parentIndex >= 0, let tokens = unsafe _tokens else { return nil }
        return Tree.Position(index: parentIndex, token: unsafe tokens[parentIndex])
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
        return unsafe _cachedPtr[position.index].childIndices.isEmpty
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
        return unsafe _cachedPtr[position.index].childIndices.count
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
        let childIndices = unsafe _cachedPtr[position.index].childIndices
        guard !childIndices.isEmpty else { return nil }
        let childIndex = childIndices[childIndices.count - 1]
        guard let tokens = unsafe _tokens else { return nil }
        return Tree.Position(index: childIndex, token: unsafe tokens[childIndex])
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
            guard _storage.header.rootIndex < 0 else {
                throw .rootOccupied
            }
            let (index, token) = _allocateSlot()
            _storage._initializeNode(at: index, element: element)
            _storage.header.rootIndex = index
            _storage.header.count += 1
            return Tree.Position(index: index, token: token)

        case .child(of: let parent, at: let childIndex):
            // Validate parent position (token check)
            try _validate(parent)
            let currentChildCount = unsafe _cachedPtr[parent.index].childIndices.count
            guard childIndex >= 0, childIndex <= currentChildCount else {
                throw .childIndexOutOfBounds
            }
            let (index, token) = _allocateSlot()
            _storage._initializeNode(at: index, element: element, parentIndex: parent.index)
            unsafe (_cachedPtr[parent.index].childIndices.insert(index, at: childIndex))
            _storage.header.count += 1
            return Tree.Position(index: index, token: token)

        case .appendChild(of: let parent):
            // Validate parent position (token check)
            try _validate(parent)
            let (index, token) = _allocateSlot()
            _storage._initializeNode(at: index, element: element, parentIndex: parent.index)
            unsafe (_cachedPtr[parent.index].childIndices.append(index))
            _storage.header.count += 1
            return Tree.Position(index: index, token: token)
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

        guard unsafe _cachedPtr[position.index].childIndices.isEmpty else {
            throw .cannotRemoveNonLeaf
        }

        // Update parent's child array
        let parentIndex = unsafe _cachedPtr[position.index].parentIndex
        if parentIndex >= 0 {
            // Find and remove this child from parent's childIndices
            if let childSlot = unsafe _cachedPtr[parentIndex].childIndices.firstIndex(of: position.index) {
                unsafe (_cachedPtr[parentIndex].childIndices.remove(at: childSlot))
            }
        } else {
            // This is the root
            _storage.header.rootIndex = -1
        }

        // Move element out and free slot
        let element = _storage._moveElement(at: position.index)
        _freeSlot(position.index)
        _storage.header.count -= 1

        return element
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
        let parentIndex = unsafe _cachedPtr[position.index].parentIndex
        if parentIndex >= 0 {
            // Find and remove this child from parent's childIndices
            if let childSlot = unsafe _cachedPtr[parentIndex].childIndices.firstIndex(of: position.index) {
                unsafe (_cachedPtr[parentIndex].childIndices.remove(at: childSlot))
            }
        } else {
            // This is the root
            _storage.header.rootIndex = -1
        }

        // Iterative post-order removal using explicit stack
        var pending = Stack<Int>()
        var lastVisited: Int = -1

        pending.push(position.index)

        while !pending.isEmpty {
            let current = pending.peek()!
            let childIndices = unsafe _cachedPtr[current].childIndices

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
                _storage._deinitializeNode(at: current)
                _freeSlot(current)
                _storage.header.count -= 1
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
        return unsafe body(_cachedPtr[position.index].element)
    }

    /// Clears all nodes from the tree.
    @inlinable
    public mutating func clear() {
        guard _storage.header.count > 0 else { return }

        // Iterative post-order traversal using explicit stack
        var pending = Stack<Int>()
        var lastVisited: Int = -1

        if _storage.header.rootIndex >= 0 {
            pending.push(_storage.header.rootIndex)
        }

        while !pending.isEmpty {
            let current = pending.peek()!
            let childIndices = unsafe _cachedPtr[current].childIndices

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
                _storage._deinitializeNode(at: current)
                lastVisited = current
            }
        }

        _storage.header.rootIndex = -1
        _storage.header.count = 0
        _storage.header.freeHead = -1
    }

    /// Computes the height of the tree.
    ///
    /// The height is the length of the longest path from the root to a leaf.
    /// An empty tree has height -1, a single-node tree has height 0.
    ///
    /// Uses iterative traversal to avoid stack overflow on deep trees.
    @inlinable
    public var height: Int {
        let rootIndex = _storage.header.rootIndex
        guard rootIndex >= 0 else { return -1 }

        var maxHeight = 0
        var pending = Stack<(index: Int, depth: Int)>()
        pending.push((rootIndex, 0))

        while !pending.isEmpty {
            let (index, depth) = pending.pop()!
            maxHeight = Swift.max(maxHeight, depth)

            let childIndices = unsafe _cachedPtr[index].childIndices
            for childIndex in childIndices {
                pending.push((childIndex, depth + 1))
            }
        }

        return maxHeight
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
        var pending = Stack<Int>()
        if _storage.header.rootIndex >= 0 {
            pending.push(_storage.header.rootIndex)
        }

        while !pending.isEmpty {
            let index = pending.pop()!
            unsafe body(_cachedPtr[index].element)

            // Push children in reverse order so first child is processed first
            let childIndices = unsafe _cachedPtr[index].childIndices
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
        var pending = Stack<Int>()
        var lastVisited: Int = -1

        if _storage.header.rootIndex >= 0 {
            pending.push(_storage.header.rootIndex)
        }

        while !pending.isEmpty {
            let current = pending.peek()!
            let childIndices = unsafe _cachedPtr[current].childIndices

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
                unsafe body(_cachedPtr[current].element)
                lastVisited = current
            }
        }
    }

    /// Iterates over all elements in level-order (breadth-first) using a borrowing closure.
    ///
    /// - Parameter body: A closure called with each element in level-order.
    @inlinable
    public func forEachLevelOrder(_ body: (borrowing Element) -> Void) {
        guard _storage.header.rootIndex >= 0 else { return }

        var pending = Queue<Int>()
        pending.enqueue(_storage.header.rootIndex)

        while !pending.isEmpty {
            let index = pending.dequeue()!

            unsafe body(_cachedPtr[index].element)

            let childIndices = unsafe _cachedPtr[index].childIndices
            for childIndex in childIndices {
                pending.enqueue(childIndex)
            }
        }
    }
}

// MARK: - Copyable Element Extensions

extension Tree.Unbounded where Element: Copyable {

    /// Makes the storage unique, copying if necessary for copy-on-write.
    /// Also copies the auxiliary buffers (tokens, nextFree) via Storage.
    @usableFromInline
    mutating func makeUnique() {
        if !isKnownUniquelyReferenced(&_storage) {
            let newStorage = Storage.create(minimumCapacity: _storage.header.capacity)
            _storage._copyAllElements(to: newStorage)
            _replaceStorage(newStorage)
        }
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
            guard _storage.header.rootIndex < 0 else {
                throw .rootOccupied
            }
            let (index, token) = _allocateSlot()
            _storage._initializeNode(at: index, element: element)
            _storage.header.rootIndex = index
            _storage.header.count += 1
            return Tree.Position(index: index, token: token)

        case .child(of: let parent, at: let childIndex):
            // Validate parent position (token check)
            try _validate(parent)
            let currentChildCount = unsafe _cachedPtr[parent.index].childIndices.count
            guard childIndex >= 0, childIndex <= currentChildCount else {
                throw .childIndexOutOfBounds
            }
            let (index, token) = _allocateSlot()
            _storage._initializeNode(at: index, element: element, parentIndex: parent.index)
            unsafe (_cachedPtr[parent.index].childIndices.insert(index, at: childIndex))
            _storage.header.count += 1
            return Tree.Position(index: index, token: token)

        case .appendChild(of: let parent):
            // Validate parent position (token check)
            try _validate(parent)
            let (index, token) = _allocateSlot()
            _storage._initializeNode(at: index, element: element, parentIndex: parent.index)
            unsafe (_cachedPtr[parent.index].childIndices.append(index))
            _storage.header.count += 1
            return Tree.Position(index: index, token: token)
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
        return unsafe _cachedPtr[position.index].element
    }
}

// MARK: - Conditional Copyable

extension Tree.Unbounded: Copyable where Element: Copyable {}

// MARK: - Sendable

extension Tree.Unbounded: @unchecked Sendable where Element: Sendable {}
