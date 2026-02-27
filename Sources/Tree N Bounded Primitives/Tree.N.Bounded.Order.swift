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

// MARK: - Order Namespace

extension Tree.N.Bounded where Element: Copyable {

    /// Namespace for traversal order sequences.
    ///
    /// Provides access to tree traversal sequences organized by traversal order:
    /// - ``Pre``: Pre-order traversal (root, then children left-to-right)
    /// - ``Post``: Post-order traversal (children left-to-right, then root)
    /// - ``Level``: Level-order traversal (breadth-first)
    /// - ``In``: In-order traversal (left, root, right) - binary trees only
    public enum Order {}
}
