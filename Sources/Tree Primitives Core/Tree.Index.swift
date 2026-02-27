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

public import Index_Primitives

extension Tree {
    /// Type-safe index for tree node positions.
    ///
    /// Uses `Index<Element>` to provide compile-time safety preventing
    /// cross-tree index confusion.
    ///
    /// ## Position Semantics
    ///
    /// Position represents a node's index in the tree's internal storage.
    /// For arena-based trees, this is the slot index in the node array.
    ///
    /// ## Relationship to Tree.Position
    ///
    /// `Tree.Index` provides the underlying typed index. `Tree.Position`
    /// (where used) may wrap this with additional validation (e.g., token
    /// for structural modification detection).
    ///
    /// ## Example
    ///
    /// ```swift
    /// let nodeIdx: Tree.Index<Int> = 0  // Root node index
    /// ```
    public typealias Index<Element: ~Copyable> = Index_Primitives.Index<Element>
}
