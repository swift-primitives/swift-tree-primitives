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

/// A dynamically-growing binary tree supporting move-only elements.
///
/// `Tree.Binary` is the general-purpose binary tree primitive. It provides O(1)
/// node insertion and O(1) navigation with automatic capacity growth. This is the
/// canonical binary tree type—use it unless you have specific constraints requiring
/// a variant.
///
/// ## Example
///
/// ```swift
/// var tree = Tree.Binary<Int>()
/// let root = try tree.insert(1, at: .root)
/// let left = try tree.insert(2, at: .left(of: root))
/// let right = try tree.insert(3, at: .right(of: root))
///
/// tree.forEachInOrder { element in
///     print(element)  // 2, 1, 3
/// }
/// ```
///
/// ## Variants
///
/// - ``Binary``: Dynamically-growing with amortized O(1) insert (this type)
/// - ``Binary/Bounded``: Fixed-capacity with upfront allocation, throws on overflow
/// - ``Binary/Inline``: Zero-allocation inline storage with compile-time capacity
/// - ``Binary/Small``: Inline storage with automatic spill to heap
///
/// ## Move-Only Support
///
/// Both the tree and its elements can be `~Copyable`:
///
/// ```swift
/// struct FileHandle: ~Copyable { ... }
/// var handles = Tree.Binary<FileHandle>()
/// let root = try handles.insert(FileHandle(), at: .root)
/// ```
///
/// ## Copy-on-Write
///
/// When `Element` is `Copyable`, `Tree.Binary` uses copy-on-write semantics:
/// copies share storage until mutation, providing efficient value semantics.
///
/// ## Arena-Based Storage
///
/// Uses arena-based storage where all nodes are stored contiguously. Nodes
/// reference each other by index rather than pointer, improving cache locality.
/// Removed nodes are recycled via a free-list for efficient reuse.
extension Tree {

    @safe
    public struct Binary<Element: ~Copyable>: ~Copyable {

        // MARK: - Header

        /// Header for arena-based binary tree storage.
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

        /// A node in the arena-based binary tree.
        @usableFromInline
        struct Node: ~Copyable {
            /// The element stored in this node.
            @usableFromInline var element: Element
            /// Index of left child (-1 for none).
            @usableFromInline var leftIndex: Int
            /// Index of right child (-1 for none).
            @usableFromInline var rightIndex: Int
            /// Index of parent (-1 for root).
            @usableFromInline var parentIndex: Int

            @usableFromInline
            init(element: consuming Element, leftIndex: Int = -1, rightIndex: Int = -1, parentIndex: Int = -1) {
                self.element = element
                self.leftIndex = leftIndex
                self.rightIndex = rightIndex
                self.parentIndex = parentIndex
            }
        }

        // MARK: - Storage

        /// Internal storage class for arena-based binary tree.
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
                    var stack = Stack<Int>()
                    var lastVisited: Int = -1

                    if header.rootIndex >= 0 {
                        stack.push(header.rootIndex)
                    }

                    while !stack.isEmpty {
                        let current = stack.peek()!
                        let leftIndex = unsafe nodes[current].leftIndex
                        let rightIndex = unsafe nodes[current].rightIndex

                        // If there's an unvisited left child (and we haven't come up from right), go left
                        if leftIndex >= 0 && leftIndex != lastVisited && rightIndex != lastVisited {
                            stack.push(leftIndex)
                        }
                        // Else if there's an unvisited right child, go right
                        else if rightIndex >= 0 && rightIndex != lastVisited {
                            stack.push(rightIndex)
                        }
                        // Else we're done with children, process current node
                        else {
                            _ = stack.pop()
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
                leftIndex: Int = -1,
                rightIndex: Int = -1,
                parentIndex: Int = -1
            ) {
                let ptr = unsafe withUnsafeMutablePointerToElements { unsafe $0 + index }
                unsafe ptr.initialize(to: Node(
                    element: element,
                    leftIndex: leftIndex,
                    rightIndex: rightIndex,
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
                _ = unsafe withUnsafeMutablePointerToElements { src in
                    unsafe newStorage.withUnsafeMutablePointerToElements { dst in
                        // Move only active nodes (traverse from root)
                        func moveSubtree(at index: Int) {
                            guard index >= 0 else { return }
                            let leftIndex = unsafe src[index].leftIndex
                            let rightIndex = unsafe src[index].rightIndex
                            let parentIndex = unsafe src[index].parentIndex

                            unsafe (dst + index).initialize(to: Node(
                                element: (src + index).move().element,
                                leftIndex: leftIndex,
                                rightIndex: rightIndex,
                                parentIndex: parentIndex
                            ))

                            moveSubtree(at: leftIndex)
                            moveSubtree(at: rightIndex)
                        }

                        moveSubtree(at: header.rootIndex)
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
                _ = unsafe withUnsafeMutablePointerToElements { src in
                    unsafe newStorage.withUnsafeMutablePointerToElements { dst in
                        // Copy only active nodes (traverse from root)
                        func copySubtree(at index: Int) {
                            guard index >= 0 else { return }
                            let element = unsafe src[index].element
                            let leftIndex = unsafe src[index].leftIndex
                            let rightIndex = unsafe src[index].rightIndex
                            let parentIndex = unsafe src[index].parentIndex

                            unsafe (dst + index).initialize(to: Node(
                                element: element,
                                leftIndex: leftIndex,
                                rightIndex: rightIndex,
                                parentIndex: parentIndex
                            ))

                            copySubtree(at: leftIndex)
                            copySubtree(at: rightIndex)
                        }

                        copySubtree(at: header.rootIndex)
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

        // MARK: - Bounded (declared here for ~Copyable propagation)

        /// A fixed-capacity binary tree.
        ///
        /// `Binary.Bounded` allocates storage upfront and throws on overflow.
        /// Use this variant when capacity is known or in contexts requiring
        /// predictable memory behavior (embedded, real-time).
        ///
        /// ## Example
        ///
        /// ```swift
        /// var tree = try Tree.Binary<Int>.Bounded(capacity: 100)
        /// let root = try tree.insert(1, at: .root)
        /// let left = try tree.insert(2, at: .left(of: root))
        /// ```
        @safe
        public struct Bounded: ~Copyable {
            @usableFromInline
            var _storage: Storage

            /// Cached pointer to node storage.
            @usableFromInline
            var _cachedPtr: UnsafeMutablePointer<Node>

            /// Cached pointer to token buffer (owned by Storage).
            @usableFromInline
            var _tokens: UnsafeMutablePointer<UInt32>?

            /// Cached pointer to free-list next buffer (owned by Storage).
            @usableFromInline
            var _nextFree: UnsafeMutablePointer<Int>?

            /// The maximum number of nodes the tree can hold.
            public let capacity: Int

            /// Creates a tree with the specified capacity.
            ///
            /// - Parameter capacity: Maximum number of nodes. Must be non-negative.
            /// - Throws: ``Bounded/Error/invalidCapacity`` if capacity is negative.
            @inlinable
            public init(capacity: Int) throws(__TreeBinaryBoundedError) {
                guard capacity >= 0 else {
                    throw .invalidCapacity
                }
                self.capacity = capacity
                self._storage = Storage.create(minimumCapacity: capacity)
                unsafe (self._cachedPtr = self._storage._nodesPointer)
                unsafe (self._tokens = self._storage._tokens)
                unsafe (self._nextFree = self._storage._nextFree)
            }
        }

        // MARK: - Inline (declared here for ~Copyable propagation)

        /// A fixed-capacity, inline-storage binary tree with compile-time capacity.
        ///
        /// `Binary.Inline` stores nodes directly within the struct's memory layout,
        /// requiring no heap allocation. The capacity is specified as a compile-time
        /// generic parameter.
        ///
        /// ## Example
        ///
        /// ```swift
        /// var tree = Tree.Binary<Int>.Inline<16>()
        /// let root = try tree.insert(1, at: .root)
        /// ```
        ///
        /// ## Non-Copyable
        ///
        /// `Binary.Inline` is unconditionally `~Copyable` (move-only) because it requires
        /// a deinitializer to clean up inline storage.
        ///
        /// - Note: This type is declared inside `Binary` (not in an extension) due to a
        ///   Swift compiler bug where nested types with value generic parameters declared
        ///   in extensions do not properly inherit `~Copyable` constraints from the outer type.
        public struct Inline<let capacity: Int>: ~Copyable {
            /// Maximum node stride supported by inline storage (128 bytes per slot).
            @usableFromInline
            static var _maxStride: Int { 128 }

            /// Inline node with fixed indices.
            @usableFromInline
            struct InlineNode {
                @usableFromInline
                var slot: (Int, Int, Int, Int, Int, Int, Int, Int, Int, Int, Int, Int, Int, Int, Int, Int)
                @usableFromInline
                var leftIndex: Int
                @usableFromInline
                var rightIndex: Int
                @usableFromInline
                var parentIndex: Int
                @usableFromInline
                var isOccupied: Bool

                @usableFromInline
                init() {
                    self.slot = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
                    self.leftIndex = -1
                    self.rightIndex = -1
                    self.parentIndex = -1
                    self.isOccupied = false
                }
            }

            /// Raw storage for nodes.
            @usableFromInline
            var _storage: InlineArray<capacity, InlineNode>

            /// Token buffer for position validation. Each slot's token alternates:
            /// even = free, odd = occupied. Incremented on allocate and free.
            @usableFromInline
            var _tokens: InlineArray<capacity, UInt32>

            /// Free-list next pointers stored separately (not in freed node memory).
            @usableFromInline
            var _nextFree: InlineArray<capacity, Int>

            @usableFromInline
            var _rootIndex: Int

            @usableFromInline
            var _count: Int

            @usableFromInline
            var _freeHead: Int

            /// Workaround for Swift compiler bug where deinit element cleanup
            /// fails for ~Copyable structs that contain only value-type properties.
            /// Adding a reference type property (`AnyObject?`) fixes the bug.
            /// See: https://github.com/swiftlang/swift/issues/86652
            @usableFromInline
            var _deinitWorkaround: AnyObject? = nil

            /// Creates an empty inline binary tree.
            @inlinable
            public init() {
                precondition(
                    MemoryLayout<Element>.stride <= Self._maxStride,
                    "Element stride (\(MemoryLayout<Element>.stride)) exceeds inline storage slot size (\(Self._maxStride) bytes). Use Binary.Bounded instead."
                )
                precondition(
                    MemoryLayout<Element>.alignment <= MemoryLayout<Int>.alignment,
                    "Element alignment (\(MemoryLayout<Element>.alignment)) exceeds inline slot alignment (\(MemoryLayout<Int>.alignment) bytes). Use Binary.Bounded instead."
                )
                self._storage = InlineArray(repeating: InlineNode())
                self._tokens = InlineArray(repeating: 0)  // All start as free (even)
                self._nextFree = InlineArray(repeating: -1)
                self._rootIndex = -1
                self._count = 0
                self._freeHead = -1
            }

            deinit {
                let count = _count
                guard count > 0 else { return }

                // Iterative post-order collection using explicit stack
                var postOrderIndices = Queue<Int>()
                postOrderIndices.reserve(count)

                var stack = Stack<Int>()
                var lastVisited: Int = -1

                if _rootIndex >= 0 {
                    stack.push(_rootIndex)
                }

                while !stack.isEmpty {
                    let current = stack.peek()!
                    let leftIndex = _storage[current].leftIndex
                    let rightIndex = _storage[current].rightIndex

                    // If there's an unvisited left child (and we haven't come up from right), go left
                    if leftIndex >= 0 && leftIndex != lastVisited && rightIndex != lastVisited {
                        stack.push(leftIndex)
                    }
                    // Else if there's an unvisited right child, go right
                    else if rightIndex >= 0 && rightIndex != lastVisited {
                        stack.push(rightIndex)
                    }
                    // Else we're done with children, collect current node
                    else {
                        _ = stack.pop()
                        postOrderIndices.enqueue(current)
                        lastVisited = current
                    }
                }

                // Deinitialize elements using immutable pointer cast to mutable
                let nodeStride = MemoryLayout<InlineNode>.stride
                let slotOffset = MemoryLayout<InlineNode>.offset(of: \.slot) ?? 0

                unsafe Swift.withUnsafePointer(to: _storage) { storagePtr in
                    let basePtr = unsafe UnsafeMutableRawPointer(mutating: unsafe UnsafeRawPointer(storagePtr))
                    while !postOrderIndices.isEmpty {
                        let index = postOrderIndices.dequeue()!
                        let nodePtr = unsafe basePtr + index * nodeStride
                        let elementPtr = unsafe (nodePtr + slotOffset)
                            .assumingMemoryBound(to: Element.self)
                        unsafe elementPtr.deinitialize(count: 1)
                    }
                }
            }
        }

        // MARK: - Small (SmallVec-style: inline then spill to heap)

        /// A binary tree with small-buffer optimization (SmallVec pattern).
        ///
        /// `Binary.Small` stores up to `inlineCapacity` nodes in inline storage,
        /// then automatically spills to heap storage when that capacity is exceeded.
        ///
        /// ## Example
        ///
        /// ```swift
        /// var tree = Tree.Binary<Int>.Small<8>()  // Inline up to 8 nodes
        /// let root = try tree.insert(1, at: .root)
        /// // ... more inserts, spills to heap when > 8 nodes
        /// ```
        ///
        /// ## Non-Copyable
        ///
        /// `Binary.Small` is unconditionally `~Copyable` (move-only) because it requires
        /// a deinitializer to clean up inline storage.
        @safe
        public struct Small<let inlineCapacity: Int>: ~Copyable {
            /// Maximum node stride supported by inline storage (128 bytes per slot).
            @usableFromInline
            static var _maxStride: Int { 128 }

            /// Inline node with fixed indices.
            @usableFromInline
            struct InlineNode {
                @usableFromInline
                var slot: (Int, Int, Int, Int, Int, Int, Int, Int, Int, Int, Int, Int, Int, Int, Int, Int)
                @usableFromInline
                var leftIndex: Int
                @usableFromInline
                var rightIndex: Int
                @usableFromInline
                var parentIndex: Int
                @usableFromInline
                var isOccupied: Bool

                @usableFromInline
                init() {
                    self.slot = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
                    self.leftIndex = -1
                    self.rightIndex = -1
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
            var _heap: Storage?

            /// Cached pointer to heap nodes. Only valid when _heap is non-nil.
            @usableFromInline
            var _heapPtr: UnsafeMutablePointer<Node>?

            /// Cached pointer to heap tokens. Only valid when _heap is non-nil.
            @usableFromInline
            var _heapTokens: UnsafeMutablePointer<UInt32>?

            /// Cached pointer to heap nextFree. Only valid when _heap is non-nil.
            @usableFromInline
            var _heapNextFree: UnsafeMutablePointer<Int>?

            /// Creates an empty small binary tree.
            @inlinable
            public init() {
                precondition(
                    MemoryLayout<Element>.stride <= Self._maxStride,
                    "Element stride (\(MemoryLayout<Element>.stride)) exceeds inline storage slot size (\(Self._maxStride) bytes). Use Binary.Bounded instead."
                )
                precondition(
                    MemoryLayout<Element>.alignment <= MemoryLayout<Int>.alignment,
                    "Element alignment (\(MemoryLayout<Element>.alignment)) exceeds inline slot alignment (\(MemoryLayout<Int>.alignment) bytes). Use Binary.Bounded instead."
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
                    var postOrderIndices = Queue<Int>()
                    postOrderIndices.reserve(count)

                    var stack = Stack<Int>()
                    var lastVisited: Int = -1

                    if _rootIndex >= 0 {
                        stack.push(_rootIndex)
                    }

                    while !stack.isEmpty {
                        let current = stack.peek()!
                        let leftIndex = _inline[current].leftIndex
                        let rightIndex = _inline[current].rightIndex

                        // If there's an unvisited left child (and we haven't come up from right), go left
                        if leftIndex >= 0 && leftIndex != lastVisited && rightIndex != lastVisited {
                            stack.push(leftIndex)
                        }
                        // Else if there's an unvisited right child, go right
                        else if rightIndex >= 0 && rightIndex != lastVisited {
                            stack.push(rightIndex)
                        }
                        // Else we're done with children, collect current node
                        else {
                            _ = stack.pop()
                            postOrderIndices.enqueue(current)
                            lastVisited = current
                        }
                    }

                    // Deinitialize using immutable pointer cast to mutable
                    let nodeStride = MemoryLayout<InlineNode>.stride
                    let slotOffset = MemoryLayout<InlineNode>.offset(of: \.slot) ?? 0

                    unsafe Swift.withUnsafePointer(to: _inline) { storagePtr in
                        let basePtr = unsafe UnsafeMutableRawPointer(mutating: unsafe UnsafeRawPointer(storagePtr))
                        while !postOrderIndices.isEmpty {
                            let index = postOrderIndices.dequeue()!
                            let nodePtr = unsafe basePtr + index * nodeStride
                            let elementPtr = unsafe (nodePtr + slotOffset)
                                .assumingMemoryBound(to: Element.self)
                            unsafe elementPtr.deinitialize(count: 1)
                        }
                    }
                }
            }
        }

        // MARK: - Position Types

        /// A position (cursor) to a node in the binary tree.
        ///
        /// `Position` is a lightweight, type-safe handle for navigating and
        /// operating on tree nodes. Positions are invalidated when the referenced
        /// node is removed.
        ///
        /// ## Token-Based Validation
        ///
        /// Each position carries a token that is validated against the tree's internal
        /// token buffer before any node access. This provides O(1) safety checking:
        /// - Stale positions (after removal) are detected and rejected
        /// - No node memory is accessed without validation
        /// - Tokens use odd/even scheme: odd = occupied, even = free
        public struct Position: Sendable, Equatable, Hashable {
            @usableFromInline
            let index: Int

            /// Token for validity checking (odd = occupied, even = free).
            @usableFromInline
            let token: UInt32

            @usableFromInline
            init(index: Int, token: UInt32) {
                self.index = index
                self.token = token
            }
        }

        /// Specifies where to insert a new node.
        public enum InsertPosition: Sendable, Equatable {
            /// Insert as the root of the tree.
            case root
            /// Insert as the left child of the given position.
            case left(of: Position)
            /// Insert as the right child of the given position.
            case right(of: Position)
        }

        // MARK: - Initialization

        /// Creates an empty binary tree.
        @inlinable
        public init() {
            self._storage = Storage.create()
            unsafe (self._cachedPtr = self._storage._nodesPointer)
            unsafe (self._tokens = self._storage._tokens)
            unsafe (self._nextFree = self._storage._nextFree)
        }

        /// Creates an empty binary tree with reserved capacity.
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

        /// The position of the root node, or `nil` if the tree is empty.
        @inlinable
        public var root: Position? {
            let rootIndex = _storage.header.rootIndex
            guard rootIndex >= 0, let tokens = unsafe _tokens else { return nil }
            return Position(index: rootIndex, token: unsafe tokens[rootIndex])
        }

        // MARK: - Position Validation

        /// Validates that a position refers to a currently-occupied slot.
        ///
        /// Token validation provides O(1) safety checking:
        /// - Stale positions (after removal) are detected and rejected
        /// - No node memory is accessed without validation
        /// - Tokens use odd/even scheme: odd = occupied, even = free
        @usableFromInline
        func _validate(_ position: Position) throws(__TreeBinaryError) {
            guard position.index >= 0,
                  position.index < capacity,
                  let tokens = unsafe _tokens,
                  unsafe tokens[position.index] == position.token,
                  position.token & 1 == 1 else {  // explicit "occupied" check
                throw .invalidPosition
            }
        }

        // MARK: - Navigation

        /// Returns the position of the left child of the node at the given position.
        ///
        /// - Parameter position: The position of the parent node.
        /// - Returns: The position of the left child, or `nil` if there is no left child.
        /// - Note: Returns `nil` if the position is invalid (stale or out of bounds).
        @inlinable
        public func left(of position: Position) -> Position? {
            do {
                try _validate(position)
            } catch {
                return nil
            }
            let leftIndex = unsafe _cachedPtr[position.index].leftIndex
            guard leftIndex >= 0, let tokens = unsafe _tokens else { return nil }
            return Position(index: leftIndex, token: unsafe tokens[leftIndex])
        }

        /// Returns the position of the right child of the node at the given position.
        ///
        /// - Parameter position: The position of the parent node.
        /// - Returns: The position of the right child, or `nil` if there is no right child.
        /// - Note: Returns `nil` if the position is invalid (stale or out of bounds).
        @inlinable
        public func right(of position: Position) -> Position? {
            do {
                try _validate(position)
            } catch {
                return nil
            }
            let rightIndex = unsafe _cachedPtr[position.index].rightIndex
            guard rightIndex >= 0, let tokens = unsafe _tokens else { return nil }
            return Position(index: rightIndex, token: unsafe tokens[rightIndex])
        }

        /// Returns the position of the parent of the node at the given position.
        ///
        /// - Parameter position: The position of the child node.
        /// - Returns: The position of the parent, or `nil` if the node is the root.
        /// - Note: Returns `nil` if the position is invalid (stale or out of bounds).
        @inlinable
        public func parent(of position: Position) -> Position? {
            do {
                try _validate(position)
            } catch {
                return nil
            }
            let parentIndex = unsafe _cachedPtr[position.index].parentIndex
            guard parentIndex >= 0, let tokens = unsafe _tokens else { return nil }
            return Position(index: parentIndex, token: unsafe tokens[parentIndex])
        }

        /// Returns whether the node at the given position is a leaf (has no children).
        ///
        /// - Parameter position: The position to check.
        /// - Returns: `true` if the node has no children, `false` otherwise.
        /// - Note: Returns `false` if the position is invalid (stale or out of bounds).
        @inlinable
        public func isLeaf(_ position: Position) -> Bool {
            do {
                try _validate(position)
            } catch {
                return false
            }
            let leftIndex = unsafe _cachedPtr[position.index].leftIndex
            let rightIndex = unsafe _cachedPtr[position.index].rightIndex
            return leftIndex < 0 && rightIndex < 0
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

// MARK: - Insert Operations (~Copyable)

extension Tree.Binary where Element: ~Copyable {

    /// Inserts an element at the specified position.
    ///
    /// - Parameters:
    ///   - element: The element to insert.
    ///   - position: Where to insert the element.
    /// - Returns: The position of the newly inserted node (with token for validation).
    /// - Throws: ``Error/positionOccupied`` if the position is already occupied,
    ///           ``Error/invalidPosition`` if the parent position is invalid or stale.
    @inlinable
    @discardableResult
    public mutating func insert(
        _ element: consuming Element,
        at position: InsertPosition
    ) throws(__TreeBinaryError) -> Position {
        switch position {
        case .root:
            guard _storage.header.rootIndex < 0 else {
                throw .positionOccupied
            }
            let (index, token) = _allocateSlot()
            _storage._initializeNode(at: index, element: element)
            _storage.header.rootIndex = index
            _storage.header.count += 1
            return Position(index: index, token: token)

        case .left(of: let parent):
            // Validate parent position (token check)
            try _validate(parent)
            guard unsafe _cachedPtr[parent.index].leftIndex < 0 else {
                throw .positionOccupied
            }
            let (index, token) = _allocateSlot()
            _storage._initializeNode(at: index, element: element, parentIndex: parent.index)
            unsafe (_cachedPtr[parent.index].leftIndex = index)
            _storage.header.count += 1
            return Position(index: index, token: token)

        case .right(of: let parent):
            // Validate parent position (token check)
            try _validate(parent)
            guard unsafe _cachedPtr[parent.index].rightIndex < 0 else {
                throw .positionOccupied
            }
            let (index, token) = _allocateSlot()
            _storage._initializeNode(at: index, element: element, parentIndex: parent.index)
            unsafe (_cachedPtr[parent.index].rightIndex = index)
            _storage.header.count += 1
            return Position(index: index, token: token)
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
    public mutating func remove(at position: Position) throws(__TreeBinaryError) -> Element {
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
    public mutating func removeSubtree(at position: Position) throws(__TreeBinaryError) {
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
            // This is the root
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

            // If there's an unvisited left child (and we haven't come up from right), go left
            if leftIndex >= 0 && leftIndex != lastVisited && rightIndex != lastVisited {
                stack.push(leftIndex)
            }
            // Else if there's an unvisited right child, go right
            else if rightIndex >= 0 && rightIndex != lastVisited {
                stack.push(rightIndex)
            }
            // Else we're done with children, process current node
            else {
                _ = stack.pop()
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
    public func peek<R>(at position: Position, _ body: (borrowing Element) -> R) -> R? {
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

            // If there's an unvisited left child (and we haven't come up from right), go left
            if leftIndex >= 0 && leftIndex != lastVisited && rightIndex != lastVisited {
                stack.push(leftIndex)
            }
            // Else if there's an unvisited right child, go right
            else if rightIndex >= 0 && rightIndex != lastVisited {
                stack.push(rightIndex)
            }
            // Else we're done with children, process current node
            else {
                _ = stack.pop()
                _storage._deinitializeNode(at: current)
                lastVisited = current
            }
        }

        _storage.header.rootIndex = -1
        _storage.header.count = 0
        _storage.header.freeHead = -1
    }

    /// Iterates over all elements in pre-order using a borrowing closure.
    ///
    /// - Parameter body: A closure called with each element in pre-order.
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

    /// Iterates over all elements in in-order using a borrowing closure.
    ///
    /// - Parameter body: A closure called with each element in in-order.
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

    /// Iterates over all elements in post-order using a borrowing closure.
    ///
    /// - Parameter body: A closure called with each element in post-order.
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

    /// Iterates over all elements in level-order (breadth-first) using a borrowing closure.
    ///
    /// - Parameter body: A closure called with each element in level-order.
    @inlinable
    public func forEachLevelOrder(_ body: (borrowing Element) -> Void) {
        guard _storage.header.rootIndex >= 0 else { return }

        var queue = Queue<Int>()
        queue.enqueue(_storage.header.rootIndex)

        while !queue.isEmpty {
            let index = queue.dequeue()!

            unsafe body(_cachedPtr[index].element)

            let leftIndex = unsafe _cachedPtr[index].leftIndex
            let rightIndex = unsafe _cachedPtr[index].rightIndex

            if leftIndex >= 0 {
                queue.enqueue(leftIndex)
            }
            if rightIndex >= 0 {
                queue.enqueue(rightIndex)
            }
        }
    }

    /// Computes the height of the tree.
    ///
    /// The height is the length of the longest path from the root to a leaf.
    /// An empty tree has height -1, a single-node tree has height 0.
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

// MARK: - Copyable Element Extensions

extension Tree.Binary where Element: Copyable {

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
    ) throws(__TreeBinaryError) -> Position {
        makeUnique()

        switch position {
        case .root:
            guard _storage.header.rootIndex < 0 else {
                throw .positionOccupied
            }
            let (index, token) = _allocateSlot()
            _storage._initializeNode(at: index, element: element)
            _storage.header.rootIndex = index
            _storage.header.count += 1
            return Position(index: index, token: token)

        case .left(of: let parent):
            // Validate parent position (token check)
            try _validate(parent)
            guard unsafe _cachedPtr[parent.index].leftIndex < 0 else {
                throw .positionOccupied
            }
            let (index, token) = _allocateSlot()
            _storage._initializeNode(at: index, element: element, parentIndex: parent.index)
            unsafe (_cachedPtr[parent.index].leftIndex = index)
            _storage.header.count += 1
            return Position(index: index, token: token)

        case .right(of: let parent):
            // Validate parent position (token check)
            try _validate(parent)
            guard unsafe _cachedPtr[parent.index].rightIndex < 0 else {
                throw .positionOccupied
            }
            let (index, token) = _allocateSlot()
            _storage._initializeNode(at: index, element: element, parentIndex: parent.index)
            unsafe (_cachedPtr[parent.index].rightIndex = index)
            _storage.header.count += 1
            return Position(index: index, token: token)
        }
    }

    /// Returns the element at the specified position.
    ///
    /// - Parameter position: The position of the node.
    /// - Returns: The element at the position, or `nil` if invalid or stale.
    @inlinable
    public func peek(at position: Position) -> Element? {
        do {
            try _validate(position)
        } catch {
            return nil
        }
        return unsafe _cachedPtr[position.index].element
    }
}

// MARK: - Conditional Copyable

extension Tree.Binary: Copyable where Element: Copyable {}
extension Tree.Binary.Bounded: Copyable where Element: Copyable {}
// Note: Binary.Inline and Binary.Small are unconditionally ~Copyable due to deinit requirement

// MARK: - Sendable

extension Tree.Binary: @unchecked Sendable where Element: Sendable {}
extension Tree.Binary.Bounded: @unchecked Sendable where Element: Sendable {}
extension Tree.Binary.Inline: @unchecked Sendable where Element: Sendable {}
extension Tree.Binary.Small: @unchecked Sendable where Element: Sendable {}
