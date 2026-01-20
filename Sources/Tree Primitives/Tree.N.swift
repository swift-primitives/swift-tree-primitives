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
/// Uses arena-based storage where all nodes are stored contiguously. Nodes
/// reference each other by index rather than pointer, improving cache locality.
/// Removed nodes are recycled via a free-list for efficient reuse.
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

        // MARK: - Header

        /// Header for arena-based n-ary tree storage.
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

        /// Internal storage class for arena-based n-ary tree.
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
                            unsafe (nodes + current).deinitialize(count: 1)
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
                            let childCount = unsafe src[index].childCount
                            let parentIndex = unsafe src[index].parentIndex

                            var newNode = Node(
                                element: unsafe (src + index).move().element,
                                parentIndex: parentIndex
                            )
                            newNode.childIndices = childIndices
                            newNode.childCount = childCount

                            unsafe (dst + index).initialize(to: newNode)

                            // Push children in reverse order so first child is processed first
                            for slot in stride(from: n - 1, through: 0, by: -1) {
                                let childIndex = childIndices[slot]
                                if childIndex >= 0 {
                                    pending.push(childIndex)
                                }
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
                            let childCount = unsafe src[index].childCount
                            let parentIndex = unsafe src[index].parentIndex

                            var newNode = Node(
                                element: element,
                                parentIndex: parentIndex
                            )
                            newNode.childIndices = childIndices
                            newNode.childCount = childCount

                            unsafe (dst + index).initialize(to: newNode)

                            // Push children in reverse order so first child is processed first
                            for slot in stride(from: n - 1, through: 0, by: -1) {
                                let childIndex = childIndices[slot]
                                if childIndex >= 0 {
                                    pending.push(childIndex)
                                }
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

        /// Creates an empty n-ary tree.
        @inlinable
        public init() {
            self._storage = Storage.create()
            unsafe (self._cachedPtr = self._storage._nodesPointer)
            unsafe (self._tokens = self._storage._tokens)
            unsafe (self._nextFree = self._storage._nextFree)
        }

        /// Creates an empty n-ary tree with reserved capacity.
        ///
        /// - Parameter minimumCapacity: The minimum number of nodes to reserve space for.
        @inlinable
        public init(minimumCapacity: Int) {
            precondition(minimumCapacity >= 0, "Capacity must be non-negative")
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

        /// The maximum arity (number of children per node).
        @inlinable
        public static var arity: Int { n }

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
        func _validate(_ position: Tree.Position) throws(__TreeNError) {
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
        let childIndex = unsafe _cachedPtr[position.index].childIndices[slot.index]
        guard childIndex >= 0, let tokens = unsafe _tokens else { return nil }
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
        return unsafe _cachedPtr[position.index].childCount == 0
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
        return unsafe _cachedPtr[position.index].childCount
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
        for slot in 0..<n {
            let childIndex = unsafe _cachedPtr[position.index].childIndices[slot]
            if childIndex >= 0, let tokens = unsafe _tokens {
                return Tree.Position(index: childIndex, token: unsafe tokens[childIndex])
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
        for slot in stride(from: n - 1, through: 0, by: -1) {
            let childIndex = unsafe _cachedPtr[position.index].childIndices[slot]
            if childIndex >= 0, let tokens = unsafe _tokens {
                return Tree.Position(index: childIndex, token: unsafe tokens[childIndex])
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
            guard _storage.header.rootIndex < 0 else {
                throw .slotOccupied
            }
            let (index, token) = _allocateSlot()
            _storage._initializeNode(at: index, element: element)
            _storage.header.rootIndex = index
            _storage.header.count += 1
            return Tree.Position(index: index, token: token)

        case .child(of: let parent, slot: let slot):
            // Validate parent position (token check)
            try _validate(parent)
            guard unsafe _cachedPtr[parent.index].childIndices[slot.index] < 0 else {
                throw .slotOccupied
            }
            let (index, token) = _allocateSlot()
            _storage._initializeNode(at: index, element: element, parentIndex: parent.index)
            unsafe (_cachedPtr[parent.index].childIndices[slot.index] = index)
            unsafe (_cachedPtr[parent.index].childCount += 1)
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
    public mutating func remove(at position: Tree.Position) throws(__TreeNError) -> Element {
        // Validate position (token check)
        try _validate(position)

        guard unsafe _cachedPtr[position.index].childCount == 0 else {
            throw .cannotRemoveNonLeaf
        }

        // Update parent's child pointer
        let parentIndex = unsafe _cachedPtr[position.index].parentIndex
        if parentIndex >= 0 {
            // Find which slot this child occupies
            for slot in 0..<n {
                if unsafe _cachedPtr[parentIndex].childIndices[slot] == position.index {
                    unsafe (_cachedPtr[parentIndex].childIndices[slot] = -1)
                    unsafe (_cachedPtr[parentIndex].childCount -= 1)
                    break
                }
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
    public mutating func removeSubtree(at position: Tree.Position) throws(__TreeNError) {
        // Validate position (token check)
        try _validate(position)

        // Update parent's child pointer
        let parentIndex = unsafe _cachedPtr[position.index].parentIndex
        if parentIndex >= 0 {
            // Find which slot this child occupies
            for slot in 0..<n {
                if unsafe _cachedPtr[parentIndex].childIndices[slot] == position.index {
                    unsafe (_cachedPtr[parentIndex].childIndices[slot] = -1)
                    unsafe (_cachedPtr[parentIndex].childCount -= 1)
                    break
                }
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
                _storage._deinitializeNode(at: current)
                _freeSlot(current)
                _storage.header.count -= 1
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

            // Find rightmost unvisited child
            var hasUnvisitedChild = false
            for slot in stride(from: n - 1, through: 0, by: -1) {
                let childIndex = unsafe _cachedPtr[current].childIndices[slot]
                if childIndex >= 0 && childIndex != lastVisited {
                    // Check if we've already processed any later children
                    var laterChildVisited = false
                    for laterSlot in (slot + 1)..<n {
                        if unsafe _cachedPtr[current].childIndices[laterSlot] == lastVisited {
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

            for slot in 0..<n {
                let childIndex = unsafe _cachedPtr[index].childIndices[slot]
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
        if _storage.header.rootIndex >= 0 {
            pending.push(_storage.header.rootIndex)
        }

        while !pending.isEmpty {
            let index = pending.pop()!
            unsafe body(_cachedPtr[index].element)

            // Push children in reverse order so first child is processed first
            for slot in stride(from: n - 1, through: 0, by: -1) {
                let childIndex = unsafe _cachedPtr[index].childIndices[slot]
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

        if _storage.header.rootIndex >= 0 {
            pending.push(_storage.header.rootIndex)
        }

        while !pending.isEmpty {
            let current = pending.peek()!
            let childIndices = unsafe _cachedPtr[current].childIndices

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
                unsafe body(_cachedPtr[current].element)
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
        guard _storage.header.rootIndex >= 0 else { return }

        var pending = Queue<Int>()
        pending.enqueue(_storage.header.rootIndex)

        while !pending.isEmpty {
            let index = pending.dequeue()!

            unsafe body(_cachedPtr[index].element)

            for slot in 0..<n {
                let childIndex = unsafe _cachedPtr[index].childIndices[slot]
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
        var current = _storage.header.rootIndex

        while current >= 0 || !pending.isEmpty {
            // Go to leftmost node
            while current >= 0 {
                pending.push(current)
                current = unsafe _cachedPtr[current].childIndices[0]  // left child
            }

            // Process node
            current = pending.pop()!
            unsafe body(_cachedPtr[current].element)

            // Move to right subtree
            current = unsafe _cachedPtr[current].childIndices[1]  // right child
        }
    }
}

// MARK: - Copyable Element Extensions

extension Tree.N where Element: Copyable {

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
    ) throws(__TreeNError) -> Tree.Position {
        makeUnique()

        switch position {
        case .root:
            guard _storage.header.rootIndex < 0 else {
                throw .slotOccupied
            }
            let (index, token) = _allocateSlot()
            _storage._initializeNode(at: index, element: element)
            _storage.header.rootIndex = index
            _storage.header.count += 1
            return Tree.Position(index: index, token: token)

        case .child(of: let parent, slot: let slot):
            // Validate parent position (token check)
            try _validate(parent)
            guard unsafe _cachedPtr[parent.index].childIndices[slot.index] < 0 else {
                throw .slotOccupied
            }
            let (index, token) = _allocateSlot()
            _storage._initializeNode(at: index, element: element, parentIndex: parent.index)
            unsafe (_cachedPtr[parent.index].childIndices[slot.index] = index)
            unsafe (_cachedPtr[parent.index].childCount += 1)
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

extension Tree.N: Copyable where Element: Copyable {}

// MARK: - Sendable

extension Tree.N: @unchecked Sendable where Element: Sendable {}
