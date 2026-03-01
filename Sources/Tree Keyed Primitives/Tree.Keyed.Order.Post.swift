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

extension Tree.Keyed.Order {

    /// Namespace for post-order traversal types.
    ///
    /// Post-order traversal visits children in insertion order, then the root.
    public enum Post {}
}
