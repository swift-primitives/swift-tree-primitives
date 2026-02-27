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

// MARK: - Traversal Sequences (Copyable elements only)

extension Tree.N where Element: Copyable {

    /// A sequence that yields elements in pre-order (root, then children left-to-right).
    public var preOrder: Order.Pre.Sequence {
        Order.Pre.Sequence(tree: self)
    }

    /// A sequence that yields elements in post-order (children left-to-right, then root).
    public var postOrder: Order.Post.Sequence {
        Order.Post.Sequence(tree: self)
    }

    /// A sequence that yields elements in level-order (breadth-first).
    public var levelOrder: Order.Level.Sequence {
        Order.Level.Sequence(tree: self)
    }
}

// MARK: - Binary Tree In-Order Sequence (n == 2 only)

extension Tree.N where Element: Copyable, n == 2 {

    /// A sequence that yields elements in in-order (left, root, right).
    ///
    /// Only available for binary trees (n == 2).
    public var inOrder: Order.In.Sequence {
        Order.In.Sequence(tree: self)
    }
}
