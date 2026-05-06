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

@Suite("Tree.N<2>.Nested.Builder")
struct TreeBinaryNestedBuilderTests {
    @Suite struct Unit {}
    @Suite struct EdgeCase {}
    @Suite struct Sparse {}
    @Suite struct DepthCoverage {}
    @Suite struct StaticMethods {}
}

// MARK: - Aliases (ergonomic test syntax)

private typealias BNode = Tree<Int>.N<2>.Nested.Node

// MARK: - Helpers

extension TreeBinaryNestedBuilderTests {
    fileprivate static func preOrder(_ tree: borrowing Tree<Int>.N<2>) -> [Int] {
        var result: [Int] = []
        tree.forEachPreOrder { result.append($0) }
        return result
    }

    fileprivate static func inOrder(_ tree: borrowing Tree<Int>.N<2>) -> [Int] {
        var result: [Int] = []
        tree.forEachInOrder { result.append($0) }
        return result
    }
}

// MARK: - Unit Tests

extension TreeBinaryNestedBuilderTests.Unit {

    // Note: empty-body case is handled by Round-1 flat-BFS builder
    // (Tree<Int>.N<2> { } with no Element expression). The nested-DSL
    // builder requires at least one Node expression to disambiguate from
    // the Round-1 overload via Swift's type inference.

    @Test
    func `Single leaf node`() {
        let tree = Tree<Int>.N<2> {
            BNode(42)
        }
        #expect(tree.count == 1)
        #expect(TreeBinaryNestedBuilderTests.preOrder(tree) == [42])
    }

    @Test
    func `Root with both children`() {
        let tree = Tree<Int>.N<2> {
            BNode(1) {
                BNode(2)
                BNode(3)
            }
        }
        // Pre-order: root, left, right = [1, 2, 3]
        #expect(TreeBinaryNestedBuilderTests.preOrder(tree) == [1, 2, 3])
        // In-order: left, root, right = [2, 1, 3]
        #expect(TreeBinaryNestedBuilderTests.inOrder(tree) == [2, 1, 3])
    }

    @Test
    func `Three-level complete tree`() {
        let tree = Tree<Int>.N<2> {
            BNode(1) {
                BNode(2) {
                    BNode(4)
                    BNode(5)
                }
                BNode(3) {
                    BNode(6)
                    BNode(7)
                }
            }
        }
        // Pre-order: 1, 2, 4, 5, 3, 6, 7
        #expect(TreeBinaryNestedBuilderTests.preOrder(tree) == [1, 2, 4, 5, 3, 6, 7])
        // In-order: 4, 2, 5, 1, 6, 3, 7
        #expect(TreeBinaryNestedBuilderTests.inOrder(tree) == [4, 2, 5, 1, 6, 3, 7])
    }
}

// MARK: - Sparse Trees (key advantage of nested over flat-BFS)

extension TreeBinaryNestedBuilderTests.Sparse {

    @Test
    func `Root with left child only`() {
        let tree = Tree<Int>.N<2> {
            BNode(1) {
                BNode(2)
            }
        }
        // Pre-order: 1, 2 (no right child)
        #expect(TreeBinaryNestedBuilderTests.preOrder(tree) == [1, 2])
    }

    @Test
    func `Asymmetric tree - left subtree deeper than right`() {
        let tree = Tree<Int>.N<2> {
            BNode(1) {
                BNode(2) {
                    BNode(4) {
                        BNode(8)
                    }
                }
                BNode(3)
            }
        }
        // Pre-order: 1, 2, 4, 8, 3
        #expect(TreeBinaryNestedBuilderTests.preOrder(tree) == [1, 2, 4, 8, 3])
    }

    @Test
    func `Left-skewed tree (linked-list shape)`() {
        let tree = Tree<Int>.N<2> {
            BNode(1) {
                BNode(2) {
                    BNode(3) {
                        BNode(4)
                    }
                }
            }
        }
        #expect(TreeBinaryNestedBuilderTests.preOrder(tree) == [1, 2, 3, 4])
    }
}

// MARK: - Edge Cases

extension TreeBinaryNestedBuilderTests.EdgeCase {

    @Test
    func `Conditional child include`() {
        let include = true
        let tree = Tree<Int>.N<2> {
            BNode(1) {
                BNode(2)
                if include {
                    BNode(3)
                }
            }
        }
        #expect(TreeBinaryNestedBuilderTests.preOrder(tree) == [1, 2, 3])
    }

    @Test
    func `Conditional child exclude`() {
        let include = false
        let tree = Tree<Int>.N<2> {
            BNode(1) {
                BNode(2)
                if include {
                    BNode(3)
                }
            }
        }
        // Without third Node, tree is root + left only
        #expect(TreeBinaryNestedBuilderTests.preOrder(tree) == [1, 2])
    }

    @Test
    func `If-else child branch`() {
        let condition = true
        let tree = Tree<Int>.N<2> {
            BNode(1) {
                if condition {
                    BNode(10)
                } else {
                    BNode(20)
                }
            }
        }
        #expect(TreeBinaryNestedBuilderTests.preOrder(tree) == [1, 10])
    }
}

// MARK: - Depth Coverage (validate recursion)

extension TreeBinaryNestedBuilderTests.DepthCoverage {

    @Test
    func `Depth 4 tree`() {
        let tree = Tree<Int>.N<2> {
            BNode(1) {
                BNode(2) {
                    BNode(3) {
                        BNode(4) {
                            BNode(5)
                        }
                    }
                }
            }
        }
        #expect(tree.count == 5)
        #expect(TreeBinaryNestedBuilderTests.preOrder(tree) == [1, 2, 3, 4, 5])
    }

    @Test
    func `Balanced depth-3 with 7 nodes`() {
        let tree = Tree<Int>.N<2> {
            BNode(4) {
                BNode(2) {
                    BNode(1)
                    BNode(3)
                }
                BNode(6) {
                    BNode(5)
                    BNode(7)
                }
            }
        }
        // In-order traversal of a BST gives sorted output
        #expect(TreeBinaryNestedBuilderTests.inOrder(tree) == [1, 2, 3, 4, 5, 6, 7])
    }
}

// MARK: - Static Methods

extension TreeBinaryNestedBuilderTests.StaticMethods {

    @Test
    func `buildExpression single Node`() {
        let result = Tree<Int>.N<2>.Nested.Builder.buildExpression(BNode(42))
        #expect(result.count == 1)
        #expect(result[0].element == 42)
    }

    @Test
    func `buildBlock empty`() {
        let result = Tree<Int>.N<2>.Nested.Builder.buildBlock()
        #expect(result.isEmpty)
    }

    @Test
    func `buildPartialBlock accumulated and next`() {
        let acc: [BNode] = [BNode(1)]
        let next: [BNode] = [BNode(2)]
        let result = Tree<Int>.N<2>.Nested.Builder.buildPartialBlock(
            accumulated: acc,
            next: next
        )
        #expect(result.count == 2)
        #expect(result[0].element == 1)
        #expect(result[1].element == 2)
    }

    @Test
    func `buildArray flattens components`() {
        let result = Tree<Int>.N<2>.Nested.Builder.buildArray([
            [BNode(1)],
            [BNode(2), BNode(3)],
        ])
        #expect(result.count == 3)
    }
}
