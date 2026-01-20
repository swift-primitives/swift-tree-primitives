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
            if tree._storage.header.rootIndex >= 0 {
                pending.push(tree._storage.header.rootIndex)
            }
        }

        public mutating func next() -> Element? {
            let ptr = unsafe tree._cachedPtr

            while !pending.isEmpty {
                let current = pending.peek()!

                var hasUnvisitedChild = false
                for slot in stride(from: n - 1, through: 0, by: -1) {
                    let childIndex = unsafe ptr[current].childIndices[slot]
                    if childIndex >= 0 && childIndex != lastVisited {
                        var laterChildVisited = false
                        for laterSlot in (slot + 1)..<n {
                            if unsafe ptr[current].childIndices[laterSlot] == lastVisited {
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
                    return unsafe ptr[current].element
                }
            }

            return nil
        }
    }
}
