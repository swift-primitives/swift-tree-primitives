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
internal import Buffer_Arena_Primitives

// MARK: - Level-Order Iterator

extension Tree.N.Bounded.Order.Level {

    /// An iterator for level-order traversal.
    public struct Iterator: IteratorProtocol {
        let tree: Tree.N<Element, n>.Bounded
        var pending: Queue<Int>

        init(tree: Tree.N<Element, n>.Bounded) {
            self.tree = tree
            self.pending = Queue<Int>()
            if let rootIndex = tree._rootIndex {
                pending.enqueue(tree._rawIndex(rootIndex))
            }
        }

        public mutating func next() -> Element? {
            guard !pending.isEmpty else { return nil }

            let index = pending.dequeue()!
            let nodePtr = unsafe tree._arena.pointer(at: tree._slot(index))
            let element = unsafe nodePtr.pointee.element

            for slot in 0..<n {
                let childIndex = unsafe nodePtr.pointee.childIndices[slot]
                if childIndex >= 0 {
                    pending.enqueue(childIndex)
                }
            }

            return element
        }
    }
}
