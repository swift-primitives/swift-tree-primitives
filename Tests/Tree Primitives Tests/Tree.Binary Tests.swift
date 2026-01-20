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

import Testing
@testable import Tree_Primitives

// MARK: - Tree.Binary Tests

@Suite("Tree.Binary")
struct TreeBinaryTests {

    @Test("Empty tree")
    func emptyTree() {
        let tree = Tree.Binary<Int>()
        #expect(tree.isEmpty)
        #expect(tree.count == 0)
        #expect(tree.root == nil)
        #expect(tree.height == -1)
    }

    @Test("Insert root")
    func insertRoot() throws {
        var tree = Tree.Binary<Int>()
        let root = try tree.insert(42, at: .root)

        #expect(!tree.isEmpty)
        #expect(tree.count == 1)
        #expect(tree.root != nil)
        #expect(tree.root == root)
        #expect(tree.peek(at: root) == 42)
        #expect(tree.height == 0)
    }

    @Test("Insert children")
    func insertChildren() throws {
        var tree = Tree.Binary<Int>()
        let root = try tree.insert(1, at: .root)
        let left = try tree.insert(2, at: .left(of: root))
        let right = try tree.insert(3, at: .right(of: root))

        #expect(tree.count == 3)
        #expect(tree.left(of: root) == left)
        #expect(tree.right(of: root) == right)
        #expect(tree.parent(of: left) == root)
        #expect(tree.parent(of: right) == root)
        #expect(tree.isLeaf(root) == false)
        #expect(tree.isLeaf(left) == true)
        #expect(tree.isLeaf(right) == true)
        #expect(tree.height == 1)
    }

    @Test("Insert throws on occupied root")
    func insertThrowsOnOccupiedRoot() throws {
        var tree = Tree.Binary<Int>()
        _ = try tree.insert(1, at: .root)

        #expect(throws: __TreeBinaryError.positionOccupied) {
            try tree.insert(2, at: .root)
        }
    }

    @Test("Insert throws on occupied child")
    func insertThrowsOnOccupiedChild() throws {
        var tree = Tree.Binary<Int>()
        let root = try tree.insert(1, at: .root)
        _ = try tree.insert(2, at: .left(of: root))

        #expect(throws: __TreeBinaryError.positionOccupied) {
            try tree.insert(3, at: .left(of: root))
        }
    }

    @Test("Remove leaf")
    func removeLeaf() throws {
        var tree = Tree.Binary<Int>()
        let root = try tree.insert(1, at: .root)
        let left = try tree.insert(2, at: .left(of: root))

        let removed = try tree.remove(at: left)
        #expect(removed == 2)
        #expect(tree.count == 1)
        #expect(tree.left(of: root) == nil)
    }

    @Test("Remove throws on non-leaf")
    func removeThrowsOnNonLeaf() throws {
        var tree = Tree.Binary<Int>()
        let root = try tree.insert(1, at: .root)
        _ = try tree.insert(2, at: .left(of: root))

        #expect(throws: __TreeBinaryError.cannotRemoveNonLeaf) {
            try tree.remove(at: root)
        }
    }

    @Test("Remove subtree")
    func removeSubtree() throws {
        var tree = Tree.Binary<Int>()
        let root = try tree.insert(1, at: .root)
        let left = try tree.insert(2, at: .left(of: root))
        _ = try tree.insert(4, at: .left(of: left))
        _ = try tree.insert(5, at: .right(of: left))
        _ = try tree.insert(3, at: .right(of: root))

        #expect(tree.count == 5)

        try tree.removeSubtree(at: left)
        #expect(tree.count == 2)
        #expect(tree.left(of: root) == nil)
    }

    @Test("Clear tree")
    func clearTree() throws {
        var tree = Tree.Binary<Int>()
        let root = try tree.insert(1, at: .root)
        _ = try tree.insert(2, at: .left(of: root))
        _ = try tree.insert(3, at: .right(of: root))

        tree.clear()
        #expect(tree.isEmpty)
        #expect(tree.count == 0)
        #expect(tree.root == nil)
    }

    @Test("Pre-order traversal")
    func preOrderTraversal() throws {
        var tree = Tree.Binary<Int>()
        let root = try tree.insert(1, at: .root)
        let left = try tree.insert(2, at: .left(of: root))
        let right = try tree.insert(3, at: .right(of: root))
        _ = try tree.insert(4, at: .left(of: left))
        _ = try tree.insert(5, at: .right(of: left))

        var result: [Int] = []
        tree.forEachPreOrder { result.append($0) }
        #expect(result == [1, 2, 4, 5, 3])
    }

    @Test("In-order traversal")
    func inOrderTraversal() throws {
        var tree = Tree.Binary<Int>()
        let root = try tree.insert(1, at: .root)
        let left = try tree.insert(2, at: .left(of: root))
        let right = try tree.insert(3, at: .right(of: root))
        _ = try tree.insert(4, at: .left(of: left))
        _ = try tree.insert(5, at: .right(of: left))

        var result: [Int] = []
        tree.forEachInOrder { result.append($0) }
        #expect(result == [4, 2, 5, 1, 3])
    }

    @Test("Post-order traversal")
    func postOrderTraversal() throws {
        var tree = Tree.Binary<Int>()
        let root = try tree.insert(1, at: .root)
        let left = try tree.insert(2, at: .left(of: root))
        let right = try tree.insert(3, at: .right(of: root))
        _ = try tree.insert(4, at: .left(of: left))
        _ = try tree.insert(5, at: .right(of: left))

        var result: [Int] = []
        tree.forEachPostOrder { result.append($0) }
        #expect(result == [4, 5, 2, 3, 1])
    }

    @Test("Level-order traversal")
    func levelOrderTraversal() throws {
        var tree = Tree.Binary<Int>()
        let root = try tree.insert(1, at: .root)
        let left = try tree.insert(2, at: .left(of: root))
        let right = try tree.insert(3, at: .right(of: root))
        _ = try tree.insert(4, at: .left(of: left))
        _ = try tree.insert(5, at: .right(of: left))

        var result: [Int] = []
        tree.forEachLevelOrder { result.append($0) }
        #expect(result == [1, 2, 3, 4, 5])
    }

    @Test("Traversal sequences")
    func traversalSequences() throws {
        var tree = Tree.Binary<Int>()
        let root = try tree.insert(1, at: .root)
        let left = try tree.insert(2, at: .left(of: root))
        _ = try tree.insert(3, at: .right(of: root))
        _ = try tree.insert(4, at: .left(of: left))
        _ = try tree.insert(5, at: .right(of: left))

        #expect(Array(tree.preOrder) == [1, 2, 4, 5, 3])
        #expect(Array(tree.inOrder) == [4, 2, 5, 1, 3])
        #expect(Array(tree.postOrder) == [4, 5, 2, 3, 1])
        #expect(Array(tree.levelOrder) == [1, 2, 3, 4, 5])
    }

    @Test("Height calculation")
    func heightCalculation() throws {
        var tree = Tree.Binary<Int>()
        #expect(tree.height == -1)

        let root = try tree.insert(1, at: .root)
        #expect(tree.height == 0)

        let left = try tree.insert(2, at: .left(of: root))
        #expect(tree.height == 1)

        _ = try tree.insert(4, at: .left(of: left))
        #expect(tree.height == 2)
    }

    @Test("Capacity growth")
    func capacityGrowth() throws {
        var tree = Tree.Binary<Int>()

        // Build a complete binary tree with 15 nodes
        var positions: [Tree.Binary<Int>.Position] = []
        positions.append(try tree.insert(1, at: .root))

        for i in 0..<7 {
            if i * 2 + 1 < 15 {
                positions.append(try tree.insert(i * 2 + 2, at: .left(of: positions[i])))
            }
            if i * 2 + 2 < 15 {
                positions.append(try tree.insert(i * 2 + 3, at: .right(of: positions[i])))
            }
        }

        #expect(tree.count == 15)
    }
}

// MARK: - Tree.Binary.Bounded Tests

@Suite("Tree.Binary.Bounded")
struct TreeBinaryBoundedTests {

    @Test("Bounded initialization")
    func boundedInit() throws {
        let tree = try Tree.Binary<Int>.Bounded(capacity: 10)
        #expect(tree.isEmpty)
        #expect(tree.count == 0)
        #expect(tree.capacity == 10)
        #expect(!tree.isFull)
    }

    @Test("Bounded insert and overflow")
    func boundedOverflow() throws {
        var tree = try Tree.Binary<Int>.Bounded(capacity: 3)

        let root = try tree.insert(1, at: .root)
        _ = try tree.insert(2, at: .left(of: root))
        _ = try tree.insert(3, at: .right(of: root))

        #expect(tree.isFull)
        #expect(tree.count == 3)

        #expect(throws: __TreeBinaryBoundedError.overflow) {
            try tree.insert(4, at: .left(of: tree.left(of: root)!))
        }
    }

    @Test("Bounded negative capacity")
    func boundedNegativeCapacity() {
        #expect(throws: __TreeBinaryBoundedError.invalidCapacity) {
            _ = try Tree.Binary<Int>.Bounded(capacity: -1)
        }
    }

    @Test("Bounded traversal")
    func boundedTraversal() throws {
        var tree = try Tree.Binary<Int>.Bounded(capacity: 5)
        let root = try tree.insert(1, at: .root)
        let left = try tree.insert(2, at: .left(of: root))
        _ = try tree.insert(3, at: .right(of: root))
        _ = try tree.insert(4, at: .left(of: left))
        _ = try tree.insert(5, at: .right(of: left))

        #expect(Array(tree.preOrder) == [1, 2, 4, 5, 3])
        #expect(Array(tree.inOrder) == [4, 2, 5, 1, 3])
    }
}

// MARK: - Tree.Binary.Inline Tests

@Suite("Tree.Binary.Inline")
struct TreeBinaryInlineTests {

    @Test("Inline initialization")
    func inlineInit() {
        let tree = Tree.Binary<Int>.Inline<8>()
        #expect(tree.isEmpty)
        #expect(tree.count == 0)
        #expect(!tree.isFull)
    }

    @Test("Inline insert")
    func inlineInsert() throws {
        var tree = Tree.Binary<Int>.Inline<8>()
        let root = try tree.insert(1, at: .root)
        let left = try tree.insert(2, at: .left(of: root))
        _ = try tree.insert(3, at: .right(of: root))

        #expect(tree.count == 3)
        #expect(tree.peek(at: root) == 1)
        #expect(tree.peek(at: left) == 2)
    }

    @Test("Inline overflow")
    func inlineOverflow() throws {
        var tree = Tree.Binary<Int>.Inline<3>()
        let root = try tree.insert(1, at: .root)
        let left = try tree.insert(2, at: .left(of: root))
        _ = try tree.insert(3, at: .right(of: root))

        #expect(tree.isFull)

        #expect(throws: __TreeBinaryInlineError.overflow) {
            try tree.insert(4, at: .left(of: left))
        }
    }

    @Test("Inline traversal")
    func inlineTraversal() throws {
        var tree = Tree.Binary<Int>.Inline<8>()
        let root = try tree.insert(1, at: .root)
        let left = try tree.insert(2, at: .left(of: root))
        _ = try tree.insert(3, at: .right(of: root))
        _ = try tree.insert(4, at: .left(of: left))

        var result: [Int] = []
        tree.forEachInOrder { result.append($0) }
        #expect(result == [4, 2, 1, 3])
    }
}

// MARK: - Tree.Binary.Small Tests

@Suite("Tree.Binary.Small")
struct TreeBinarySmallTests {

    @Test("Small initialization")
    func smallInit() {
        let tree = Tree.Binary<Int>.Small<4>()
        #expect(tree.isEmpty)
        #expect(tree.count == 0)
        #expect(!tree.isSpilled)
    }

    @Test("Small inline storage")
    func smallInline() throws {
        var tree = Tree.Binary<Int>.Small<4>()
        let root = try tree.insert(1, at: .root)
        _ = try tree.insert(2, at: .left(of: root))
        _ = try tree.insert(3, at: .right(of: root))

        #expect(tree.count == 3)
        #expect(!tree.isSpilled)
    }

    @Test("Small spill to heap")
    func smallSpill() throws {
        var tree = Tree.Binary<Int>.Small<3>()
        let root = try tree.insert(1, at: .root)
        let left = try tree.insert(2, at: .left(of: root))
        _ = try tree.insert(3, at: .right(of: root))

        #expect(!tree.isSpilled)

        _ = try tree.insert(4, at: .left(of: left))

        #expect(tree.isSpilled)
        #expect(tree.count == 4)
    }

    @Test("Small traversal after spill")
    func smallTraversalAfterSpill() throws {
        var tree = Tree.Binary<Int>.Small<2>()
        let root = try tree.insert(1, at: .root)
        let left = try tree.insert(2, at: .left(of: root))

        // Spill
        _ = try tree.insert(3, at: .right(of: root))
        _ = try tree.insert(4, at: .left(of: left))

        #expect(tree.isSpilled)

        var result: [Int] = []
        tree.forEachInOrder { result.append($0) }
        #expect(result == [4, 2, 1, 3])
    }
}

// MARK: - NonCopyable Tests

@Suite("Tree.Binary.NonCopyable")
struct TreeBinaryNonCopyableTests {

    /// A move-only token for testing ~Copyable support.
    struct Token: ~Copyable {
        let value: Int
        let tracker: DeinitTracker

        init(_ value: Int, tracker: DeinitTracker) {
            self.value = value
            self.tracker = tracker
        }

        deinit {
            tracker.record(value)
        }
    }

    /// Tracks deinit order.
    final class DeinitTracker: Sendable {
        private let _order: Mutex<[Int]> = Mutex([])

        func record(_ value: Int) {
            _order.withLock { $0.append(value) }
        }

        var order: [Int] {
            _order.withLock { $0 }
        }
    }

    @Test("NonCopyable insert and peek")
    func nonCopyableInsertAndPeek() throws {
        let tracker = DeinitTracker()
        var tree = Tree.Binary<Token>()

        let root = try tree.insert(Token(1, tracker: tracker), at: .root)
        _ = try tree.insert(Token(2, tracker: tracker), at: .left(of: root))

        #expect(tree.count == 2)

        tree.peek(at: root) { token in
            #expect(token.value == 1)
        }
    }

    @Test("NonCopyable deinit order - post-order")
    func nonCopyableDeinitOrder() throws {
        let tracker = DeinitTracker()

        do {
            var tree = Tree.Binary<Token>()
            let root = try tree.insert(Token(1, tracker: tracker), at: .root)
            let left = try tree.insert(Token(2, tracker: tracker), at: .left(of: root))
            _ = try tree.insert(Token(3, tracker: tracker), at: .right(of: root))
            _ = try tree.insert(Token(4, tracker: tracker), at: .left(of: left))
            _ = try tree.insert(Token(5, tracker: tracker), at: .right(of: left))
        }

        // Post-order: 4, 5, 2, 3, 1
        #expect(tracker.order == [4, 5, 2, 3, 1])
    }

    @Test("NonCopyable forEach")
    func nonCopyableForEach() throws {
        let tracker = DeinitTracker()
        var tree = Tree.Binary<Token>()

        let root = try tree.insert(Token(1, tracker: tracker), at: .root)
        _ = try tree.insert(Token(2, tracker: tracker), at: .left(of: root))
        _ = try tree.insert(Token(3, tracker: tracker), at: .right(of: root))

        var values: [Int] = []
        tree.forEachPreOrder { token in
            values.append(token.value)
        }
        #expect(values == [1, 2, 3])
    }
}

// MARK: - Conditional Copyable Tests

@Suite("Tree.Binary.ConditionalCopyable")
struct TreeBinaryConditionalCopyableTests {

    @Test("Copyable when element is Copyable")
    func copyableWhenElementCopyable() throws {
        var tree1 = Tree.Binary<Int>()
        let root = try tree1.insert(1, at: .root)
        _ = try tree1.insert(2, at: .left(of: root))

        // This should compile - tree is Copyable
        let tree2 = tree1

        #expect(tree1.count == tree2.count)
    }

    @Test("Copy-on-write behavior")
    func copyOnWrite() throws {
        var tree1 = Tree.Binary<Int>()
        let root = try tree1.insert(1, at: .root)
        _ = try tree1.insert(2, at: .left(of: root))

        var tree2 = tree1

        // Mutate tree2
        _ = try tree2.insert(3, at: .right(of: tree2.root!))

        // tree1 should be unchanged
        #expect(tree1.count == 2)
        #expect(tree2.count == 3)
    }
}

// MARK: - Sendable Tests

@Suite("Tree.Binary.Sendable")
struct TreeBinarySendableTests {

    func requireSendable<T: Sendable>(_: T) {}

    @Test("Sendable when element is Sendable")
    func sendableWhenElementSendable() throws {
        var tree = Tree.Binary<Int>()
        let root = try tree.insert(42, at: .root)
        _ = try tree.insert(1, at: .left(of: root))

        requireSendable(tree)
    }

    @Test("Sendable bounded")
    func sendableBounded() throws {
        var tree = try Tree.Binary<Int>.Bounded(capacity: 10)
        _ = try tree.insert(42, at: .root)

        requireSendable(tree)
    }

    @Test("Sendable inline")
    func sendableInline() throws {
        var tree = Tree.Binary<Int>.Inline<8>()
        _ = try tree.insert(42, at: .root)

        requireSendable(tree)
    }

    @Test("Sendable small")
    func sendableSmall() throws {
        var tree = Tree.Binary<Int>.Small<4>()
        _ = try tree.insert(42, at: .root)

        requireSendable(tree)
    }
}

// MARK: - Mutex helper for thread-safe tracking

final class Mutex<Value>: @unchecked Sendable {
    private var _value: Value
    private let lock = NSLock()

    init(_ value: Value) {
        self._value = value
    }

    func withLock<R>(_ body: (inout Value) throws -> R) rethrows -> R {
        lock.lock()
        defer { lock.unlock() }
        return try body(&_value)
    }
}
