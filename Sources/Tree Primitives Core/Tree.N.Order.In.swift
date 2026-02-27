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

// MARK: - In-Order Namespace

extension Tree.N.Order where n == 2 {

    /// Namespace for in-order traversal types.
    ///
    /// In-order traversal visits left subtree, then root, then right subtree.
    /// Only available for binary trees (n == 2).
    public enum In {}
}
