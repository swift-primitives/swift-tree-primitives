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

// MARK: - Traversal (~Copyable)

extension Tree.Keyed where Element: ~Copyable {

    /// Iterates over all values in pre-order using a borrowing closure.
    ///
    /// Uses iterative traversal to avoid stack overflow on deep trees.
    /// Children are visited in insertion order.
    ///
    /// - Parameter body: A closure called with each value in pre-order.
    @inlinable
    public func forEachPreOrder(_ body: (borrowing Value) -> Void) {
        guard let rootIndex = _rootIndex else { return }
        var pending = Stack<Index<Node>>()
        pending.push(rootIndex)

        while !pending.isEmpty {
            let index = pending.pop()!
            let nodePtr = unsafe _arena.pointer(at: index)
            unsafe body(nodePtr.pointee.value)

            // Collect children, then push in reverse for correct order
            var childIndices: [Index<Node>] = []
            unsafe nodePtr.pointee._children.forEach { _, childIndex in
                childIndices.append(childIndex)
            }
            for i in (0..<childIndices.count).reversed() {
                pending.push(childIndices[i])
            }
        }
    }

    /// Iterates over all values in post-order using a borrowing closure.
    ///
    /// Uses iterative traversal to avoid stack overflow on deep trees.
    /// Children are visited in insertion order.
    ///
    /// - Parameter body: A closure called with each value in post-order.
    @inlinable
    public func forEachPostOrder(_ body: (borrowing Value) -> Void) {
        guard let rootIndex = _rootIndex else { return }

        // Two-stack approach: build reverse post-order, then process
        var pending = Stack<Index<Node>>()
        var output = Stack<Index<Node>>()

        pending.push(rootIndex)

        while !pending.isEmpty {
            let index = pending.pop()!
            output.push(index)

            let nodePtr = unsafe _arena.pointer(at: index)
            // Push children in insertion order (leftmost first) so rightmost ends up on top
            unsafe nodePtr.pointee._children.forEach { _, childIndex in
                pending.push(childIndex)
            }
        }

        // Process in reverse order (post-order)
        while !output.isEmpty {
            let index = output.pop()!
            let nodePtr = unsafe _arena.pointer(at: index)
            unsafe body(nodePtr.pointee.value)
        }
    }

    /// Iterates over all values in level-order (breadth-first) using a borrowing closure.
    ///
    /// Children are visited in insertion order within each level.
    ///
    /// - Parameter body: A closure called with each value in level-order.
    @inlinable
    public func forEachLevelOrder(_ body: (borrowing Value) -> Void) {
        guard let rootIndex = _rootIndex else { return }

        var pending = Queue<Index<Node>>()
        pending.enqueue(rootIndex)

        while !pending.isEmpty {
            let index = pending.dequeue()!
            let nodePtr = unsafe _arena.pointer(at: index)

            unsafe body(nodePtr.pointee.value)

            unsafe nodePtr.pointee._children.forEach { _, childIndex in
                pending.enqueue(childIndex)
            }
        }
    }
}

// MARK: - Traversal Sequences (Copyable values only)

extension Tree.Keyed where Element: Copyable {

    /// A sequence that yields values in pre-order (root, then children in insertion order).
    public var preOrder: Order.Pre.Sequence {
        Order.Pre.Sequence(tree: self)
    }

    /// A sequence that yields values in post-order (children in insertion order, then root).
    public var postOrder: Order.Post.Sequence {
        Order.Post.Sequence(tree: self)
    }

    /// A sequence that yields values in level-order (breadth-first).
    public var levelOrder: Order.Level.Sequence {
        Order.Level.Sequence(tree: self)
    }
}
