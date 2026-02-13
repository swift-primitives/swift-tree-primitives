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
internal import Buffer_Arena_Primitives

// MARK: - Pre-Order Iterator

extension Tree.N.Bounded.Order.Pre {

    /// An iterator for pre-order traversal.
    public struct Iterator: Sequence.Iterator.`Protocol`, IteratorProtocol {
        let tree: Tree.N<Element, n>.Bounded
        var pending: Stack<Int>

        init(tree: Tree.N<Element, n>.Bounded) {
            self.tree = tree
            self.pending = Stack<Int>()
            if let rootIndex = tree._rootIndex {
                self.pending.push(tree._rawIndex(rootIndex))
            }
        }

        public mutating func next() -> Element? {
            guard !pending.isEmpty else { return nil }

            let index = pending.pop()!
            let nodePtr = unsafe tree._arena.pointer(at: tree._slot(index))
            let element = unsafe nodePtr.pointee.element

            for slot in stride(from: n - 1, through: 0, by: -1) {
                let childIndex = unsafe nodePtr.pointee.childIndices[slot]
                if childIndex >= 0 {
                    pending.push(childIndex)
                }
            }

            return element
        }
    }
}
