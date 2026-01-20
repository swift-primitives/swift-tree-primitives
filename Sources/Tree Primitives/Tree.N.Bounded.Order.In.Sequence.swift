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

// MARK: - In-Order Sequence

extension Tree.N.Bounded.Order.In {

    /// A sequence that yields elements in in-order traversal.
    ///
    /// Only available for binary trees (n == 2).
    public struct Sequence: Swift.Sequence {
        let tree: Tree.N<Element, n>.Bounded

        public func makeIterator() -> Iterator {
            Iterator(tree: tree)
        }
    }
}
