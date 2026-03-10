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

// MARK: - Level-Order Sequence

extension Tree.N.Order.Level {

    /// A sequence that yields elements in level-order (breadth-first) traversal.
    public struct Sequence: Swift.Sequence {
        let tree: Tree.N<n>

        public func makeIterator() -> Iterator {
            Iterator(tree: tree)
        }
    }
}
