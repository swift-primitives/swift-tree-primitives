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
        @usableFromInline
        final class Storage: ManagedBuffer<Header, Node> {

            @usableFromInline
            static func create() -> Storage {
                let storage = Storage.create(minimumCapacity: 0) { _ in Header() }
                return unsafe unsafeDowncast(storage, to: Storage.self)
            }

            @usableFromInline
            static func create(minimumCapacity: Int) -> Storage {
                var header = Header()
                header.capacity = minimumCapacity
                let storage = Storage.create(minimumCapacity: minimumCapacity) { _ in header }
                return unsafe unsafeDowncast(storage, to: Storage.self)
            }

            deinit {
                let count = header.count
                guard count > 0 else { return }

                // Post-order traversal to deinit children before parents
                func deinitSubtree(at index: Int, nodes: UnsafeMutablePointer<Node>) {
                    guard index >= 0 else { return }
                    let leftIndex = unsafe nodes[index].leftIndex
                    let rightIndex = unsafe nodes[index].rightIndex
                    unsafe deinitSubtree(at: leftIndex, nodes: nodes)
                    unsafe deinitSubtree(at: rightIndex, nodes: nodes)
                    unsafe (nodes + index).deinitialize(count: 1)
                }

                _ = unsafe withUnsafeMutablePointerToElements { nodes in
                    unsafe deinitSubtree(at: header.rootIndex, nodes: nodes)
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

            // MARK: - Free-List Raw Byte Helpers

            /// Loads the free-list next index from a freed slot.
            ///
            /// - Precondition: The slot at `index` must be deinitialized/free.
            @usableFromInline
            func _loadFreeNext(at index: Int) -> Int {
                unsafe withUnsafeMutablePointerToElements { ptr in
                    unsafe UnsafeRawPointer(ptr.advanced(by: index)).load(as: Int.self)
                }
            }

            /// Stores the free-list next index into a freed slot.
            ///
            /// - Precondition: The slot at `index` must be deinitialized/free.
            @usableFromInline
            func _storeFreeNext(at index: Int, next: Int) {
                unsafe withUnsafeMutablePointerToElements { ptr in
                    unsafe UnsafeMutableRawPointer(ptr.advanced(by: index)).storeBytes(of: next, as: Int.self)
                }
            }

            /// Moves all elements to new storage.
            ///
            /// After this call, `self` is in an empty state so that
            /// `deinit` won't double-destroy the moved elements.
            @usableFromInline
            func _moveAllElements(to newStorage: Storage) {
                let count = header.count
                guard count > 0 else { return }

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

                // Rebuild free list for new storage (copy free slot pointers)
                if header.freeHead >= 0 {
                    var freeIndex = header.freeHead
                    while freeIndex >= 0 {
                        let nextFree = _loadFreeNext(at: freeIndex)
                        newStorage._storeFreeNext(at: freeIndex, next: nextFree)
                        freeIndex = nextFree
                    }
                }

                // Reset old header so deinit doesn't traverse moved nodes
                header.rootIndex = -1
                header.count = 0
                header.freeHead = -1
            }

            /// Copies all elements to new storage (for CoW).
            ///
            /// Unlike `_moveAllElements`, this preserves the source storage.
            /// Only available for Copyable elements.
            @usableFromInline
            func _copyAllElements(to newStorage: Storage) where Element: Copyable {
                let count = header.count
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

                // Copy header state
                newStorage.header.rootIndex = header.rootIndex
                newStorage.header.count = header.count
                newStorage.header.freeHead = header.freeHead

                // Rebuild free list for new storage (copy free slot pointers)
                if header.freeHead >= 0 {
                    var freeIndex = header.freeHead
                    while freeIndex >= 0 {
                        let nextFree = _loadFreeNext(at: freeIndex)
                        newStorage._storeFreeNext(at: freeIndex, next: nextFree)
                        freeIndex = nextFree
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

            @usableFromInline
            var _rootIndex: Int

            @usableFromInline
            var _count: Int

            @usableFromInline
            var _freeHead: Int

            /// Workaround for Swift compiler bug where deinit element cleanup
            /// doesn't work correctly for ~Copyable structs without reference types.
            @usableFromInline
            var _deinitWorkaround: AnyObject? = nil

            /// Creates an empty inline binary tree.
            @inlinable
            public init() {
                precondition(
                    MemoryLayout<Element>.stride <= Self._maxStride,
                    "Element stride (\(MemoryLayout<Element>.stride)) exceeds inline storage slot size (\(Self._maxStride) bytes). Use Binary.Bounded instead."
                )
                self._storage = InlineArray(repeating: InlineNode())
                self._rootIndex = -1
                self._count = 0
                self._freeHead = -1
            }

            deinit {
                let count = _count
                guard count > 0 else { return }

                // Collect indices in post-order first (read-only pass)
                var postOrderIndices: [Int] = []
                postOrderIndices.reserveCapacity(count)

                func collectPostOrder(at index: Int) {
                    guard index >= 0 else { return }
                    let leftIndex = _storage[index].leftIndex
                    let rightIndex = _storage[index].rightIndex
                    collectPostOrder(at: leftIndex)
                    collectPostOrder(at: rightIndex)
                    postOrderIndices.append(index)
                }
                collectPostOrder(at: _rootIndex)

                // Deinitialize elements using immutable pointer cast to mutable
                let nodeStride = MemoryLayout<InlineNode>.stride
                let slotOffset = MemoryLayout<InlineNode>.offset(of: \.slot) ?? 0

                unsafe Swift.withUnsafePointer(to: _storage) { storagePtr in
                    let basePtr = unsafe UnsafeMutableRawPointer(mutating: unsafe UnsafeRawPointer(storagePtr))
                    for index in postOrderIndices {
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

            /// Creates an empty small binary tree.
            @inlinable
            public init() {
                precondition(
                    MemoryLayout<Element>.stride <= Self._maxStride,
                    "Element stride (\(MemoryLayout<Element>.stride)) exceeds inline storage slot size (\(Self._maxStride) bytes). Use Binary.Bounded instead."
                )
                self._inline = InlineArray(repeating: InlineNode())
                self._rootIndex = -1
                self._count = 0
                self._freeHead = -1
                self._heap = nil
                unsafe (self._heapPtr = nil)
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
                    // Elements are inline - collect indices in post-order first
                    var postOrderIndices: [Int] = []
                    postOrderIndices.reserveCapacity(count)

                    func collectPostOrder(at index: Int) {
                        guard index >= 0 else { return }
                        let leftIndex = _inline[index].leftIndex
                        let rightIndex = _inline[index].rightIndex
                        collectPostOrder(at: leftIndex)
                        collectPostOrder(at: rightIndex)
                        postOrderIndices.append(index)
                    }
                    collectPostOrder(at: _rootIndex)

                    // Deinitialize using immutable pointer cast to mutable
                    let nodeStride = MemoryLayout<InlineNode>.stride
                    let slotOffset = MemoryLayout<InlineNode>.offset(of: \.slot) ?? 0

                    unsafe Swift.withUnsafePointer(to: _inline) { storagePtr in
                        let basePtr = unsafe UnsafeMutableRawPointer(mutating: unsafe UnsafeRawPointer(storagePtr))
                        for index in postOrderIndices {
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
        public struct Position: Sendable, Equatable, Hashable {
            @usableFromInline
            let index: Int

            @usableFromInline
            init(index: Int) {
                self.index = index
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
        }

        /// Creates an empty binary tree with reserved capacity.
        ///
        /// - Parameter minimumCapacity: The minimum number of nodes to reserve space for.
        @inlinable
        public init(minimumCapacity: Int) {
            precondition(minimumCapacity >= 0, "Capacity must be non-negative")
            self._storage = Storage.create(minimumCapacity: minimumCapacity)
            unsafe (self._cachedPtr = self._storage._nodesPointer)
        }

        // MARK: - Properties

        /// The number of nodes in the tree.
        @inlinable
        public var count: Int { _storage.header.count }

        /// Whether the tree is empty.
        @inlinable
        public var isEmpty: Bool { _storage.header.count == 0 }

        /// The position of the root node, or `nil` if the tree is empty.
        @inlinable
        public var root: Position? {
            let rootIndex = _storage.header.rootIndex
            return rootIndex >= 0 ? Position(index: rootIndex) : nil
        }

        // MARK: - Navigation

        /// Returns the position of the left child of the node at the given position.
        ///
        /// - Parameter position: The position of the parent node.
        /// - Returns: The position of the left child, or `nil` if there is no left child.
        @inlinable
        public func left(of position: Position) -> Position? {
            let leftIndex = unsafe _cachedPtr[position.index].leftIndex
            return leftIndex >= 0 ? Position(index: leftIndex) : nil
        }

        /// Returns the position of the right child of the node at the given position.
        ///
        /// - Parameter position: The position of the parent node.
        /// - Returns: The position of the right child, or `nil` if there is no right child.
        @inlinable
        public func right(of position: Position) -> Position? {
            let rightIndex = unsafe _cachedPtr[position.index].rightIndex
            return rightIndex >= 0 ? Position(index: rightIndex) : nil
        }

        /// Returns the position of the parent of the node at the given position.
        ///
        /// - Parameter position: The position of the child node.
        /// - Returns: The position of the parent, or `nil` if the node is the root.
        @inlinable
        public func parent(of position: Position) -> Position? {
            let parentIndex = unsafe _cachedPtr[position.index].parentIndex
            return parentIndex >= 0 ? Position(index: parentIndex) : nil
        }

        /// Returns whether the node at the given position is a leaf (has no children).
        ///
        /// - Parameter position: The position to check.
        /// - Returns: `true` if the node has no children, `false` otherwise.
        @inlinable
        public func isLeaf(_ position: Position) -> Bool {
            let leftIndex = unsafe _cachedPtr[position.index].leftIndex
            let rightIndex = unsafe _cachedPtr[position.index].rightIndex
            return leftIndex < 0 && rightIndex < 0
        }

        // MARK: - Capacity Management

        /// Ensures the tree has capacity for at least the specified number of nodes.
        @usableFromInline
        mutating func ensureCapacity(_ minimumCapacity: Int) {
            guard minimumCapacity > _storage.capacity else { return }

            let newCapacity = Swift.max(minimumCapacity, Swift.max(_storage.capacity * 2, 4))
            let newStorage = Storage.create(minimumCapacity: newCapacity)
            _storage._moveAllElements(to: newStorage)
            _storage = newStorage
            // CRITICAL: Update cached pointer
            unsafe (_cachedPtr = _storage._nodesPointer)
        }

        /// Allocates a slot for a new node.
        @usableFromInline
        mutating func _allocateSlot() -> Int {
            // Try to reuse from free list
            if _storage.header.freeHead >= 0 {
                let index = _storage.header.freeHead
                _storage.header.freeHead = _storage._loadFreeNext(at: index)
                return index
            }

            // Allocate at end
            ensureCapacity(_storage.header.count + 1)
            return _storage.header.count
        }

        /// Returns a slot to the free list.
        @usableFromInline
        mutating func _freeSlot(_ index: Int) {
            _storage._storeFreeNext(at: index, next: _storage.header.freeHead)
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
    /// - Returns: The position of the newly inserted node.
    /// - Throws: ``Error/positionOccupied`` if the position is already occupied,
    ///           ``Error/invalidPosition`` if the parent position is invalid.
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
            let index = _allocateSlot()
            _storage._initializeNode(at: index, element: element)
            _storage.header.rootIndex = index
            _storage.header.count += 1
            return Position(index: index)

        case .left(of: let parent):
            guard parent.index >= 0 && parent.index < _storage.capacity else {
                throw .invalidPosition
            }
            guard unsafe _cachedPtr[parent.index].leftIndex < 0 else {
                throw .positionOccupied
            }
            let index = _allocateSlot()
            _storage._initializeNode(at: index, element: element, parentIndex: parent.index)
            unsafe (_cachedPtr[parent.index].leftIndex = index)
            _storage.header.count += 1
            return Position(index: index)

        case .right(of: let parent):
            guard parent.index >= 0 && parent.index < _storage.capacity else {
                throw .invalidPosition
            }
            guard unsafe _cachedPtr[parent.index].rightIndex < 0 else {
                throw .positionOccupied
            }
            let index = _allocateSlot()
            _storage._initializeNode(at: index, element: element, parentIndex: parent.index)
            unsafe (_cachedPtr[parent.index].rightIndex = index)
            _storage.header.count += 1
            return Position(index: index)
        }
    }

    /// Removes the leaf node at the specified position.
    ///
    /// - Parameter position: The position of the node to remove. Must be a leaf.
    /// - Returns: The element that was stored at the position.
    /// - Throws: ``Error/invalidPosition`` if the position is invalid,
    ///           ``Error/cannotRemoveNonLeaf`` if the node has children.
    @inlinable
    @discardableResult
    public mutating func remove(at position: Position) throws(__TreeBinaryError) -> Element {
        guard position.index >= 0 && position.index < _storage.capacity else {
            throw .invalidPosition
        }

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
    /// - Throws: ``Error/invalidPosition`` if the position is invalid.
    @inlinable
    public mutating func removeSubtree(at position: Position) throws(__TreeBinaryError) {
        guard position.index >= 0 && position.index < _storage.capacity else {
            throw .invalidPosition
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

        // Post-order removal
        func removeNode(at index: Int) {
            guard index >= 0 else { return }
            let leftIndex = unsafe _cachedPtr[index].leftIndex
            let rightIndex = unsafe _cachedPtr[index].rightIndex
            removeNode(at: leftIndex)
            removeNode(at: rightIndex)
            _storage._deinitializeNode(at: index)
            _freeSlot(index)
            _storage.header.count -= 1
        }

        removeNode(at: position.index)
    }

    /// Accesses the element at the specified position via a borrowing closure.
    ///
    /// - Parameters:
    ///   - position: The position of the node.
    ///   - body: A closure that receives a borrowing reference to the element.
    /// - Returns: The value returned by `body`, or `nil` if the position is invalid.
    @inlinable
    public func peek<R>(at position: Position, _ body: (borrowing Element) -> R) -> R? {
        guard position.index >= 0 && position.index < _storage.capacity else {
            return nil
        }
        return unsafe body(_cachedPtr[position.index].element)
    }

    /// Clears all nodes from the tree.
    @inlinable
    public mutating func clear() {
        guard _storage.header.count > 0 else { return }

        // Post-order traversal to deinit
        func clearSubtree(at index: Int) {
            guard index >= 0 else { return }
            let leftIndex = unsafe _cachedPtr[index].leftIndex
            let rightIndex = unsafe _cachedPtr[index].rightIndex
            clearSubtree(at: leftIndex)
            clearSubtree(at: rightIndex)
            _storage._deinitializeNode(at: index)
        }

        clearSubtree(at: _storage.header.rootIndex)
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

        // Simple array-based queue for level-order traversal
        var queue: [Int] = [_storage.header.rootIndex]
        var head = 0

        while head < queue.count {
            let index = queue[head]
            head += 1

            unsafe body(_cachedPtr[index].element)

            let leftIndex = unsafe _cachedPtr[index].leftIndex
            let rightIndex = unsafe _cachedPtr[index].rightIndex

            if leftIndex >= 0 {
                queue.append(leftIndex)
            }
            if rightIndex >= 0 {
                queue.append(rightIndex)
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
    @usableFromInline
    mutating func makeUnique() {
        if !isKnownUniquelyReferenced(&_storage) {
            let newStorage = Storage.create(minimumCapacity: _storage.capacity)
            _storage._copyAllElements(to: newStorage)
            _storage = newStorage
            // CRITICAL: Update cached pointer
            unsafe (_cachedPtr = _storage._nodesPointer)
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
            let index = _allocateSlot()
            _storage._initializeNode(at: index, element: element)
            _storage.header.rootIndex = index
            _storage.header.count += 1
            return Position(index: index)

        case .left(of: let parent):
            guard parent.index >= 0 && parent.index < _storage.capacity else {
                throw .invalidPosition
            }
            guard unsafe _cachedPtr[parent.index].leftIndex < 0 else {
                throw .positionOccupied
            }
            let index = _allocateSlot()
            _storage._initializeNode(at: index, element: element, parentIndex: parent.index)
            unsafe (_cachedPtr[parent.index].leftIndex = index)
            _storage.header.count += 1
            return Position(index: index)

        case .right(of: let parent):
            guard parent.index >= 0 && parent.index < _storage.capacity else {
                throw .invalidPosition
            }
            guard unsafe _cachedPtr[parent.index].rightIndex < 0 else {
                throw .positionOccupied
            }
            let index = _allocateSlot()
            _storage._initializeNode(at: index, element: element, parentIndex: parent.index)
            unsafe (_cachedPtr[parent.index].rightIndex = index)
            _storage.header.count += 1
            return Position(index: index)
        }
    }

    /// Returns the element at the specified position.
    ///
    /// - Parameter position: The position of the node.
    /// - Returns: The element at the position, or `nil` if invalid.
    @inlinable
    public func peek(at position: Position) -> Element? {
        guard position.index >= 0 && position.index < _storage.capacity else {
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
