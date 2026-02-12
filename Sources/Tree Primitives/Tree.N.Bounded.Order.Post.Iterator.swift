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
    public struct Iterator: IteratorProtocol {
        let tree: Tree.N<Element, n>.Bounded
        var pending: Stack<Int>
        var lastVisited: Int

        init(tree: Tree.N<Element, n>.Bounded) {
            self.tree = tree
            self.pending = Stack<Int>()
            self.lastVisited = -1
            if tree._rootIndex >= 0 {
                pending.push(tree._rootIndex)
            }
        }

        public mutating func next() -> Element? {
            while !pending.isEmpty {
                let current = pending.peek()!
                let nodePtr = unsafe tree._arena.pointer(at: tree._slot(current))

                var hasUnvisitedChild = false
                for slot in stride(from: n - 1, through: 0, by: -1) {
                    let childIndex = unsafe nodePtr.pointee.childIndices[slot]
                    if childIndex >= 0 && childIndex != lastVisited {
                        var laterChildVisited = false
                        for laterSlot in (slot + 1)..<n {
                            if unsafe nodePtr.pointee.childIndices[laterSlot] == lastVisited {
                                laterChildVisited = true
                                break
                            }
                        }
                        if !laterChildVisited {
                            pending.push(childIndex)
                            hasUnvisitedChild = true
                            break
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
