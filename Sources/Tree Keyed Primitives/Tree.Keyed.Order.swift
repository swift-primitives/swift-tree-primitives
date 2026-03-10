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

extension Tree.Keyed where Element: Copyable {

    /// Namespace for traversal order sequences.
    ///
    /// Provides access to tree traversal sequences organized by traversal order:
    /// - ``Pre``: Pre-order traversal (root, then children in insertion order)
    /// - ``Post``: Post-order traversal (children in insertion order, then root)
    /// - ``Level``: Level-order traversal (breadth-first)
    public enum Order {}
}
