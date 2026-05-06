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

extension Tree.Unbounded where Element: Copyable {
    /// Namespace for the nested-DSL Tree.Unbounded builder.
    ///
    /// `Tree.Unbounded.Nested` provides a recursive, nestable builder
    /// where each node can have any number of children declared as nested
    /// expressions. Coexists with the flat Round-1 builder (root +
    /// children of root only) — choose the flat builder for shallow
    /// single-root trees; choose the nested builder for deep trees with
    /// explicit grandchildren.
    ///
    /// ```swift
    /// let tree = Tree<String>.Unbounded {
    ///     Node("root") {
    ///         Node("alpha") {
    ///             Node("alpha-1")
    ///             Node("alpha-2")
    ///         }
    ///         Node("beta")
    ///         Node("gamma") {
    ///             Node("gamma-1")
    ///         }
    ///     }
    /// }
    /// ```
    public enum Nested {}
}
