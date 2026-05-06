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

extension Tree.N.Nested where n == 2, Element: Copyable {
    /// A declarative node for the nested-DSL Tree.Binary builder.
    ///
    /// `Node` captures `(element, children)` recursively; the children
    /// list has at most 2 entries (positional convention: first = left,
    /// second = right). Empty children list = leaf.
    ///
    /// ```swift
    /// // Leaf:
    /// Node(42)
    ///
    /// // Internal node with both children:
    /// Node(1) {
    ///     Node(2)
    ///     Node(3)
    /// }
    ///
    /// // Internal node with left child only:
    /// Node(1) {
    ///     Node(2)
    /// }
    /// ```
    ///
    /// ## Right-Only Children
    ///
    /// Positional convention assigns the first declared child to the
    /// `.left` slot. To declare a node with only a right child, use the
    /// imperative `insert(at:)` API after construction:
    ///
    /// ```swift
    /// var tree = Tree<Int>.Binary.Nested { Node(1) { Node(2) } }
    /// // Node 1 has left=2, right=nil. To add right=3:
    /// let root = tree.root!
    /// try tree.insert(3, at: .right(of: root))
    /// ```
    public struct Node {
        public let element: Element
        public let children: [Node]

        /// Creates a leaf node (no children).
        @inlinable
        public init(_ element: Element) {
            self.element = element
            self.children = []
        }

        /// Creates a node with declared children.
        ///
        /// Positional convention: first child = left, second child = right.
        /// Trapping precondition: at most 2 children.
        @inlinable
        public init(
            _ element: Element,
            @Tree<Element>.N<2>.Nested.Builder _ children: () -> [Node]
        ) {
            self.element = element
            self.children = children()
            precondition(
                self.children.count <= 2,
                "Tree.Binary.Nested.Node may declare at most 2 children (left, right)"
            )
        }
    }
}
