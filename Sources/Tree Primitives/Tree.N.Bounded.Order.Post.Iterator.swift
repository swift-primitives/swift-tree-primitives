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

// MARK: - Post-Order Iterator

extension Tree.N.Bounded.Order.Post {

    /// An iterator for post-order traversal.
    public struct Iterator: Sequence_Primitives.Sequence.Iterator.`Protocol`, IteratorProtocol {
        let tree: Tree.N<Element, n>.Bounded
        var pending: Stack<Index<Tree.N<Element, n>.Node>>
        var lastVisited: Index<Tree.N<Element, n>.Node>?

        init(tree: Tree.N<Element, n>.Bounded) {
            self.tree = tree
            self.pending = Stack<Index<Tree.N<Element, n>.Node>>()
            self.lastVisited = nil
            if let rootIndex = tree._rootIndex {
                pending.push(rootIndex)
            }
        }

        public mutating func next() -> Element? {
            while !pending.isEmpty {
                let current = pending.peek()!
                let nodePtr = unsafe tree._arena.pointer(at: current)

                var hasUnvisitedChild = false
                for slot in stride(from: n - 1, through: 0, by: -1) {
                    if let child = unsafe nodePtr.pointee.childIndices[slot] {
                        if child != lastVisited {
                            var laterChildVisited = false
                            for laterSlot in (slot + 1)..<n {
                                if unsafe nodePtr.pointee.childIndices[laterSlot] == lastVisited {
                                    laterChildVisited = true
                                    break
                                }
                            }
                            if !laterChildVisited {
                                pending.push(child)
                                hasUnvisitedChild = true
                                break
                            }
                        }
                    }
                }

                if !hasUnvisitedChild {
                    _ = pending.pop()
                    lastVisited = current
                    return unsafe nodePtr.pointee.element
                }
            }

            return nil
        }
    }
}
