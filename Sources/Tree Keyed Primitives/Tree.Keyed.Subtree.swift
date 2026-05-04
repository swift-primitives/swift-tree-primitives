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

// MARK: - Subtree Extraction

extension Tree.Keyed where Element: Copyable {

    /// Returns a deep copy of the subtree rooted at the given key path.
    ///
    /// Named `subtree(at:)` per [API-NAME-002] — Graph's `subgraph(at:)` uses
    /// graph terminology; `subtree` matches tree terminology.
    ///
    /// For read-only analysis of a subtree, prefer `position(at:)` with
    /// navigation methods (O(1) vs O(n) copy). Use `subtree(at:)` when you
    /// need a standalone tree to pass to other functions or preserve across
    /// mutations.
    ///
    /// - Parameter keyPath: The sequence of keys from root to the subtree root.
    /// - Returns: A standalone tree containing the subtree, or nil if the path
    ///   doesn't resolve.
    /// - Complexity: O(d + n) where d is key path length, n is subtree node count.
    @inlinable
    public func subtree(at keyPath: some Swift.Sequence<Key>) -> Tree<Element>.Keyed<Key>? {
        guard let pos = position(at: keyPath) else { return nil }

        var result = Tree<Element>.Keyed<Key>()
        let sourceIndex = _slot(pos.index)
        let sourcePtr = unsafe _arena.pointer(at: sourceIndex)

        let rootPos = result._arena.insert(Node(value: unsafe sourcePtr.pointee.value))
        result._rootIndex = rootPos.slot

        var pending = Stack<(source: Index<Node>, dest: Index<Node>)>()
        pending.push((sourceIndex, rootPos.slot))

        while !pending.isEmpty {
            let (srcIdx, dstIdx) = pending.pop()!
            let srcPtr = unsafe _arena.pointer(at: srcIdx)

            var children: [(key: Key, index: Index<Node>)] = []
            unsafe srcPtr.pointee._children.forEach { key, childIndex in
                children.append((key, childIndex))
            }

            for (childKey, childIndex) in children {
                let childPtr = unsafe _arena.pointer(at: childIndex)
                let newChild = result._arena.insert(
                    Node(value: unsafe childPtr.pointee.value, parentIndex: dstIdx, parentKey: childKey)
                )
                let destParentPtr = unsafe result._arena.pointer(at: dstIdx)
                unsafe (destParentPtr.pointee._children.set(childKey, newChild.slot))
                pending.push((childIndex, newChild.slot))
            }
        }

        return result
    }
}
