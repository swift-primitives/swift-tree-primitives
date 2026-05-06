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

@Suite("Tree.Unbounded.Nested.Builder")
struct TreeUnboundedNestedBuilderTests {
    @Suite struct Unit {}
    @Suite struct EdgeCase {}
    @Suite struct DepthCoverage {}
    @Suite struct StaticMethods {}
}

// MARK: - Aliases (ergonomic test syntax)

private typealias UNode = Tree<String>.Unbounded.Nested.Node
private typealias UIntNode = Tree<Int>.Unbounded.Nested.Node

// MARK: - Helpers

extension TreeUnboundedNestedBuilderTests {
    fileprivate static func preOrder(_ tree: borrowing Tree<String>.Unbounded) -> [String] {
        var result: [String] = []
        tree.forEachPreOrder { result.append($0) }
        return result
    }

    fileprivate static func preOrder(_ tree: borrowing Tree<Int>.Unbounded) -> [Int] {
        var result: [Int] = []
        tree.forEachPreOrder { result.append($0) }
        return result
    }
}

// MARK: - Unit Tests

extension TreeUnboundedNestedBuilderTests.Unit {

    @Test
    func `Single leaf node`() {
        let tree = Tree<Int>.Unbounded {
            UIntNode(42)
        }
        #expect(tree.count == 1)
        #expect(TreeUnboundedNestedBuilderTests.preOrder(tree) == [42])
    }

    @Test
    func `Root with three direct children`() {
        let tree = Tree<String>.Unbounded {
            UNode("root") {
                UNode("a")
                UNode("b")
                UNode("c")
            }
        }
        // Pre-order: root, then children in declaration order
        #expect(TreeUnboundedNestedBuilderTests.preOrder(tree) == ["root", "a", "b", "c"])
    }

    @Test
    func `Root with no children equivalent to leaf`() {
        let tree = Tree<String>.Unbounded {
            UNode("alone")
        }
        #expect(TreeUnboundedNestedBuilderTests.preOrder(tree) == ["alone"])
    }

    @Test
    func `Two-level nesting`() {
        let tree = Tree<String>.Unbounded {
            UNode("root") {
                UNode("a") {
                    UNode("a-1")
                    UNode("a-2")
                }
                UNode("b")
            }
        }
        // Pre-order DFS: root, a, a-1, a-2, b
        #expect(
            TreeUnboundedNestedBuilderTests.preOrder(tree)
                == ["root", "a", "a-1", "a-2", "b"]
        )
    }

    @Test
    func `Three-level nesting`() {
        let tree = Tree<Int>.Unbounded {
            UIntNode(1) {
                UIntNode(2) {
                    UIntNode(4) {
                        UIntNode(8)
                    }
                    UIntNode(5)
                }
                UIntNode(3) {
                    UIntNode(6)
                    UIntNode(7)
                }
            }
        }
        // Pre-order DFS: 1, 2, 4, 8, 5, 3, 6, 7
        #expect(
            TreeUnboundedNestedBuilderTests.preOrder(tree)
                == [1, 2, 4, 8, 5, 3, 6, 7]
        )
    }
}

// MARK: - Control Flow

extension TreeUnboundedNestedBuilderTests.EdgeCase {

    @Test
    func `Conditional child include`() {
        let include = true
        let tree = Tree<Int>.Unbounded {
            UIntNode(1) {
                UIntNode(2)
                if include {
                    UIntNode(3)
                }
            }
        }
        #expect(TreeUnboundedNestedBuilderTests.preOrder(tree) == [1, 2, 3])
    }

    @Test
    func `Conditional child exclude`() {
        let include = false
        let tree = Tree<Int>.Unbounded {
            UIntNode(1) {
                UIntNode(2)
                if include {
                    UIntNode(3)
                }
            }
        }
        #expect(TreeUnboundedNestedBuilderTests.preOrder(tree) == [1, 2])
    }

    @Test
    func `For loop generates wide subtree`() {
        let tree = Tree<Int>.Unbounded {
            UIntNode(0) {
                for i in 1...5 {
                    UIntNode(i)
                }
            }
        }
        #expect(TreeUnboundedNestedBuilderTests.preOrder(tree) == [0, 1, 2, 3, 4, 5])
    }

    @Test
    func `Many wide children`() {
        let tree = Tree<Int>.Unbounded {
            UIntNode(0) {
                for i in 1...20 {
                    UIntNode(i)
                }
            }
        }
        #expect(tree.count == 21)
    }

    @Test
    func `Mixed width and depth`() {
        let tree = Tree<Int>.Unbounded {
            UIntNode(1) {
                UIntNode(2) {
                    for i in 5...8 {
                        UIntNode(i)
                    }
                }
                UIntNode(3)
                UIntNode(4)
            }
        }
        // Pre-order: 1, 2, 5, 6, 7, 8, 3, 4
        #expect(TreeUnboundedNestedBuilderTests.preOrder(tree) == [1, 2, 5, 6, 7, 8, 3, 4])
    }
}

// MARK: - Depth Coverage

extension TreeUnboundedNestedBuilderTests.DepthCoverage {

    @Test
    func `Linear chain depth 5`() {
        let tree = Tree<Int>.Unbounded {
            UIntNode(1) {
                UIntNode(2) {
                    UIntNode(3) {
                        UIntNode(4) {
                            UIntNode(5)
                        }
                    }
                }
            }
        }
        #expect(tree.count == 5)
        #expect(TreeUnboundedNestedBuilderTests.preOrder(tree) == [1, 2, 3, 4, 5])
    }

    @Test
    func `Wide branching with mixed depth`() {
        let tree = Tree<Int>.Unbounded {
            UIntNode(1) {
                UIntNode(10)  // leaf
                UIntNode(20) {
                    UIntNode(21) {
                        UIntNode(22)
                    }
                }
                UIntNode(30)  // leaf
            }
        }
        // Pre-order: 1, 10, 20, 21, 22, 30
        #expect(TreeUnboundedNestedBuilderTests.preOrder(tree) == [1, 10, 20, 21, 22, 30])
    }
}

// MARK: - Static Methods

extension TreeUnboundedNestedBuilderTests.StaticMethods {

    @Test
    func `buildExpression single Node`() {
        let result = Tree<Int>.Unbounded.Nested.Builder.buildExpression(UIntNode(42))
        #expect(result.count == 1)
        #expect(result[0].element == 42)
    }

    @Test
    func `buildBlock empty`() {
        let result = Tree<Int>.Unbounded.Nested.Builder.buildBlock()
        #expect(result.isEmpty)
    }

    @Test
    func `buildPartialBlock accumulates Nodes`() {
        let acc: [UIntNode] = [UIntNode(1)]
        let next: [UIntNode] = [UIntNode(2), UIntNode(3)]
        let result = Tree<Int>.Unbounded.Nested.Builder.buildPartialBlock(
            accumulated: acc,
            next: next
        )
        #expect(result.count == 3)
    }

    @Test
    func `buildArray flattens components`() {
        let result = Tree<Int>.Unbounded.Nested.Builder.buildArray([
            [UIntNode(1)],
            [UIntNode(2), UIntNode(3), UIntNode(4)],
        ])
        #expect(result.count == 4)
    }
}
