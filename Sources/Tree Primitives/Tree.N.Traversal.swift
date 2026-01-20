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

public import Queue_Primitives
public import Stack_Primitives

// MARK: - Traversal Sequences (Copyable elements only)

extension Tree.N where Element: Copyable {

    /// A sequence that yields elements in pre-order (root, then children left-to-right).
    public var preOrder: PreOrderSequence {
        PreOrderSequence(tree: self)
    }

    /// A sequence that yields elements in post-order (children left-to-right, then root).
    public var postOrder: PostOrderSequence {
        PostOrderSequence(tree: self)
    }

    /// A sequence that yields elements in level-order (breadth-first).
    public var levelOrder: LevelOrderSequence {
        LevelOrderSequence(tree: self)
    }

    // MARK: - PreOrder

    /// A sequence that yields elements in pre-order traversal.
    public struct PreOrderSequence: Sequence {
        let tree: Tree.N<Element, n>

        public func makeIterator() -> PreOrderIterator {
            PreOrderIterator(tree: tree)
        }
    }

    /// An iterator for pre-order traversal.
    public struct PreOrderIterator: IteratorProtocol {
        let tree: Tree.N<Element, n>
        var pending: Stack<Int>

        init(tree: Tree.N<Element, n>) {
            self.tree = tree
            self.pending = Stack<Int>()
            if tree._storage.header.rootIndex >= 0 {
                self.pending.push(tree._storage.header.rootIndex)
            }
        }

        public mutating func next() -> Element? {
            guard !pending.isEmpty else { return nil }

            let index = pending.pop()!
            let ptr = unsafe tree._cachedPtr
            let element = unsafe ptr[index].element
            let childIndices = unsafe ptr[index].childIndices

            // Push children in reverse order so first child is processed first
            for slot in stride(from: n - 1, through: 0, by: -1) {
                let childIndex = childIndices[slot]
                if childIndex >= 0 {
                    pending.push(childIndex)
                }
            }

            return element
        }
    }

    // MARK: - PostOrder

    /// A sequence that yields elements in post-order traversal.
    public struct PostOrderSequence: Sequence {
        let tree: Tree.N<Element, n>

        public func makeIterator() -> PostOrderIterator {
            PostOrderIterator(tree: tree)
        }
    }

    /// An iterator for post-order traversal.
    public struct PostOrderIterator: IteratorProtocol {
        let tree: Tree.N<Element, n>
        var pending: Stack<Int>
        var lastVisited: Int

        init(tree: Tree.N<Element, n>) {
            self.tree = tree
            self.pending = Stack<Int>()
            self.lastVisited = -1

            // Push root if exists
            if tree._storage.header.rootIndex >= 0 {
                pending.push(tree._storage.header.rootIndex)
            }
        }

        public mutating func next() -> Element? {
            let ptr = unsafe tree._cachedPtr

            while !pending.isEmpty {
                let current = pending.peek()!
                let childIndices = unsafe ptr[current].childIndices

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
                    return unsafe ptr[current].element
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

    // MARK: - LevelOrder

    /// A sequence that yields elements in level-order (breadth-first) traversal.
    public struct LevelOrderSequence: Sequence {
        let tree: Tree.N<Element, n>

        public func makeIterator() -> LevelOrderIterator {
            LevelOrderIterator(tree: tree)
        }
    }

    /// An iterator for level-order traversal.
    public struct LevelOrderIterator: IteratorProtocol {
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

// MARK: - Binary Tree In-Order Sequence (n == 2 only)

extension Tree.N where Element: Copyable, n == 2 {

    /// A sequence that yields elements in in-order (left, root, right).
    ///
    /// Only available for binary trees (n == 2).
    public var inOrder: InOrderSequence {
        InOrderSequence(tree: self)
    }

    /// A sequence that yields elements in in-order traversal.
    public struct InOrderSequence: Sequence {
        let tree: Tree.N<Element, n>

        public func makeIterator() -> InOrderIterator {
            InOrderIterator(tree: tree)
        }
    }

    /// An iterator for in-order traversal.
    public struct InOrderIterator: IteratorProtocol {
        let tree: Tree.N<Element, n>
        var pending: Stack<Int>
        var current: Int

        init(tree: Tree.N<Element, n>) {
            self.tree = tree
            self.pending = Stack<Int>()
            self.current = tree._storage.header.rootIndex
        }

        public mutating func next() -> Element? {
            let ptr = unsafe tree._cachedPtr

            while current >= 0 || !pending.isEmpty {
                // Go to leftmost node
                while current >= 0 {
                    pending.push(current)
                    current = unsafe ptr[current].childIndices[0]  // left child
                }

                // Process node
                current = pending.pop()!
                let element = unsafe ptr[current].element

                // Move to right subtree
                current = unsafe ptr[current].childIndices[1]  // right child

                return element
            }

            return nil
        }
    }
}
