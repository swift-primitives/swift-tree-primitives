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

extension Tree.Keyed.Order.Pre {

    /// A sequence that yields values in pre-order traversal.
    ///
    /// Pre-order traversal visits the root first, then children in insertion order.
    public struct Sequence: Swift.Sequence {
        let tree: Tree<Element>.Keyed<Key>

        public func makeIterator() -> Iterator {
            Iterator(tree: tree)
        }
    }
}
