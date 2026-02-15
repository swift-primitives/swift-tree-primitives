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

// MARK: - In-Order Iterator

extension Tree.N.Bounded.Order.In {

    /// An iterator for in-order traversal.
    ///
    /// Only available for binary trees (n == 2).
    public struct Iterator: Sequence_Primitives.Sequence.Iterator.`Protocol`, IteratorProtocol {
        let tree: Tree.N<Element, n>.Bounded
        var pending: Stack<Index<Tree.N<Element, n>.Node>>
        var current: Index<Tree.N<Element, n>.Node>?

        init(tree: Tree.N<Element, n>.Bounded) {
            self.tree = tree
            self.pending = Stack<Index<Tree.N<Element, n>.Node>>()
            self.current = tree._rootIndex
        }

        public mutating func next() -> Element? {
            while current != nil || !pending.isEmpty {
                while let c = current {
                    pending.push(c)
                    current = unsafe tree._arena.pointer(at: c).pointee.childIndices[0]
                }

                let c = pending.pop()!
                let nodePtr = unsafe tree._arena.pointer(at: c)
                let element = unsafe nodePtr.pointee.element
                current = unsafe nodePtr.pointee.childIndices[1]

                return element
            }
            return nil
        }
    }
}
