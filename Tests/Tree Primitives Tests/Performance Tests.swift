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

// MARK: - Performance Tests

@Suite("Tree.Binary.Performance")
struct TreeBinaryPerformanceTests {

    // MARK: - Insert Performance

    @Test("Insert 10,000 nodes")
    func insertTenThousand() throws {
        var tree = Tree.Binary<Int>()
        var positions: [Tree.Binary<Int>.Position] = []
        positions.reserveCapacity(10_000)

        // Insert root
        positions.append(try tree.insert(0, at: .root))

        // Build complete binary tree
        for i in 1..<10_000 {
            let parentIndex = (i - 1) / 2
            let parent = positions[parentIndex]
            if i % 2 == 1 {
                positions.append(try tree.insert(i, at: .left(of: parent)))
            } else {
                positions.append(try tree.insert(i, at: .right(of: parent)))
            }
        }

        #expect(tree.count == 10_000)
    }

    @Test("Insert 50,000 nodes")
    func insertFiftyThousand() throws {
        var tree = Tree.Binary<Int>()
        var positions: [Tree.Binary<Int>.Position] = []
        positions.reserveCapacity(50_000)

        positions.append(try tree.insert(0, at: .root))

        for i in 1..<50_000 {
            let parentIndex = (i - 1) / 2
            let parent = positions[parentIndex]
            if i % 2 == 1 {
                positions.append(try tree.insert(i, at: .left(of: parent)))
            } else {
                positions.append(try tree.insert(i, at: .right(of: parent)))
            }
        }

        #expect(tree.count == 50_000)
    }

    // MARK: - Navigation Performance

    @Test("Navigate 100,000 positions")
    func navigateHundredThousand() throws {
        var tree = Tree.Binary<Int>()
        var positions: [Tree.Binary<Int>.Position] = []
        positions.reserveCapacity(1_000)

        positions.append(try tree.insert(0, at: .root))
        for i in 1..<1_000 {
            let parentIndex = (i - 1) / 2
            let parent = positions[parentIndex]
            if i % 2 == 1 {
                positions.append(try tree.insert(i, at: .left(of: parent)))
            } else {
                positions.append(try tree.insert(i, at: .right(of: parent)))
            }
        }

        // Navigate many times
        var navigationCount = 0
        for _ in 0..<100 {
            for pos in positions {
                _ = tree.left(of: pos)
                _ = tree.right(of: pos)
                _ = tree.parent(of: pos)
                navigationCount += 3
            }
        }

        #expect(navigationCount == 300_000)
    }

    // MARK: - Traversal Performance

    @Test("Pre-order traversal 10,000 nodes")
    func preOrderTenThousand() throws {
        var tree = Tree.Binary<Int>()
        var positions: [Tree.Binary<Int>.Position] = []
        positions.reserveCapacity(10_000)

        positions.append(try tree.insert(0, at: .root))
        for i in 1..<10_000 {
            let parentIndex = (i - 1) / 2
            let parent = positions[parentIndex]
            if i % 2 == 1 {
                positions.append(try tree.insert(i, at: .left(of: parent)))
            } else {
                positions.append(try tree.insert(i, at: .right(of: parent)))
            }
        }

        var count = 0
        tree.forEachPreOrder { _ in count += 1 }
        #expect(count == 10_000)
    }

    @Test("In-order traversal 10,000 nodes")
    func inOrderTenThousand() throws {
        var tree = Tree.Binary<Int>()
        var positions: [Tree.Binary<Int>.Position] = []
        positions.reserveCapacity(10_000)

        positions.append(try tree.insert(0, at: .root))
        for i in 1..<10_000 {
            let parentIndex = (i - 1) / 2
            let parent = positions[parentIndex]
            if i % 2 == 1 {
                positions.append(try tree.insert(i, at: .left(of: parent)))
            } else {
                positions.append(try tree.insert(i, at: .right(of: parent)))
            }
        }

        var count = 0
        tree.forEachInOrder { _ in count += 1 }
        #expect(count == 10_000)
    }

    @Test("Post-order traversal 10,000 nodes")
    func postOrderTenThousand() throws {
        var tree = Tree.Binary<Int>()
        var positions: [Tree.Binary<Int>.Position] = []
        positions.reserveCapacity(10_000)

        positions.append(try tree.insert(0, at: .root))
        for i in 1..<10_000 {
            let parentIndex = (i - 1) / 2
            let parent = positions[parentIndex]
            if i % 2 == 1 {
                positions.append(try tree.insert(i, at: .left(of: parent)))
            } else {
                positions.append(try tree.insert(i, at: .right(of: parent)))
            }
        }

        var count = 0
        tree.forEachPostOrder { _ in count += 1 }
        #expect(count == 10_000)
    }

    @Test("Level-order traversal 10,000 nodes")
    func levelOrderTenThousand() throws {
        var tree = Tree.Binary<Int>()
        var positions: [Tree.Binary<Int>.Position] = []
        positions.reserveCapacity(10_000)

        positions.append(try tree.insert(0, at: .root))
        for i in 1..<10_000 {
            let parentIndex = (i - 1) / 2
            let parent = positions[parentIndex]
            if i % 2 == 1 {
                positions.append(try tree.insert(i, at: .left(of: parent)))
            } else {
                positions.append(try tree.insert(i, at: .right(of: parent)))
            }
        }

        var count = 0
        tree.forEachLevelOrder { _ in count += 1 }
        #expect(count == 10_000)
    }

    // MARK: - Remove/Clear Performance

    @Test("Remove subtree 5,000 nodes")
    func removeSubtreeFiveThousand() throws {
        var tree = Tree.Binary<Int>()
        var positions: [Tree.Binary<Int>.Position] = []
        positions.reserveCapacity(10_000)

        positions.append(try tree.insert(0, at: .root))
        for i in 1..<10_000 {
            let parentIndex = (i - 1) / 2
            let parent = positions[parentIndex]
            if i % 2 == 1 {
                positions.append(try tree.insert(i, at: .left(of: parent)))
            } else {
                positions.append(try tree.insert(i, at: .right(of: parent)))
            }
        }

        // Remove left subtree (roughly half the tree)
        let leftChild = tree.left(of: positions[0])!
        try tree.removeSubtree(at: leftChild)

        #expect(tree.count < 10_000)
    }

    @Test("Clear 10,000 nodes")
    func clearTenThousand() throws {
        var tree = Tree.Binary<Int>()
        var positions: [Tree.Binary<Int>.Position] = []
        positions.reserveCapacity(10_000)

        positions.append(try tree.insert(0, at: .root))
        for i in 1..<10_000 {
            let parentIndex = (i - 1) / 2
            let parent = positions[parentIndex]
            if i % 2 == 1 {
                positions.append(try tree.insert(i, at: .left(of: parent)))
            } else {
                positions.append(try tree.insert(i, at: .right(of: parent)))
            }
        }

        tree.clear()
        #expect(tree.isEmpty)
    }

    // MARK: - CoW Performance

    @Test("Copy-on-write with 10,000 nodes")
    func cowTenThousand() throws {
        var tree1 = Tree.Binary<Int>()
        var positions: [Tree.Binary<Int>.Position] = []
        positions.reserveCapacity(10_000)

        positions.append(try tree1.insert(0, at: .root))
        for i in 1..<10_000 {
            let parentIndex = (i - 1) / 2
            let parent = positions[parentIndex]
            if i % 2 == 1 {
                positions.append(try tree1.insert(i, at: .left(of: parent)))
            } else {
                positions.append(try tree1.insert(i, at: .right(of: parent)))
            }
        }

        // Copy (should be O(1) - just reference count bump)
        var tree2 = tree1

        // Find a leaf node (last position in our array is a leaf)
        let leafPosition = positions[positions.count - 1]

        // Mutate tree2 (triggers actual copy)
        _ = try tree2.insert(99999, at: .left(of: leafPosition))

        #expect(tree1.count == 10_000)
        #expect(tree2.count == 10_001)
    }

    // MARK: - Bounded Performance

    @Test("Bounded insert 10,000 nodes")
    func boundedInsertTenThousand() throws {
        var tree = try Tree.Binary<Int>.Bounded(capacity: 10_000)
        var positions: [Tree.Binary<Int>.Position] = []
        positions.reserveCapacity(10_000)

        positions.append(try tree.insert(0, at: .root))
        for i in 1..<10_000 {
            let parentIndex = (i - 1) / 2
            let parent = positions[parentIndex]
            if i % 2 == 1 {
                positions.append(try tree.insert(i, at: .left(of: parent)))
            } else {
                positions.append(try tree.insert(i, at: .right(of: parent)))
            }
        }

        #expect(tree.count == 10_000)
        #expect(tree.isFull)
    }

    // MARK: - Small Spill Performance

    @Test("Small spill and grow to 1,000 nodes")
    func smallSpillToThousand() throws {
        var tree = Tree.Binary<Int>.Small<8>()
        var positions: [Tree.Binary<Int>.Position] = []
        positions.reserveCapacity(1_000)

        positions.append(try tree.insert(0, at: .root))
        for i in 1..<1_000 {
            let parentIndex = (i - 1) / 2
            let parent = positions[parentIndex]
            if i % 2 == 1 {
                positions.append(try tree.insert(i, at: .left(of: parent)))
            } else {
                positions.append(try tree.insert(i, at: .right(of: parent)))
            }
        }

        let count = tree.count
        let isSpilled = tree.isSpilled
        #expect(count == 1_000)
        #expect(isSpilled)
    }

    // MARK: - Memory Layout Verification

    @Test("Memory layout sizes")
    func memoryLayoutSizes() {
        // Verify struct sizes are reasonable
        let positionSize = MemoryLayout<Tree.Binary<Int>.Position>.size
        let nodeSize = MemoryLayout<Tree.Binary<Int>.Node>.size

        // Position should be compact (index + token)
        #expect(positionSize <= 16)  // Int + UInt32 + padding

        // Node should contain element + 3 indices
        #expect(nodeSize <= 40)  // Int element + 3 Int indices + padding

        // Print for manual inspection
        print("Position size: \(positionSize) bytes")
        print("Node size: \(nodeSize) bytes")
        print("Position stride: \(MemoryLayout<Tree.Binary<Int>.Position>.stride) bytes")
        print("Node stride: \(MemoryLayout<Tree.Binary<Int>.Node>.stride) bytes")
    }

    // MARK: - Token Validation Performance

    @Test("Token validation 100,000 operations")
    func tokenValidationPerformance() throws {
        var tree = Tree.Binary<Int>()
        var positions: [Tree.Binary<Int>.Position] = []
        positions.reserveCapacity(100)

        positions.append(try tree.insert(0, at: .root))
        for i in 1..<100 {
            let parentIndex = (i - 1) / 2
            let parent = positions[parentIndex]
            if i % 2 == 1 {
                positions.append(try tree.insert(i, at: .left(of: parent)))
            } else {
                positions.append(try tree.insert(i, at: .right(of: parent)))
            }
        }

        // Perform many peek operations (each validates token)
        var sum = 0
        for _ in 0..<1_000 {
            for pos in positions {
                if let value = tree.peek(at: pos) {
                    sum += value
                }
            }
        }

        #expect(sum > 0)
    }

    // MARK: - Deep Tree Performance

    @Test("Deep tree (500 levels left-only)")
    func deepTreeLeftOnly() throws {
        var tree = Tree.Binary<Int>()

        var current = try tree.insert(0, at: .root)
        for i in 1..<500 {
            current = try tree.insert(i, at: .left(of: current))
        }

        #expect(tree.count == 500)
        // Note: height uses recursion, so we only test shallow trees for height
        // #expect(tree.height == 499)

        // Traverse - should not stack overflow due to iterative implementation
        var count = 0
        tree.forEachPostOrder { _ in count += 1 }
        #expect(count == 500)
    }

    @Test("Deep tree (1,000 levels) - clear")
    func deepTreeClear() throws {
        var tree = Tree.Binary<Int>()

        var current = try tree.insert(0, at: .root)
        for i in 1..<1_000 {
            current = try tree.insert(i, at: .left(of: current))
        }

        #expect(tree.count == 1_000)

        // Clear should not stack overflow due to iterative implementation
        tree.clear()
        #expect(tree.isEmpty)
    }
}
