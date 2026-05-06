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

extension Tree.N where n == 2, Element: Copyable {
    /// Namespace for the nested-DSL Tree.Binary builder.
    ///
    /// `Tree.N<2>.Nested` provides a recursive, nestable builder where each
    /// node can have left/right children declared as nested expressions.
    /// Coexists with the flat-BFS `Tree.N<2>.Builder` from Round-1 — choose
    /// the flat builder for *complete* binary trees declared in level order;
    /// choose the nested builder for *sparse* trees with explicit
    /// left/right placement.
    ///
    /// ```swift
    /// let tree = Tree<Int>.Binary.Nested {
    ///     Node(1) {
    ///         Node(2) {
    ///             Node(4)
    ///             Node(5)
    ///         }
    ///         Node(3) {
    ///             Node(6)
    ///         }
    ///     }
    /// }
    /// ```
    public enum Nested {}
}
