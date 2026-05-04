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

public import Queue_Dynamic_Primitives

// MARK: - Map Values

extension Tree.Keyed where Element: Copyable {

    /// Returns a new tree with the same structure but values transformed by the closure.
    ///
    /// - Parameter transform: A closure that maps each value to a new value.
    /// - Returns: A tree with the same keys and structure, but transformed values.
    @inlinable
    public func mapValues<U>(_ transform: (Value) -> U) -> Tree<U>.Keyed<Key> {
        var result = Tree<U>.Keyed<Key>()
        guard let rootIndex = _rootIndex else { return result }

        // Pre-order traversal to preserve structure
        var pending = Stack<(source: Index<Node>, parentIndex: Index<Tree<U>.Keyed<Key>.Node>?, parentKey: Key?)>()
        pending.push((rootIndex, nil, nil))

        while !pending.isEmpty {
            let (sourceIndex, destParentIndex, key) = pending.pop()!
            let sourcePtr = unsafe _arena.pointer(at: sourceIndex)
            let newValue = transform(unsafe sourcePtr.pointee.value)

            let arenaPos = result._arena.insert(
                Tree<U>.Keyed<Key>.Node(value: newValue, parentIndex: destParentIndex, parentKey: key)
            )

            if let destParentIndex {
                let parentPtr = unsafe result._arena.pointer(at: destParentIndex)
                unsafe (parentPtr.pointee._children.set(key!, arenaPos.slot))
            } else {
                result._rootIndex = arenaPos.slot
            }

            // Collect children in reverse for correct order
            var children: [(key: Key, index: Index<Node>)] = []
            unsafe sourcePtr.pointee._children.forEach { childKey, childIndex in
                children.append((childKey, childIndex))
            }
            for i in stride(from: children.count - 1, through: 0, by: -1) {
                pending.push((children[i].index, arenaPos.slot, children[i].key))
            }
        }

        return result
    }

    // MARK: - Map Values with Key Path

    /// Returns a new tree with values transformed by a closure that receives the key path.
    ///
    /// Delegates to ``compactMapValues(_:)-4k9z`` per [IMPL-033].
    ///
    /// - Parameter transform: A closure that receives the key path and value, returning a new value.
    /// - Returns: A tree with the same keys and structure, but transformed values.
    @inlinable
    public func mapValues<U, E>(
        _ transform: ([Key], Value) throws(E) -> U
    ) throws(E) -> Tree<U>.Keyed<Key> {
        try compactMapValues { (path, value) throws(E) -> U? in
            try transform(path, value)
        }
    }

    /// Returns a new tree with values transformed, optionally broadcasting the result
    /// to all descendants.
    ///
    /// When the transform returns `recursivelyApply: true`, the transformed value
    /// is assigned to the node and all its descendants without calling the transform
    /// again. When the transform returns `recursivelyApply: false`, each descendant
    /// is transformed independently.
    ///
    /// Delegates to ``compactMapValues(_:)-8r2v`` per [IMPL-033].
    ///
    /// - Parameter transform: A closure that receives the key path and value,
    ///   returning the new value and whether to broadcast it to descendants.
    /// - Returns: A tree with the same keys and structure, but transformed values.
    @inlinable
    public func mapValues<U, E>(
        _ transform: ([Key], Value) throws(E) -> (U, recursivelyApply: Bool)
    ) throws(E) -> Tree<U>.Keyed<Key> {
        try compactMapValues { (path, value) throws(E) in
            try transform(path, value) as (U, recursivelyApply: Bool)?
        }
    }

    // MARK: - Compact Map Values with Key Path

    /// Returns a new tree with values optionally transformed, removing nodes where
    /// the transform returns nil. The key path from root to each node is provided.
    ///
    /// When a node's transform returns nil, the node and its entire subtree are dropped.
    ///
    /// Delegates to ``compactMapValues(_:)-8r2v`` per [IMPL-033].
    ///
    /// - Parameter transform: A closure that receives the key path and value,
    ///   returning the new value or nil to drop the subtree.
    /// - Returns: A tree with transformed values, minus pruned subtrees.
    @inlinable
    public func compactMapValues<U, E>(
        _ transform: ([Key], Value) throws(E) -> U?
    ) throws(E) -> Tree<U>.Keyed<Key> {
        try compactMapValues { (path, value) throws(E) in
            try transform(path, value).map { ($0, recursivelyApply: false) }
        }
    }

    /// Returns a new tree with values optionally transformed, with optional broadcasting
    /// to descendants.
    ///
    /// This is the core tree-transform primitive. All other key-path-aware
    /// `mapValues` and `compactMapValues` variants delegate to this method.
    ///
    /// When the transform returns `recursivelyApply: true`, the value is broadcast
    /// to all descendants without calling the transform for each. When the transform
    /// returns nil, the node and its entire subtree are dropped.
    ///
    /// - Parameter transform: A closure that receives the key path and value,
    ///   returning the new value and broadcast flag, or nil to drop the subtree.
    /// - Returns: A tree with transformed values, minus pruned subtrees.
    /// - Complexity: O(n) where n is the number of nodes in the source tree.
    @inlinable
    public func compactMapValues<U, E>(
        _ transform: ([Key], Value) throws(E) -> (U, recursivelyApply: Bool)?
    ) throws(E) -> Tree<U>.Keyed<Key> {
        var result = Tree<U>.Keyed<Key>()
        guard let rootIndex = _rootIndex else { return result }

        var pending = Stack<
            (
                source: Index<Node>,
                destParent: Index<Tree<U>.Keyed<Key>.Node>?,
                parentKey: Key?,
                path: [Key],
                broadcast: U?
            )
        >()
        pending.push((rootIndex, nil, nil, [], nil))

        while !pending.isEmpty {
            let (sourceIndex, destParentIndex, key, path, broadcast) = pending.pop()!
            let sourcePtr = unsafe _arena.pointer(at: sourceIndex)

            let newValue: U
            let shouldBroadcast: Bool

            if let broadcastValue = broadcast {
                newValue = broadcastValue
                shouldBroadcast = true
            } else {
                guard let transformed = try transform(path, unsafe sourcePtr.pointee.value) else {
                    continue
                }
                newValue = transformed.0
                shouldBroadcast = transformed.recursivelyApply
            }

            let arenaPos = result._arena.insert(
                Tree<U>.Keyed<Key>.Node(value: newValue, parentIndex: destParentIndex, parentKey: key)
            )

            if let destParentIndex {
                let parentPtr = unsafe result._arena.pointer(at: destParentIndex)
                unsafe (parentPtr.pointee._children.set(key!, arenaPos.slot))
            } else {
                result._rootIndex = arenaPos.slot
            }

            var children: [(key: Key, index: Index<Node>)] = []
            unsafe sourcePtr.pointee._children.forEach { childKey, childIndex in
                children.append((childKey, childIndex))
            }
            for i in stride(from: children.count - 1, through: 0, by: -1) {
                var childPath = path
                childPath.append(children[i].key)
                pending.push(
                    (
                        children[i].index,
                        arenaPos.slot,
                        children[i].key,
                        childPath,
                        shouldBroadcast ? newValue : nil
                    )
                )
            }
        }

        return result
    }

    // MARK: - Compact Map Values (Simple)

    /// Returns a new tree with values optionally transformed, removing nodes where the transform returns nil.
    ///
    /// When a non-leaf node's transform returns nil, its entire subtree is removed.
    ///
    /// - Parameter transform: A closure that optionally transforms each value.
    /// - Returns: A tree with transformed values, minus pruned subtrees.
    @inlinable
    public func compactMapValues<U>(_ transform: (Value) -> U?) -> Tree<U>.Keyed<Key> {
        var result = Tree<U>.Keyed<Key>()
        guard let rootIndex = _rootIndex else { return result }

        let sourcePtr = unsafe _arena.pointer(at: rootIndex)
        guard let rootValue = transform(unsafe sourcePtr.pointee.value) else { return result }

        let rootPos = result._arena.insert(Tree<U>.Keyed<Key>.Node(value: rootValue))
        result._rootIndex = rootPos.slot

        var pending = Stack<(source: Index<Node>, destParent: Index<Tree<U>.Keyed<Key>.Node>)>()
        pending.push((rootIndex, rootPos.slot))

        while !pending.isEmpty {
            let (sourceIndex, destParentIndex) = pending.pop()!
            let sourceNodePtr = unsafe _arena.pointer(at: sourceIndex)

            var children: [(key: Key, index: Index<Node>)] = []
            unsafe sourceNodePtr.pointee._children.forEach { childKey, childIndex in
                children.append((childKey, childIndex))
            }

            for (childKey, childIndex) in children {
                let childPtr = unsafe _arena.pointer(at: childIndex)
                guard let childValue = transform(unsafe childPtr.pointee.value) else { continue }

                let childPos = result._arena.insert(
                    Tree<U>.Keyed<Key>.Node(value: childValue, parentIndex: destParentIndex, parentKey: childKey)
                )
                let parentPtr = unsafe result._arena.pointer(at: destParentIndex)
                unsafe (parentPtr.pointee._children.set(childKey, childPos.slot))

                pending.push((childIndex, childPos.slot))
            }
        }

        return result
    }
}

// MARK: - Map Values (Async)

extension Tree.Keyed where Element: Copyable {

    /// Async variant of ``mapValues(_:)-2g7k``.
    @inlinable
    public func mapValues<U, E>(
        _ transform: ([Key], Value) async throws(E) -> U
    ) async throws(E) -> Tree<U>.Keyed<Key> {
        try await compactMapValues { (path, value) async throws(E) -> U? in
            try await transform(path, value)
        }
    }

    /// Async variant of ``mapValues(_:)-5h3r``.
    @inlinable
    public func mapValues<U, E>(
        _ transform: ([Key], Value) async throws(E) -> (U, recursivelyApply: Bool)
    ) async throws(E) -> Tree<U>.Keyed<Key> {
        try await compactMapValues { (path, value) async throws(E) in
            try await transform(path, value) as (U, recursivelyApply: Bool)?
        }
    }

    /// Async variant of ``compactMapValues(_:)-4k9z``.
    @inlinable
    public func compactMapValues<U, E>(
        _ transform: ([Key], Value) async throws(E) -> U?
    ) async throws(E) -> Tree<U>.Keyed<Key> {
        try await compactMapValues { (path, value) async throws(E) in
            try await transform(path, value).map { ($0, recursivelyApply: false) }
        }
    }

    /// Async variant of ``compactMapValues(_:)-8r2v``.
    @inlinable
    public func compactMapValues<U, E>(
        _ transform: ([Key], Value) async throws(E) -> (U, recursivelyApply: Bool)?
    ) async throws(E) -> Tree<U>.Keyed<Key> {
        var result = Tree<U>.Keyed<Key>()
        guard let rootIndex = _rootIndex else { return result }

        var pending = Stack<
            (
                source: Index<Node>,
                destParent: Index<Tree<U>.Keyed<Key>.Node>?,
                parentKey: Key?,
                path: [Key],
                broadcast: U?
            )
        >()
        pending.push((rootIndex, nil, nil, [], nil))

        while !pending.isEmpty {
            let (sourceIndex, destParentIndex, key, path, broadcast) = pending.pop()!
            let sourcePtr = unsafe _arena.pointer(at: sourceIndex)

            let newValue: U
            let shouldBroadcast: Bool

            if let broadcastValue = broadcast {
                newValue = broadcastValue
                shouldBroadcast = true
            } else {
                guard let transformed = try await transform(path, unsafe sourcePtr.pointee.value) else {
                    continue
                }
                newValue = transformed.0
                shouldBroadcast = transformed.recursivelyApply
            }

            let arenaPos = result._arena.insert(
                Tree<U>.Keyed<Key>.Node(value: newValue, parentIndex: destParentIndex, parentKey: key)
            )

            if let destParentIndex {
                let parentPtr = unsafe result._arena.pointer(at: destParentIndex)
                unsafe (parentPtr.pointee._children.set(key!, arenaPos.slot))
            } else {
                result._rootIndex = arenaPos.slot
            }

            var children: [(key: Key, index: Index<Node>)] = []
            unsafe sourcePtr.pointee._children.forEach { childKey, childIndex in
                children.append((childKey, childIndex))
            }
            for i in stride(from: children.count - 1, through: 0, by: -1) {
                var childPath = path
                childPath.append(children[i].key)
                pending.push(
                    (
                        children[i].index,
                        arenaPos.slot,
                        children[i].key,
                        childPath,
                        shouldBroadcast ? newValue : nil
                    )
                )
            }
        }

        return result
    }
}
