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

// MARK: - Prune

extension Tree.Keyed where Element: Copyable {

    /// Removes all subtrees rooted at nodes where the predicate returns true.
    ///
    /// Traverses the tree in post-order. When the predicate returns true for a
    /// node, that node and its entire subtree are removed. Surviving branches
    /// are left intact.
    ///
    /// - Parameter shouldRemove: A closure that returns true for nodes to prune.
    @inlinable
    public mutating func prune(where shouldRemove: (Value) -> Bool) {
        guard let rootIndex = _rootIndex else { return }
        makeUnique()

        // Check root first
        let rootPtr = unsafe _arena.pointer(at: rootIndex)
        if shouldRemove(unsafe rootPtr.pointee.value) {
            // Remove entire tree
            if let root = self.root {
                try? removeSubtree(at: root)
            }
            return
        }

        // Collect nodes to prune via pre-order traversal
        var toPrune: [(parentIndex: Index<Node>, key: Key)] = []
        var pending = Stack<Index<Node>>()
        pending.push(rootIndex)

        while !pending.isEmpty {
            let index = pending.pop()!
            let nodePtr = unsafe _arena.pointer(at: index)

            var children: [(key: Key, index: Index<Node>)] = []
            unsafe nodePtr.pointee._children.forEach { key, childIndex in
                children.append((key, childIndex))
            }

            for (childKey, childIndex) in children {
                let childPtr = unsafe _arena.pointer(at: childIndex)
                if shouldRemove(unsafe childPtr.pointee.value) {
                    toPrune.append((parentIndex: index, key: childKey))
                } else {
                    pending.push(childIndex)
                }
            }
        }

        // Remove pruned subtrees (in reverse to avoid invalidation issues)
        for (parentIndex, key) in toPrune.reversed() {
            let parentPtr = unsafe _arena.pointer(at: parentIndex)
            guard let childIndex = unsafe parentPtr.pointee._children[key] else { continue }

            // Remove child from parent's dictionary
            unsafe (parentPtr.pointee._children.remove(key))

            // Free the subtree
            var freePending = Stack<Index<Node>>()
            var freeOutput = Stack<Index<Node>>()
            freePending.push(childIndex)

            while !freePending.isEmpty {
                let current = freePending.pop()!
                freeOutput.push(current)
                let currentPtr = unsafe _arena.pointer(at: current)
                unsafe currentPtr.pointee._children.forEach { _, grandchildIndex in
                    freePending.push(grandchildIndex)
                }
            }

            while !freeOutput.isEmpty {
                let idx = freeOutput.pop()!
                _arena.free(at: idx)
            }
        }
    }
}
