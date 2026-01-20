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

// MARK: - Traversal Sequences (Copyable elements only)

extension Tree.Binary where Element: Copyable {

    /// A sequence that yields elements in pre-order (root, left, right).
    public var preOrder: PreOrderSequence {
        PreOrderSequence(tree: self)
    }

    /// A sequence that yields elements in in-order (left, root, right).
    public var inOrder: InOrderSequence {
        InOrderSequence(tree: self)
    }

    /// A sequence that yields elements in post-order (left, right, root).
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
        let tree: Tree.Binary<Element>

        public func makeIterator() -> PreOrderIterator {
            PreOrderIterator(tree: tree)
        }
    }

    /// An iterator for pre-order traversal.
    public struct PreOrderIterator: IteratorProtocol {
        let tree: Tree.Binary<Element>
        var stack: [Int]

        init(tree: Tree.Binary<Element>) {
            self.tree = tree
            self.stack = []
            if tree._storage.header.rootIndex >= 0 {
                self.stack.append(tree._storage.header.rootIndex)
            }
        }

        public mutating func next() -> Element? {
            guard !stack.isEmpty else { return nil }

            let index = stack.removeLast()
            let ptr = unsafe tree._cachedPtr
            let element = unsafe ptr[index].element
            let leftIndex = unsafe ptr[index].leftIndex
            let rightIndex = unsafe ptr[index].rightIndex

            // Push right first so left is processed first
            if rightIndex >= 0 {
                stack.append(rightIndex)
            }
            if leftIndex >= 0 {
                stack.append(leftIndex)
            }

            return element
        }
    }

    // MARK: - InOrder

    /// A sequence that yields elements in in-order traversal.
    public struct InOrderSequence: Sequence {
        let tree: Tree.Binary<Element>

        public func makeIterator() -> InOrderIterator {
            InOrderIterator(tree: tree)
        }
    }

    /// An iterator for in-order traversal.
    public struct InOrderIterator: IteratorProtocol {
        let tree: Tree.Binary<Element>
        var stack: [Int]
        var current: Int

        init(tree: Tree.Binary<Element>) {
            self.tree = tree
            self.stack = []
            self.current = tree._storage.header.rootIndex
        }

        public mutating func next() -> Element? {
            let ptr = unsafe tree._cachedPtr

            while current >= 0 || !stack.isEmpty {
                // Go to leftmost node
                while current >= 0 {
                    stack.append(current)
                    current = unsafe ptr[current].leftIndex
                }

                // Process node
                current = stack.removeLast()
                let element = unsafe ptr[current].element

                // Move to right subtree
                current = unsafe ptr[current].rightIndex

                return element
            }

            return nil
        }
    }

    // MARK: - PostOrder

    /// A sequence that yields elements in post-order traversal.
    public struct PostOrderSequence: Sequence {
        let tree: Tree.Binary<Element>

        public func makeIterator() -> PostOrderIterator {
            PostOrderIterator(tree: tree)
        }
    }

    /// An iterator for post-order traversal.
    public struct PostOrderIterator: IteratorProtocol {
        let tree: Tree.Binary<Element>
        var stack: [Int]
        var lastVisited: Int

        init(tree: Tree.Binary<Element>) {
            self.tree = tree
            self.stack = []
            self.lastVisited = -1

            // Push root if exists
            if tree._storage.header.rootIndex >= 0 {
                stack.append(tree._storage.header.rootIndex)
            }
        }

        public mutating func next() -> Element? {
            let ptr = unsafe tree._cachedPtr

            while !stack.isEmpty {
                let current = stack.last!
                let leftIndex = unsafe ptr[current].leftIndex
                let rightIndex = unsafe ptr[current].rightIndex

                // If we came from right child or no right child, process current
                if rightIndex < 0 || rightIndex == lastVisited {
                    // Also check if we came from left child and there's no right child
                    if leftIndex < 0 || leftIndex == lastVisited || rightIndex == lastVisited {
                        stack.removeLast()
                        lastVisited = current
                        return unsafe ptr[current].element
                    }
                }

                // Otherwise, traverse to children
                if rightIndex >= 0 && rightIndex != lastVisited && leftIndex != lastVisited {
                    stack.append(rightIndex)
                }
                if leftIndex >= 0 && leftIndex != lastVisited {
                    stack.append(leftIndex)
                }
            }

            return nil
        }
    }

    // MARK: - LevelOrder

    /// A sequence that yields elements in level-order (breadth-first) traversal.
    public struct LevelOrderSequence: Sequence {
        let tree: Tree.Binary<Element>

        public func makeIterator() -> LevelOrderIterator {
            LevelOrderIterator(tree: tree)
        }
    }

    /// An iterator for level-order traversal.
    public struct LevelOrderIterator: IteratorProtocol {
        let tree: Tree.Binary<Element>
        var queue: [Int]
        var head: Int

        init(tree: Tree.Binary<Element>) {
            self.tree = tree
            self.queue = []
            self.head = 0

            if tree._storage.header.rootIndex >= 0 {
                queue.append(tree._storage.header.rootIndex)
            }
        }

        public mutating func next() -> Element? {
            guard head < queue.count else { return nil }

            let index = queue[head]
            head += 1

            let ptr = unsafe tree._cachedPtr
            let element = unsafe ptr[index].element
            let leftIndex = unsafe ptr[index].leftIndex
            let rightIndex = unsafe ptr[index].rightIndex

            if leftIndex >= 0 {
                queue.append(leftIndex)
            }
            if rightIndex >= 0 {
                queue.append(rightIndex)
            }

            return element
        }
    }
}

// MARK: - Bounded Traversal Sequences

extension Tree.Binary.Bounded where Element: Copyable {

    /// A sequence that yields elements in pre-order.
    public var preOrder: PreOrderSequence {
        PreOrderSequence(tree: self)
    }

    /// A sequence that yields elements in in-order.
    public var inOrder: InOrderSequence {
        InOrderSequence(tree: self)
    }

    /// A sequence that yields elements in post-order.
    public var postOrder: PostOrderSequence {
        PostOrderSequence(tree: self)
    }

    /// A sequence that yields elements in level-order.
    public var levelOrder: LevelOrderSequence {
        LevelOrderSequence(tree: self)
    }

    /// A sequence that yields elements in pre-order traversal.
    public struct PreOrderSequence: Sequence {
        let tree: Tree.Binary<Element>.Bounded

        public func makeIterator() -> PreOrderIterator {
            PreOrderIterator(tree: tree)
        }
    }

    /// An iterator for pre-order traversal.
    public struct PreOrderIterator: IteratorProtocol {
        let tree: Tree.Binary<Element>.Bounded
        var stack: [Int]

        init(tree: Tree.Binary<Element>.Bounded) {
            self.tree = tree
            self.stack = []
            if tree._storage.header.rootIndex >= 0 {
                self.stack.append(tree._storage.header.rootIndex)
            }
        }

        public mutating func next() -> Element? {
            guard !stack.isEmpty else { return nil }

            let index = stack.removeLast()
            let ptr = unsafe tree._cachedPtr
            let element = unsafe ptr[index].element
            let leftIndex = unsafe ptr[index].leftIndex
            let rightIndex = unsafe ptr[index].rightIndex

            if rightIndex >= 0 { stack.append(rightIndex) }
            if leftIndex >= 0 { stack.append(leftIndex) }

            return element
        }
    }

    /// A sequence that yields elements in in-order traversal.
    public struct InOrderSequence: Sequence {
        let tree: Tree.Binary<Element>.Bounded

        public func makeIterator() -> InOrderIterator {
            InOrderIterator(tree: tree)
        }
    }

    /// An iterator for in-order traversal.
    public struct InOrderIterator: IteratorProtocol {
        let tree: Tree.Binary<Element>.Bounded
        var stack: [Int]
        var current: Int

        init(tree: Tree.Binary<Element>.Bounded) {
            self.tree = tree
            self.stack = []
            self.current = tree._storage.header.rootIndex
        }

        public mutating func next() -> Element? {
            let ptr = unsafe tree._cachedPtr

            while current >= 0 || !stack.isEmpty {
                while current >= 0 {
                    stack.append(current)
                    current = unsafe ptr[current].leftIndex
                }

                current = stack.removeLast()
                let element = unsafe ptr[current].element
                current = unsafe ptr[current].rightIndex

                return element
            }
            return nil
        }
    }

    /// A sequence that yields elements in post-order traversal.
    public struct PostOrderSequence: Sequence {
        let tree: Tree.Binary<Element>.Bounded

        public func makeIterator() -> PostOrderIterator {
            PostOrderIterator(tree: tree)
        }
    }

    /// An iterator for post-order traversal.
    public struct PostOrderIterator: IteratorProtocol {
        let tree: Tree.Binary<Element>.Bounded
        var stack: [Int]
        var lastVisited: Int

        init(tree: Tree.Binary<Element>.Bounded) {
            self.tree = tree
            self.stack = []
            self.lastVisited = -1
            if tree._storage.header.rootIndex >= 0 {
                stack.append(tree._storage.header.rootIndex)
            }
        }

        public mutating func next() -> Element? {
            let ptr = unsafe tree._cachedPtr

            while !stack.isEmpty {
                let current = stack.last!
                let leftIndex = unsafe ptr[current].leftIndex
                let rightIndex = unsafe ptr[current].rightIndex

                if rightIndex < 0 || rightIndex == lastVisited {
                    if leftIndex < 0 || leftIndex == lastVisited || rightIndex == lastVisited {
                        stack.removeLast()
                        lastVisited = current
                        return unsafe ptr[current].element
                    }
                }

                if rightIndex >= 0 && rightIndex != lastVisited && leftIndex != lastVisited {
                    stack.append(rightIndex)
                }
                if leftIndex >= 0 && leftIndex != lastVisited {
                    stack.append(leftIndex)
                }
            }
            return nil
        }
    }

    /// A sequence that yields elements in level-order traversal.
    public struct LevelOrderSequence: Sequence {
        let tree: Tree.Binary<Element>.Bounded

        public func makeIterator() -> LevelOrderIterator {
            LevelOrderIterator(tree: tree)
        }
    }

    /// An iterator for level-order traversal.
    public struct LevelOrderIterator: IteratorProtocol {
        let tree: Tree.Binary<Element>.Bounded
        var queue: [Int]
        var head: Int

        init(tree: Tree.Binary<Element>.Bounded) {
            self.tree = tree
            self.queue = []
            self.head = 0
            if tree._storage.header.rootIndex >= 0 {
                queue.append(tree._storage.header.rootIndex)
            }
        }

        public mutating func next() -> Element? {
            guard head < queue.count else { return nil }

            let index = queue[head]
            head += 1

            let ptr = unsafe tree._cachedPtr
            let element = unsafe ptr[index].element
            let leftIndex = unsafe ptr[index].leftIndex
            let rightIndex = unsafe ptr[index].rightIndex

            if leftIndex >= 0 { queue.append(leftIndex) }
            if rightIndex >= 0 { queue.append(rightIndex) }

            return element
        }
    }
}
