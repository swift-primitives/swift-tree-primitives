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

internal import Stack_Primitives

// MARK: - In-Order Iterator

extension Tree.N.Bounded.Order.In {

    /// An iterator for in-order traversal.
    ///
    /// Only available for binary trees (n == 2).
    public struct Iterator: IteratorProtocol {
        let tree: Tree.N<Element, n>.Bounded
        var pending: Stack<Int>
        var current: Int

        init(tree: Tree.N<Element, n>.Bounded) {
            self.tree = tree
            self.pending = Stack<Int>()
            self.current = tree._storage.header.rootIndex
        }

        public mutating func next() -> Element? {
            let ptr = unsafe tree._cachedPtr

            while current >= 0 || !pending.isEmpty {
                while current >= 0 {
                    pending.push(current)
                    current = unsafe ptr[current].childIndices[0]
                }

                current = pending.pop()!
                let element = unsafe ptr[current].element
                current = unsafe ptr[current].childIndices[1]

                return element
            }
            return nil
        }
    }
}
