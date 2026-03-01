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

// MARK: - Map Values

extension Tree.Keyed where Value: Copyable {

    /// Returns a new tree with the same structure but values transformed by the closure.
    ///
    /// - Parameter transform: A closure that maps each value to a new value.
    /// - Returns: A tree with the same keys and structure, but transformed values.
    @inlinable
    public func mapValues<U>(_ transform: (Value) -> U) -> Tree.Keyed<Key, U> {
        var result = Tree.Keyed<Key, U>()
        guard let rootIndex = _rootIndex else { return result }

        // Pre-order traversal to preserve structure
        var pending = Stack<(source: Index<Node>, parentIndex: Index<Tree.Keyed<Key, U>.Node>?, parentKey: Key?)>()
        pending.push((rootIndex, nil, nil))

        while !pending.isEmpty {
            let (sourceIndex, destParentIndex, key) = pending.pop()!
            let sourcePtr = unsafe _arena.pointer(at: sourceIndex)
            let newValue = transform(unsafe sourcePtr.pointee.value)

            let arenaPos = result._arena.insert(
                Tree.Keyed<Key, U>.Node(value: newValue, parentIndex: destParentIndex, parentKey: key)
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

    /// Returns a new tree with values transformed by a closure that receives the key path.
    ///
    /// This variant provides the full key path from root to each node, enabling
    /// context-aware transformations (e.g., `recursivelyApply` pattern from swift-testing).
    ///
    /// - Parameter transform: A closure that receives the key path and value, returning a new value.
    /// - Returns: A tree with the same keys and structure, but transformed values.
    @inlinable
    public func mapValues<U>(_ transform: ([Key], Value) -> U) -> Tree.Keyed<Key, U> {
        var result = Tree.Keyed<Key, U>()
        guard let rootIndex = _rootIndex else { return result }

        var pending = Stack<(source: Index<Node>, parentIndex: Index<Tree.Keyed<Key, U>.Node>?, parentKey: Key?, path: [Key])>()
        pending.push((rootIndex, nil, nil, []))

        while !pending.isEmpty {
            let (sourceIndex, destParentIndex, key, path) = pending.pop()!
            let sourcePtr = unsafe _arena.pointer(at: sourceIndex)
            let newValue = transform(path, unsafe sourcePtr.pointee.value)

            let arenaPos = result._arena.insert(
                Tree.Keyed<Key, U>.Node(value: newValue, parentIndex: destParentIndex, parentKey: key)
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
                pending.push((children[i].index, arenaPos.slot, children[i].key, childPath))
            }
        }

        return result
    }

    /// Returns a new tree with values optionally transformed, removing nodes where the transform returns nil.
    ///
    /// When a non-leaf node's transform returns nil, its entire subtree is removed.
    ///
    /// - Parameter transform: A closure that optionally transforms each value.
    /// - Returns: A tree with transformed values, minus pruned subtrees.
    @inlinable
    public func compactMapValues<U>(_ transform: (Value) -> U?) -> Tree.Keyed<Key, U> {
        var result = Tree.Keyed<Key, U>()
        guard let rootIndex = _rootIndex else { return result }

        let sourcePtr = unsafe _arena.pointer(at: rootIndex)
        guard let rootValue = transform(unsafe sourcePtr.pointee.value) else { return result }

        let rootPos = result._arena.insert(Tree.Keyed<Key, U>.Node(value: rootValue))
        result._rootIndex = rootPos.slot

        var pending = Stack<(source: Index<Node>, destParent: Index<Tree.Keyed<Key, U>.Node>)>()
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
                    Tree.Keyed<Key, U>.Node(value: childValue, parentIndex: destParentIndex, parentKey: childKey)
                )
                let parentPtr = unsafe result._arena.pointer(at: destParentIndex)
                unsafe (parentPtr.pointee._children.set(childKey, childPos.slot))

                pending.push((childIndex, childPos.slot))
            }
        }

        return result
    }
}
