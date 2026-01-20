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

internal import Queue_Primitives

// MARK: - Level-Order Iterator

extension Tree.N.Order.Level {

    /// An iterator for level-order traversal.
    public struct Iterator: IteratorProtocol {
        let tree: Tree.N<Element, n>
        var pending: Queue<Int>

        init(tree: Tree.N<Element, n>) {
            self.tree = tree
            self.pending = Queue<Int>()

            if tree._storage.header.rootIndex >= 0 {
                pending.enqueue(tree._storage.header.rootIndex)
            }
        }

        public mutating func next() -> Element? {
            guard !pending.isEmpty else { return nil }

            let index = pending.dequeue()!

            let ptr = unsafe tree._cachedPtr
            let element = unsafe ptr[index].element
            let childIndices = unsafe ptr[index].childIndices

            for slot in 0..<n {
                let childIndex = childIndices[slot]
                if childIndex >= 0 {
                    pending.enqueue(childIndex)
                }
            }

            return element
        }
    }
}
