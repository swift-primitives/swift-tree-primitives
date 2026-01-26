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
import Synchronization
import Array_Primitives
@testable import Tree_Primitives

// MARK: - Test Helpers

/// Collects a sequence of integers into a primitives Array.
private func collect<S: Swift.Sequence<Int>>(_ sequence: S) -> Array<Int> {
    var result = Array<Int>()
    for element in sequence {
        result.append(element)
    }
    return result
}

/// Asserts that a primitives Array contains the expected elements in order.
private func expectEqual(_ array: borrowing Array<Int>, _ expected: Int...) {
    var index = 0
    array.forEach { element in
        guard index < expected.count else {
            Issue.record("Array has more elements than expected")
            return
        }
        #expect(element == expected[index])
        index += 1
    }
    #expect(index == expected.count, "Array has \(index) elements, expected \(expected.count)")
}

// MARK: - Tree.N<2> Tests (Binary Trees)

@Suite("Tree.N<2>")
struct TreeNBinaryTests {

    @Test("Empty tree")
    func emptyTree() {
        let tree = Tree.N<Int, 2>()
        #expect(tree.isEmpty)
        #expect(tree.count == 0)
        #expect(tree.root == nil)
        #expect(tree.height == -1)
    }

    @Test("Insert root")
    func insertRoot() throws {
        var tree = Tree.N<Int, 2>()
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
        var tree = Tree.N<Int, 2>()
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
        var tree = Tree.N<Int, 2>()
        _ = try tree.insert(1, at: .root)

        #expect(throws: __TreeNError.slotOccupied) {
            try tree.insert(2, at: .root)
        }
    }

    @Test("Insert throws on occupied child")
    func insertThrowsOnOccupiedChild() throws {
        var tree = Tree.N<Int, 2>()
        let root = try tree.insert(1, at: .root)
        _ = try tree.insert(2, at: .left(of: root))

        #expect(throws: __TreeNError.slotOccupied) {
            try tree.insert(3, at: .left(of: root))
        }
    }

    @Test("Remove leaf")
    func removeLeaf() throws {
        var tree = Tree.N<Int, 2>()
        let root = try tree.insert(1, at: .root)
        let left = try tree.insert(2, at: .left(of: root))

        let removed = try tree.remove(at: left)
        #expect(removed == 2)
        #expect(tree.count == 1)
        #expect(tree.left(of: root) == nil)
    }

    @Test("Remove throws on non-leaf")
    func removeThrowsOnNonLeaf() throws {
        var tree = Tree.N<Int, 2>()
        let root = try tree.insert(1, at: .root)
        _ = try tree.insert(2, at: .left(of: root))

        #expect(throws: __TreeNError.cannotRemoveNonLeaf) {
            try tree.remove(at: root)
        }
    }

    @Test("Remove subtree")
    func removeSubtree() throws {
        var tree = Tree.N<Int, 2>()
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
        var tree = Tree.N<Int, 2>()
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
        var tree = Tree.N<Int, 2>()
        let root = try tree.insert(1, at: .root)
        let left = try tree.insert(2, at: .left(of: root))
        _ = try tree.insert(3, at: .right(of: root))
        _ = try tree.insert(4, at: .left(of: left))
        _ = try tree.insert(5, at: .right(of: left))

        var result = Array<Int>()
        tree.forEachPreOrder { result.append($0) }
        expectEqual(result, 1, 2, 4, 5, 3)
    }

    @Test("In-order traversal")
    func inOrderTraversal() throws {
        var tree = Tree.N<Int, 2>()
        let root = try tree.insert(1, at: .root)
        let left = try tree.insert(2, at: .left(of: root))
        _ = try tree.insert(3, at: .right(of: root))
        _ = try tree.insert(4, at: .left(of: left))
        _ = try tree.insert(5, at: .right(of: left))

        var result = Array<Int>()
        tree.forEachInOrder { result.append($0) }
        expectEqual(result, 4, 2, 5, 1, 3)
    }

    @Test("Post-order traversal")
    func postOrderTraversal() throws {
        var tree = Tree.N<Int, 2>()
        let root = try tree.insert(1, at: .root)
        let left = try tree.insert(2, at: .left(of: root))
        _ = try tree.insert(3, at: .right(of: root))
        _ = try tree.insert(4, at: .left(of: left))
        _ = try tree.insert(5, at: .right(of: left))

        var result = Array<Int>()
        tree.forEachPostOrder { result.append($0) }
        expectEqual(result, 4, 5, 2, 3, 1)
    }

    @Test("Level-order traversal")
    func levelOrderTraversal() throws {
        var tree = Tree.N<Int, 2>()
        let root = try tree.insert(1, at: .root)
        let left = try tree.insert(2, at: .left(of: root))
        _ = try tree.insert(3, at: .right(of: root))
        _ = try tree.insert(4, at: .left(of: left))
        _ = try tree.insert(5, at: .right(of: left))

        var result = Array<Int>()
        tree.forEachLevelOrder { result.append($0) }
        expectEqual(result, 1, 2, 3, 4, 5)
    }

    @Test("Traversal sequences")
    func traversalSequences() throws {
        var tree = Tree.N<Int, 2>()
        let root = try tree.insert(1, at: .root)
        let left = try tree.insert(2, at: .left(of: root))
        _ = try tree.insert(3, at: .right(of: root))
        _ = try tree.insert(4, at: .left(of: left))
        _ = try tree.insert(5, at: .right(of: left))

        expectEqual(collect(tree.preOrder), 1, 2, 4, 5, 3)
        expectEqual(collect(tree.inOrder), 4, 2, 5, 1, 3)
        expectEqual(collect(tree.postOrder), 4, 5, 2, 3, 1)
        expectEqual(collect(tree.levelOrder), 1, 2, 3, 4, 5)
    }

    @Test("Height calculation")
    func heightCalculation() throws {
        var tree = Tree.N<Int, 2>()
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
        var tree = Tree.N<Int, 2>()

        // Build a complete binary tree with 15 nodes
        var positions: [Tree.Position] = []
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

// MARK: - Tree.N<2>.Bounded Tests

@Suite("Tree.N<2>.Bounded")
struct TreeNBoundedTests {

    @Test("Bounded initialization")
    func boundedInit() throws {
        let tree = try Tree.N<Int, 2>.Bounded(capacity: 10)
        #expect(tree.isEmpty)
        #expect(tree.count == 0)
        #expect(tree.capacity == 10)
        #expect(!tree.isFull)
    }

    @Test("Bounded insert and overflow")
    func boundedOverflow() throws {
        var tree = try Tree.N<Int, 2>.Bounded(capacity: 3)

        let root = try tree.insert(1, at: .root)
        _ = try tree.insert(2, at: .left(of: root))
        _ = try tree.insert(3, at: .right(of: root))

        #expect(tree.isFull)
        #expect(tree.count == 3)

        #expect(throws: __TreeNBoundedError.overflow) {
            try tree.insert(4, at: .left(of: tree.left(of: root)!))
        }
    }

    @Test("Bounded negative capacity")
    func boundedNegativeCapacity() {
        #expect(throws: __TreeNBoundedError.invalidCapacity) {
            _ = try Tree.N<Int, 2>.Bounded(capacity: -1)
        }
    }

    @Test("Bounded traversal")
    func boundedTraversal() throws {
        var tree = try Tree.N<Int, 2>.Bounded(capacity: 5)
        let root = try tree.insert(1, at: .root)
        let left = try tree.insert(2, at: .left(of: root))
        _ = try tree.insert(3, at: .right(of: root))
        _ = try tree.insert(4, at: .left(of: left))
        _ = try tree.insert(5, at: .right(of: left))

        expectEqual(collect(tree.preOrder), 1, 2, 4, 5, 3)
        expectEqual(collect(tree.inOrder), 4, 2, 5, 1, 3)
    }
}

// MARK: - Tree.N<2>.Inline Tests

@Suite("Tree.N<2>.Inline")
struct TreeNInlineTests {

    @Test("Inline initialization")
    func inlineInit() throws {
        var tree = try Tree.N<Int, 2>.Inline<8>()
        // Cannot use #expect on ~Copyable types, use assertions
        assert(tree.isEmpty)
        assert(tree.count == 0)
        assert(!tree.isFull)
    }

    @Test("Inline insert")
    func inlineInsert() throws {
        var tree = try Tree.N<Int, 2>.Inline<8>()
        let root = try tree.insert(1, at: .root)
        let left = try tree.insert(2, at: .left(of: root))
        _ = try tree.insert(3, at: .right(of: root))

        let count = tree.count
        #expect(count == 3)

        let rootValue = tree.peek(at: root)
        #expect(rootValue == 1)

        let leftValue = tree.peek(at: left)
        #expect(leftValue == 2)
    }

    @Test("Inline overflow")
    func inlineOverflow() throws {
        var tree = try Tree.N<Int, 2>.Inline<3>()
        let root = try tree.insert(1, at: .root)
        let left = try tree.insert(2, at: .left(of: root))
        _ = try tree.insert(3, at: .right(of: root))

        let isFull = tree.isFull
        #expect(isFull)

        #expect(throws: __TreeNInlineError.overflow) {
            try tree.insert(4, at: .left(of: left))
        }
    }

    @Test("Inline traversal")
    func inlineTraversal() throws {
        var tree = try Tree.N<Int, 2>.Inline<8>()
        let root = try tree.insert(1, at: .root)
        let left = try tree.insert(2, at: .left(of: root))
        _ = try tree.insert(3, at: .right(of: root))
        _ = try tree.insert(4, at: .left(of: left))

        var result = Array<Int>()
        tree.forEachInOrder { result.append($0) }
        expectEqual(result, 4, 2, 1, 3)
    }

    @Test("Inline remove and reuse")
    func inlineRemoveAndReuse() throws {
        var tree = try Tree.N<Int, 2>.Inline<4>()
        let root = try tree.insert(1, at: .root)
        let left = try tree.insert(2, at: .left(of: root))
        _ = try tree.insert(3, at: .right(of: root))

        // Remove left leaf
        let removed = try tree.remove(at: left)
        #expect(removed == 2)

        let countAfterRemove = tree.count
        #expect(countAfterRemove == 2)

        // Insert new left child - should reuse slot
        let newLeft = try tree.insert(4, at: .left(of: root))
        let newLeftValue = tree.peek(at: newLeft)
        #expect(newLeftValue == 4)
    }
}

// MARK: - Tree.N<2>.Small Tests

@Suite("Tree.N<2>.Small")
struct TreeNSmallTests {

    @Test("Small initialization")
    func smallInit() throws {
        var tree = try Tree.N<Int, 2>.Small<4>()
        // Cannot use #expect on ~Copyable types, use assertions
        assert(tree.isEmpty)
        assert(tree.count == 0)
        assert(!tree.isSpilled)
    }

    @Test("Small inline storage")
    func smallInline() throws {
        var tree = try Tree.N<Int, 2>.Small<4>()
        let root = try tree.insert(1, at: .root)
        _ = try tree.insert(2, at: .left(of: root))
        _ = try tree.insert(3, at: .right(of: root))

        let count = tree.count
        #expect(count == 3)

        let isSpilled = tree.isSpilled
        #expect(!isSpilled)
    }

    @Test("Small spill to heap")
    func smallSpill() throws {
        var tree = try Tree.N<Int, 2>.Small<3>()
        let root = try tree.insert(1, at: .root)
        let left = try tree.insert(2, at: .left(of: root))
        _ = try tree.insert(3, at: .right(of: root))

        let beforeSpill = tree.isSpilled
        #expect(!beforeSpill)

        _ = try tree.insert(4, at: .left(of: left))

        let afterSpill = tree.isSpilled
        #expect(afterSpill)

        let count = tree.count
        #expect(count == 4)
    }

    @Test("Small traversal after spill")
    func smallTraversalAfterSpill() throws {
        var tree = try Tree.N<Int, 2>.Small<2>()
        let root = try tree.insert(1, at: .root)
        let left = try tree.insert(2, at: .left(of: root))

        // Spill
        _ = try tree.insert(3, at: .right(of: root))
        _ = try tree.insert(4, at: .left(of: left))

        let isSpilled = tree.isSpilled
        #expect(isSpilled)

        var result = Array<Int>()
        tree.forEachInOrder { result.append($0) }
        expectEqual(result, 4, 2, 1, 3)
    }
}

// MARK: - NonCopyable Tests

@Suite("Tree.N<2>.NonCopyable")
struct TreeNNonCopyableTests {

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

    /// Tracks deinit order using Synchronization framework.
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
        var tree = Tree.N<Token, 2>()

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
            var tree = Tree.N<Token, 2>()
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
        var tree = Tree.N<Token, 2>()

        let root = try tree.insert(Token(1, tracker: tracker), at: .root)
        _ = try tree.insert(Token(2, tracker: tracker), at: .left(of: root))
        _ = try tree.insert(Token(3, tracker: tracker), at: .right(of: root))

        var values = Array<Int>()
        tree.forEachPreOrder { token in
            values.append(token.value)
        }
        expectEqual(values, 1, 2, 3)
    }
}

// MARK: - Conditional Copyable Tests

@Suite("Tree.N<2>.ConditionalCopyable")
struct TreeNConditionalCopyableTests {

    @Test("Copyable when element is Copyable")
    func copyableWhenElementCopyable() throws {
        var tree1 = Tree.N<Int, 2>()
        let root = try tree1.insert(1, at: .root)
        _ = try tree1.insert(2, at: .left(of: root))

        // This should compile - tree is Copyable
        let tree2 = tree1

        #expect(tree1.count == tree2.count)
    }

    @Test("Copy-on-write behavior")
    func copyOnWrite() throws {
        var tree1 = Tree.N<Int, 2>()
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

@Suite("Tree.N<2>.Sendable")
struct TreeNSendableTests {

    func requireSendable<T: Sendable & ~Copyable>(_: borrowing T) {}

    @Test("Sendable when element is Sendable")
    func sendableWhenElementSendable() throws {
        var tree = Tree.N<Int, 2>()
        let root = try tree.insert(42, at: .root)
        _ = try tree.insert(1, at: .left(of: root))

        requireSendable(tree)
    }

    @Test("Sendable bounded")
    func sendableBounded() throws {
        var tree = try Tree.N<Int, 2>.Bounded(capacity: 10)
        _ = try tree.insert(42, at: .root)

        requireSendable(tree)
    }

    @Test("Sendable inline")
    func sendableInline() throws {
        var tree = try Tree.N<Int, 2>.Inline<8>()
        _ = try tree.insert(42, at: .root)

        // Inline is ~Copyable but Sendable
        requireSendable(tree)
    }

    @Test("Sendable small")
    func sendableSmall() throws {
        var tree = try Tree.N<Int, 2>.Small<4>()
        _ = try tree.insert(42, at: .root)

        // Small is ~Copyable but Sendable
        requireSendable(tree)
    }
}

// MARK: - Token-Stamped Position Tests

@Suite("Tree.N<2>.StalePosition")
struct TreeNStalePositionTests {

    @Test("Stale position after remove returns nil for navigation")
    func stalePositionAfterRemove() throws {
        var tree = Tree.N<Int, 2>()
        let root = try tree.insert(1, at: .root)
        let left = try tree.insert(2, at: .left(of: root))
        _ = try tree.insert(3, at: .right(of: root))

        // Remove the left node
        _ = try tree.remove(at: left)

        // The stale position should return nil for navigation
        #expect(tree.left(of: left) == nil)
        #expect(tree.right(of: left) == nil)
        #expect(tree.parent(of: left) == nil)
        #expect(tree.isLeaf(left) == false)
        #expect(tree.peek(at: left) == nil)
    }

    @Test("Stale position after remove throws on insert")
    func stalePositionThrowsOnInsert() throws {
        var tree = Tree.N<Int, 2>()
        let root = try tree.insert(1, at: .root)
        let left = try tree.insert(2, at: .left(of: root))
        _ = try tree.insert(3, at: .right(of: root))

        // Remove the left node
        _ = try tree.remove(at: left)

        // Inserting at a stale position should throw
        #expect(throws: __TreeNError.invalidPosition) {
            try tree.insert(4, at: .left(of: left))
        }
        #expect(throws: __TreeNError.invalidPosition) {
            try tree.insert(5, at: .right(of: left))
        }
    }

    @Test("Position remains valid after unrelated inserts")
    func positionValidAfterUnrelatedInserts() throws {
        var tree = Tree.N<Int, 2>()
        let root = try tree.insert(1, at: .root)
        let left = try tree.insert(2, at: .left(of: root))

        // Capture position before more inserts
        let leftPosition = left

        // Insert more nodes elsewhere
        _ = try tree.insert(3, at: .right(of: root))
        _ = try tree.insert(4, at: .left(of: left))
        _ = try tree.insert(5, at: .right(of: left))

        // Original position should still be valid
        #expect(tree.peek(at: leftPosition) == 2)
        #expect(tree.parent(of: leftPosition) == root)
        #expect(tree.left(of: leftPosition) != nil)
        #expect(tree.right(of: leftPosition) != nil)
    }

    @Test("Position remains valid after unrelated removes")
    func positionValidAfterUnrelatedRemoves() throws {
        var tree = Tree.N<Int, 2>()
        let root = try tree.insert(1, at: .root)
        let left = try tree.insert(2, at: .left(of: root))
        let right = try tree.insert(3, at: .right(of: root))
        let leftLeft = try tree.insert(4, at: .left(of: left))
        _ = try tree.insert(5, at: .right(of: left))

        // Remove unrelated nodes
        _ = try tree.remove(at: right)
        _ = try tree.remove(at: leftLeft)

        // Left position should still be valid
        #expect(tree.peek(at: left) == 2)
        #expect(tree.parent(of: left) == root)
    }

    @Test("Position survives CoW copy")
    func positionSurvivesCoW() throws {
        var tree1 = Tree.N<Int, 2>()
        let root = try tree1.insert(1, at: .root)
        let left = try tree1.insert(2, at: .left(of: root))

        // Copy (shared storage)
        var tree2 = tree1

        // Mutate tree2 (triggers CoW)
        _ = try tree2.insert(3, at: .right(of: tree2.root!))

        // Position from tree1 should still work with tree1
        #expect(tree1.peek(at: root) == 1)
        #expect(tree1.peek(at: left) == 2)

        // tree2's root should still be valid
        #expect(tree2.peek(at: tree2.root!) == 1)
    }

    @Test("Position survives growth reallocation")
    func positionSurvivesGrowth() throws {
        var tree = Tree.N<Int, 2>()

        // Build tree and capture positions
        let root = try tree.insert(1, at: .root)
        var positions: [Tree.Position] = [root]

        // Force multiple growths
        for i in 0..<20 {
            let parent = positions[i / 2]
            if i % 2 == 0 && tree.left(of: parent) == nil {
                positions.append(try tree.insert(i + 2, at: .left(of: parent)))
            } else if tree.right(of: parent) == nil {
                positions.append(try tree.insert(i + 2, at: .right(of: parent)))
            }
        }

        // All original positions should still be valid
        #expect(tree.peek(at: root) == 1)
        #expect(tree.peek(at: positions[1]) != nil)
    }

    @Test("Bounded stale position detection")
    func boundedStalePosition() throws {
        var tree = try Tree.N<Int, 2>.Bounded(capacity: 10)
        let root = try tree.insert(1, at: .root)
        let left = try tree.insert(2, at: .left(of: root))

        // Remove left
        _ = try tree.remove(at: left)

        // Stale position should return nil
        #expect(tree.peek(at: left) == nil)
        #expect(tree.left(of: left) == nil)

        // Insert at stale position should throw
        #expect(throws: __TreeNBoundedError.invalidPosition) {
            try tree.insert(3, at: .left(of: left))
        }
    }

    @Test("Inline stale position detection")
    func inlineStalePosition() throws {
        var tree = try Tree.N<Int, 2>.Inline<8>()
        let root = try tree.insert(1, at: .root)
        let left = try tree.insert(2, at: .left(of: root))

        // Remove left
        _ = try tree.remove(at: left)

        // Stale position should return nil
        #expect(tree.peek(at: left) == nil)
        #expect(tree.left(of: left) == nil)

        // Insert at stale position should throw
        #expect(throws: __TreeNInlineError.invalidPosition) {
            try tree.insert(3, at: .left(of: left))
        }
    }

    @Test("Small stale position detection - inline")
    func smallStalePositionInline() throws {
        var tree = try Tree.N<Int, 2>.Small<8>()
        let root = try tree.insert(1, at: .root)
        let left = try tree.insert(2, at: .left(of: root))

        // Remove left (still inline)
        _ = try tree.remove(at: left)

        let isSpilled = tree.isSpilled
        #expect(!isSpilled)

        // Stale position should return nil
        #expect(tree.peek(at: left) == nil)

        // Insert at stale position should throw
        #expect(throws: __TreeNSmallError.invalidPosition) {
            try tree.insert(3, at: .left(of: left))
        }
    }

    @Test("Small stale position detection - after spill")
    func smallStalePositionAfterSpill() throws {
        var tree = try Tree.N<Int, 2>.Small<2>()
        let root = try tree.insert(1, at: .root)
        let left = try tree.insert(2, at: .left(of: root))

        // Force spill
        _ = try tree.insert(3, at: .right(of: root))
        _ = try tree.insert(4, at: .left(of: left))

        let isSpilled = tree.isSpilled
        #expect(isSpilled)

        // Position from before spill should still work
        #expect(tree.peek(at: root) == 1)
        #expect(tree.peek(at: left) == 2)

        // Remove a leaf and check stale detection
        let leftLeft = tree.left(of: left)!
        _ = try tree.remove(at: leftLeft)

        #expect(tree.peek(at: leftLeft) == nil)
    }

    @Test("Removed and reallocated slot invalidates old position")
    func removedSlotReallocationInvalidatesOldPosition() throws {
        var tree = Tree.N<Int, 2>()
        let root = try tree.insert(1, at: .root)
        let left = try tree.insert(2, at: .left(of: root))

        // Remove left
        _ = try tree.remove(at: left)

        // Insert new node - may reuse the slot
        let newLeft = try tree.insert(3, at: .left(of: root))

        // Old position should be invalid (different token)
        #expect(tree.peek(at: left) == nil)

        // New position should be valid
        #expect(tree.peek(at: newLeft) == 3)

        // They may have the same index but different tokens
        #expect(left != newLeft)
    }
}
