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
import Tree_Primitives_Test_Support

@testable import Tree_Primitives

// MARK: - Test Suite Structure

@Suite("Tree.Binary.Builder")
struct TreeBinaryBuilderTests {
    @Suite struct Unit {}
    @Suite struct EdgeCase {}
    @Suite struct Integration {}
    @Suite struct LevelOrder {}
    @Suite struct StaticMethods {}
}

// MARK: - Helpers

extension TreeBinaryBuilderTests {
    /// Collect elements via in-order traversal (Left, Root, Right).
    fileprivate static func inOrder(
        _ tree: borrowing Tree<Int>.Binary
    ) -> [Int] {
        var result: [Int] = []
        tree.forEachInOrder { result.append($0) }
        return result
    }

    /// Collect elements via pre-order traversal (Root, Left, Right).
    fileprivate static func preOrder(
        _ tree: borrowing Tree<Int>.Binary
    ) -> [Int] {
        var result: [Int] = []
        tree.forEachPreOrder { result.append($0) }
        return result
    }
}

// MARK: - Level Order Construction

extension TreeBinaryBuilderTests.LevelOrder {

    @Test
    func `Single element makes root`() {
        let tree = Tree<Int>.Binary { 1 }
        #expect(tree.count == 1)
    }

    @Test
    func `Three elements form root with two children`() {
        let tree = Tree<Int>.Binary {
            1
            2
            3
        }
        // In-order traversal: left, root, right = 2, 1, 3
        #expect(TreeBinaryBuilderTests.inOrder(tree) == [2, 1, 3])
        // Pre-order traversal: root, left, right = 1, 2, 3
        #expect(TreeBinaryBuilderTests.preOrder(tree) == [1, 2, 3])
    }

    @Test
    func `Seven elements form complete tree`() {
        // Layout:
        //         1
        //       /   \
        //      2     3
        //     / \   / \
        //    4   5 6   7
        let tree = Tree<Int>.Binary {
            1
            2
            3
            4
            5
            6
            7
        }
        // In-order: 4, 2, 5, 1, 6, 3, 7
        #expect(TreeBinaryBuilderTests.inOrder(tree) == [4, 2, 5, 1, 6, 3, 7])
        // Pre-order: 1, 2, 4, 5, 3, 6, 7
        #expect(TreeBinaryBuilderTests.preOrder(tree) == [1, 2, 4, 5, 3, 6, 7])
    }
}

// MARK: - Unit Tests

extension TreeBinaryBuilderTests.Unit {

    @Test
    func `Empty block produces empty tree`() {
        let tree = Tree<Int>.Binary {}
        #expect(tree.isEmpty)
    }

    @Test
    func `Optional element - some`() {
        let value: Int? = 42
        let tree = Tree<Int>.Binary { value }
        #expect(tree.count == 1)
    }

    @Test
    func `Optional element - none produces empty tree`() {
        let value: Int? = nil
        let tree = Tree<Int>.Binary { value }
        #expect(tree.isEmpty)
    }

    @Test
    func `Two elements - root with left child only`() {
        let tree = Tree<Int>.Binary {
            10
            20
        }
        #expect(tree.count == 2)
        // Pre-order: root, left = 10, 20
        #expect(TreeBinaryBuilderTests.preOrder(tree) == [10, 20])
    }
}

// MARK: - Control Flow

extension TreeBinaryBuilderTests.Unit {

    @Test
    func `Conditional include adds to layout`() {
        let include = true
        let tree = Tree<Int>.Binary {
            1
            2
            if include {
                3
            }
        }
        #expect(tree.count == 3)
    }

    @Test
    func `Conditional exclude reduces layout`() {
        let include = false
        let tree = Tree<Int>.Binary {
            1
            2
            if include {
                3
            }
        }
        #expect(tree.count == 2)
    }

    @Test
    func `For loop builds wide tree`() {
        let tree = Tree<Int>.Binary {
            for i in 1...7 {
                i
            }
        }
        #expect(tree.count == 7)
    }
}

// MARK: - Edge Cases

extension TreeBinaryBuilderTests.EdgeCase {

    @Test
    func `Many elements`() {
        let tree = Tree<Int>.Binary {
            for i in 0..<31 {
                i
            }
        }
        #expect(tree.count == 31)
    }

    @Test
    func `Mixed with Optional none entries`() {
        let none: Int? = nil
        let some: Int? = 99
        let tree = Tree<Int>.Binary {
            1
            none
            some
        }
        // none doesn't contribute; some becomes the second slot
        #expect(tree.count == 2)
    }
}

// MARK: - Integration

extension TreeBinaryBuilderTests.Integration {

    @Test
    func `Builder result accepts further inserts via imperative API`() throws {
        var tree = Tree<Int>.Binary {
            1
            2
            3
        }
        // Find root and add a left-child to node 2 (which is at .left(of: root))
        let root = tree.root!
        let leftOfRoot = tree.child(of: root, slot: .left)!
        try tree.insert(99, at: .left(of: leftOfRoot))
        #expect(tree.count == 4)
    }
}

// MARK: - Static Method Tests

extension TreeBinaryBuilderTests.StaticMethods {

    @Test
    func `buildExpression single element`() {
        let result = Tree<Int>.N<2>.Builder.buildExpression(42)
        #expect(result == [42])
    }

    @Test
    func `buildExpression array`() {
        let result = Tree<Int>.N<2>.Builder.buildExpression([1, 2, 3])
        #expect(result == [1, 2, 3])
    }

    @Test
    func `buildPartialBlock accumulated`() {
        let result = Tree<Int>.N<2>.Builder.buildPartialBlock(
            accumulated: [1, 2],
            next: [3, 4]
        )
        #expect(result == [1, 2, 3, 4])
    }

    @Test
    func `buildArray flattens components`() {
        let result = Tree<Int>.N<2>.Builder.buildArray([[1, 2], [3]])
        #expect(result == [1, 2, 3])
    }
}
