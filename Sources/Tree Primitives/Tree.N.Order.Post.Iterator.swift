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

extension Tree.N.Order.Post {

    /// An iterator for post-order traversal.
    public struct Iterator: IteratorProtocol {
        let tree: Tree.N<Element, n>
        var pending: Stack<Int>
        var lastVisited: Int

        init(tree: Tree.N<Element, n>) {
            self.tree = tree
            self.pending = Stack<Int>()
            self.lastVisited = -1

            // Push root if exists
            if tree._rootIndex >= 0 {
                pending.push(tree._rootIndex)
            }
        }

        public mutating func next() -> Element? {
            while !pending.isEmpty {
                let current = pending.peek()!
                let nodePtr = unsafe tree._arena.pointer(at: tree._slot(current))
                let childIndices = unsafe nodePtr.pointee.childIndices

                // Find rightmost existing child index
                var rightmostChildIndex: Int = -1
                for slot in stride(from: n - 1, through: 0, by: -1) {
                    if childIndices[slot] >= 0 {
                        rightmostChildIndex = childIndices[slot]
                        break
                    }
                }

                // Find leftmost existing child index
                var leftmostChildIndex: Int = -1
                for slot in 0..<n {
                    if childIndices[slot] >= 0 {
                        leftmostChildIndex = childIndices[slot]
                        break
                    }
                }

                // Process current if:
                // 1. It's a leaf (no children), OR
                // 2. We came from the rightmost child, OR
                // 3. We came from leftmost child AND no other children exist
                let isLeaf = rightmostChildIndex < 0
                let cameFromRightmost = rightmostChildIndex >= 0 && rightmostChildIndex == lastVisited
                let cameFromLeftmostNoOther = leftmostChildIndex >= 0 && leftmostChildIndex == lastVisited && leftmostChildIndex == rightmostChildIndex

                if isLeaf || cameFromRightmost || cameFromLeftmostNoOther {
                    _ = pending.pop()
                    lastVisited = current
                    return unsafe nodePtr.pointee.element
                } else {
                    // Push children in reverse order (rightmost first so leftmost is processed first)
                    for slot in stride(from: n - 1, through: 0, by: -1) {
                        let childIndex = childIndices[slot]
                        if childIndex >= 0 {
                            pending.push(childIndex)
                        }
                    }
                }
            }

            return nil
        }
    }
}
