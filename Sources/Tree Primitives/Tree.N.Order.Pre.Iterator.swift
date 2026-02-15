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

// MARK: - Pre-Order Iterator

extension Tree.N.Order.Pre {

    /// An iterator for pre-order traversal.
    public struct Iterator: Sequence_Primitives.Sequence.Iterator.`Protocol`, IteratorProtocol {
        let tree: Tree.N<Element, n>
        var pending: Stack<Index<Tree.N<Element, n>.Node>>

        init(tree: Tree.N<Element, n>) {
            self.tree = tree
            self.pending = Stack<Index<Tree.N<Element, n>.Node>>()
            if let rootIndex = tree._rootIndex {
                self.pending.push(rootIndex)
            }
        }

        public mutating func next() -> Element? {
            guard !pending.isEmpty else { return nil }

            let index = pending.pop()!
            let nodePtr = unsafe tree._arena.pointer(at: index)
            let element = unsafe nodePtr.pointee.element
            let childIndices = unsafe nodePtr.pointee.childIndices

            // Push children in reverse order so first child is processed first
            for slot in stride(from: n - 1, through: 0, by: -1) {
                if let child = childIndices[slot] {
                    pending.push(child)
                }
            }

            return element
        }
    }
}
