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
    public struct Iterator: IteratorProtocol {
        let tree: Tree.N<Element, n>.Bounded
        var pending: Stack<Int>
        var current: Int

        init(tree: Tree.N<Element, n>.Bounded) {
            self.tree = tree
            self.pending = Stack<Int>()
            if let rootIndex = tree._rootIndex {
                self.current = tree._rawIndex(rootIndex)
            } else {
                self.current = -1
            }
        }

        public mutating func next() -> Element? {
            while current >= 0 || !pending.isEmpty {
                while current >= 0 {
                    pending.push(current)
                    current = unsafe tree._arena.pointer(at: tree._slot(current)).pointee.childIndices[0]
                }

                current = pending.pop()!
                let nodePtr = unsafe tree._arena.pointer(at: tree._slot(current))
                let element = unsafe nodePtr.pointee.element
                current = unsafe nodePtr.pointee.childIndices[1]

                return element
            }
            return nil
        }
    }
}
