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

@Suite("Tree.Unbounded.Builder")
struct TreeUnboundedBuilderTests {
    @Suite struct Unit {}
    @Suite struct EdgeCase {}
    @Suite struct Integration {}
    @Suite struct StaticMethods {}
}

// MARK: - Helpers

extension TreeUnboundedBuilderTests {
    fileprivate static func preOrder(
        _ tree: borrowing Tree<Int>.Unbounded
    ) -> [Int] {
        var result: [Int] = []
        tree.forEachPreOrder { result.append($0) }
        return result
    }
}

// MARK: - Unit Tests

extension TreeUnboundedBuilderTests.Unit {

    @Test
    func `Empty block produces empty tree`() {
        let tree = Tree<Int>.Unbounded {}
        #expect(tree.isEmpty)
    }

    @Test
    func `Single element makes root`() {
        let tree = Tree<Int>.Unbounded { 42 }
        #expect(tree.count == 1)
        #expect(TreeUnboundedBuilderTests.preOrder(tree) == [42])
    }

    @Test
    func `Multiple elements - first is root, rest are children`() {
        let tree = Tree<Int>.Unbounded {
            1
            2
            3
            4
        }
        // Pre-order: root, then children in order = [1, 2, 3, 4]
        #expect(TreeUnboundedBuilderTests.preOrder(tree) == [1, 2, 3, 4])
        #expect(tree.count == 4)
    }

    @Test
    func `Optional element - some`() {
        let value: Int? = 42
        let tree = Tree<Int>.Unbounded { value }
        #expect(tree.count == 1)
    }

    @Test
    func `Optional element - none produces empty tree`() {
        let value: Int? = nil
        let tree = Tree<Int>.Unbounded { value }
        #expect(tree.isEmpty)
    }
}

// MARK: - Control Flow

extension TreeUnboundedBuilderTests.Unit {

    @Test
    func `Conditional include`() {
        let include = true
        let tree = Tree<Int>.Unbounded {
            1
            2
            if include {
                3
            }
        }
        #expect(tree.count == 3)
    }

    @Test
    func `Conditional exclude`() {
        let include = false
        let tree = Tree<Int>.Unbounded {
            1
            2
            if include {
                3
            }
        }
        #expect(tree.count == 2)
    }

    @Test
    func `For loop generates wide tree`() {
        let tree = Tree<Int>.Unbounded {
            0
            for i in 1...5 {
                i
            }
        }
        #expect(tree.count == 6)
        #expect(TreeUnboundedBuilderTests.preOrder(tree) == [0, 1, 2, 3, 4, 5])
    }
}

// MARK: - Edge Cases

extension TreeUnboundedBuilderTests.EdgeCase {

    @Test
    func `Many children`() {
        let tree = Tree<Int>.Unbounded {
            0
            for i in 1..<100 {
                i
            }
        }
        #expect(tree.count == 100)
    }

    @Test
    func `Single root no children`() {
        let tree = Tree<Int>.Unbounded {
            42
        }
        #expect(tree.count == 1)
        let root = tree.root!
        #expect(tree.childCount(of: root) == 0)
    }

    @Test
    func `Mixed Optional none entries`() {
        let none: Int? = nil
        let tree = Tree<Int>.Unbounded {
            1
            none
            2
        }
        // none doesn't contribute
        #expect(tree.count == 2)
    }
}

// MARK: - Integration

extension TreeUnboundedBuilderTests.Integration {

    @Test
    func `Builder result accepts further inserts via imperative API`() throws {
        var tree = Tree<Int>.Unbounded {
            1
            2
            3
        }
        let root = tree.root!
        let firstChild = tree.child(of: root, at: 0)!
        try tree.insert(99, at: .appendChild(of: firstChild))
        #expect(tree.count == 4)
    }

    @Test
    func `Root has expected number of direct children`() {
        let tree = Tree<Int>.Unbounded {
            0
            1
            2
            3
        }
        let root = tree.root!
        #expect(tree.childCount(of: root) == 3)
    }
}

// MARK: - Static Method Tests

extension TreeUnboundedBuilderTests.StaticMethods {

    @Test
    func `buildExpression single element`() {
        let result = Tree<Int>.Unbounded.Builder.buildExpression(42)
        #expect(result == [42])
    }

    @Test
    func `buildExpression array`() {
        let result = Tree<Int>.Unbounded.Builder.buildExpression([1, 2, 3])
        #expect(result == [1, 2, 3])
    }

    @Test
    func `buildPartialBlock accumulated`() {
        let result = Tree<Int>.Unbounded.Builder.buildPartialBlock(
            accumulated: [1, 2],
            next: [3, 4]
        )
        #expect(result == [1, 2, 3, 4])
    }

    @Test
    func `buildArray flattens components`() {
        let result = Tree<Int>.Unbounded.Builder.buildArray([[1, 2], [3]])
        #expect(result == [1, 2, 3])
    }
}
