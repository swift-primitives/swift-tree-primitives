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

// MARK: - Pre-Order Sequence

extension Tree.N.Order.Pre {

    /// A sequence that yields elements in pre-order traversal.
    ///
    /// Pre-order traversal visits the root first, then children left-to-right.
    public struct Sequence: Swift.Sequence {
        let tree: Tree.N<Element, n>

        public func makeIterator() -> Iterator {
            Iterator(tree: tree)
        }
    }
}
