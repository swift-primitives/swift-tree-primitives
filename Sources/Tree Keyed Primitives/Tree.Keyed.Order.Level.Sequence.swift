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

extension Tree.Keyed.Order.Level {

    /// A sequence that yields values in level-order (breadth-first) traversal.
    public struct Sequence: Swift.Sequence {
        let tree: Tree.Keyed<Key, Value>

        public func makeIterator() -> Iterator {
            Iterator(tree: tree)
        }
    }
}
