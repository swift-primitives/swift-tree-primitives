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

extension Tree.Unbounded.Nested where Element: Copyable {
    /// A declarative node for the nested-DSL Tree.Unbounded builder.
    ///
    /// `Node` captures `(element, children)` recursively with any number
    /// of children. Empty children list = leaf.
    ///
    /// ```swift
    /// // Leaf:
    /// Node("alpha")
    ///
    /// // Internal node with three children:
    /// Node("root") {
    ///     Node("a")
    ///     Node("b")
    ///     Node("c")
    /// }
    ///
    /// // Recursive nesting:
    /// Node("root") {
    ///     Node("a") {
    ///         Node("a-1")
    ///         Node("a-2")
    ///     }
    ///     Node("b")
    /// }
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
        /// Children are appended in declaration order via the
        /// `.appendChild` insertion path.
        @inlinable
        public init(
            _ element: Element,
            @Tree<Element>.Unbounded.Nested.Builder _ children: () -> [Node]
        ) {
            self.element = element
            self.children = children()
        }
    }
}
