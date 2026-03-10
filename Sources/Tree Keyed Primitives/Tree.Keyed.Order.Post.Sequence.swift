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

extension Tree.Keyed.Order.Post {

    /// A sequence that yields values in post-order traversal.
    ///
    /// Post-order traversal visits children in insertion order, then the root.
    public struct Sequence: Swift.Sequence {
        let tree: Tree<Element>.Keyed<Key>

        public func makeIterator() -> Iterator {
            Iterator(tree: tree)
        }
    }
}
