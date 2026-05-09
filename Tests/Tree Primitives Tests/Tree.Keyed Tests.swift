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

// MARK: - Tree.Keyed Tests (Parallel Namespace per [TEST-004])

@Suite("Tree.Keyed")
struct TreeKeyedTests {
    @Suite struct Unit {}
    @Suite struct EdgeCase {}
    @Suite struct Integration {}
    @Suite(.serialized) struct Performance {}
}

// MARK: - Unit Tests

extension TreeKeyedTests.Unit {

    // MARK: - Initialization

    @Test
    func `empty tree has nil root and zero count`() {
        let tree = Tree<Int>.Keyed<String>()
        #expect(tree.isEmpty)
        #expect(tree.count == 0)
        #expect(tree.root == nil)
        #expect(tree.height == nil)
    }

    // MARK: - Insert

    @Test
    func `insert root stores value and updates count`() throws {
        var tree = Tree<Int>.Keyed<String>()
        let root = try tree.insert(42, at: .root)

        #expect(!tree.isEmpty)
        #expect(tree.count == 1)
        #expect(tree.root == root)
        #expect(tree.peek(at: root) == 42)
        #expect(tree.height == 0)
    }

    @Test
    func `insert children by key stores values at correct positions`() throws {
        var tree = Tree<Int>.Keyed<String>()
        let root = try tree.insert(0, at: .root)
        let left = try tree.insert(1, at: .child(of: root, key: "left"))
        let right = try tree.insert(2, at: .child(of: root, key: "right"))

        #expect(tree.count == 3)
        #expect(tree.peek(at: root) == 0)
        #expect(tree.peek(at: left) == 1)
        #expect(tree.peek(at: right) == 2)
    }

    // MARK: - Remove

    @Test
    func `remove leaf returns value and decrements count`() throws {
        var tree = Tree<Int>.Keyed<String>()
        let root = try tree.insert(0, at: .root)
        let child = try tree.insert(1, at: .child(of: root, key: "child"))

        let removed = try tree.remove(at: child)
        #expect(removed == 1)
        #expect(tree.count == 1)
        #expect(tree.child(of: root, key: "child") == nil)
    }

    @Test
    func `remove subtree removes all descendant nodes`() throws {
        var tree = Tree<Int>.Keyed<String>()
        let root = try tree.insert(0, at: .root)
        let child = try tree.insert(1, at: .child(of: root, key: "a"))
        _ = try tree.insert(2, at: .child(of: child, key: "b"))
        _ = try tree.insert(3, at: .child(of: child, key: "c"))

        #expect(tree.count == 4)
        try tree.removeSubtree(at: child)
        #expect(tree.count == 1)
        #expect(tree.child(of: root, key: "a") == nil)
    }

    // MARK: - Clear

    @Test
    func `clear empties tree and resets root`() throws {
        var tree = Tree<Int>.Keyed<String>()
        let root = try tree.insert(0, at: .root)
        _ = try tree.insert(1, at: .child(of: root, key: "a"))
        _ = try tree.insert(2, at: .child(of: root, key: "b"))

        tree.clear()
        #expect(tree.isEmpty)
        #expect(tree.count == 0)
        #expect(tree.root == nil)
    }

    // MARK: - Height

    @Test
    func `height increases with depth`() throws {
        var tree = Tree<Int>.Keyed<String>()
        let root = try tree.insert(0, at: .root)
        #expect(tree.height == 0)

        let child = try tree.insert(1, at: .child(of: root, key: "a"))
        #expect(tree.height == 1)

        _ = try tree.insert(2, at: .child(of: child, key: "b"))
        #expect(tree.height == 2)
    }

    // MARK: - Update

    @Test
    func `update replaces value at position`() throws {
        var tree = Tree<Int>.Keyed<String>()
        let root = try tree.insert(0, at: .root)

        try tree.update(at: root, 99)
        #expect(tree.peek(at: root) == 99)
    }

    // MARK: - Navigation

    @Test
    func `parent returns parent position or nil for root`() throws {
        var tree = Tree<Int>.Keyed<String>()
        let root = try tree.insert(0, at: .root)
        let child = try tree.insert(1, at: .child(of: root, key: "a"))

        #expect(tree.parent(of: child) == root)
        #expect(tree.parent(of: root) == nil)
    }

    @Test
    func `child returns position for existing key or nil`() throws {
        var tree = Tree<Int>.Keyed<String>()
        let root = try tree.insert(0, at: .root)
        let left = try tree.insert(1, at: .child(of: root, key: "left"))
        let right = try tree.insert(2, at: .child(of: root, key: "right"))

        #expect(tree.child(of: root, key: "left") == left)
        #expect(tree.child(of: root, key: "right") == right)
        #expect(tree.child(of: root, key: "nonexistent") == nil)
    }

    @Test
    func `key returns parent key or nil for root`() throws {
        var tree = Tree<Int>.Keyed<String>()
        let root = try tree.insert(0, at: .root)
        let child = try tree.insert(1, at: .child(of: root, key: "mykey"))

        #expect(tree.key(of: child) == "mykey")
        #expect(tree.key(of: root) == nil)
    }

    @Test
    func `isLeaf returns true for childless nodes`() throws {
        var tree = Tree<Int>.Keyed<String>()
        let root = try tree.insert(0, at: .root)
        #expect(tree.isLeaf(root))

        let child = try tree.insert(1, at: .child(of: root, key: "a"))
        #expect(!tree.isLeaf(root))
        #expect(tree.isLeaf(child))
    }

    @Test
    func `childCount returns number of direct children`() throws {
        var tree = Tree<Int>.Keyed<String>()
        let root = try tree.insert(0, at: .root)
        #expect(tree.childCount(of: root) == 0)

        _ = try tree.insert(1, at: .child(of: root, key: "a"))
        _ = try tree.insert(2, at: .child(of: root, key: "b"))
        _ = try tree.insert(3, at: .child(of: root, key: "c"))
        #expect(tree.childCount(of: root) == 3)
    }

    @Test
    func `forEachChild iterates children in insertion order`() throws {
        var tree = Tree<Int>.Keyed<String>()
        let root = try tree.insert(0, at: .root)
        _ = try tree.insert(1, at: .child(of: root, key: "x"))
        _ = try tree.insert(2, at: .child(of: root, key: "y"))
        _ = try tree.insert(3, at: .child(of: root, key: "z"))

        var keys: [String] = []
        var values: [Int] = []
        tree.forEachChild(of: root) { key, pos in
            keys.append(key)
            if let v = tree.peek(at: pos) {
                values.append(v)
            }
        }

        #expect(keys == ["x", "y", "z"])
        #expect(values == [1, 2, 3])
    }

    // MARK: - Key Path

    @Test
    func `keyPath reconstructs path from root to node`() throws {
        var tree = Tree<Int>.Keyed<String>()
        let root = try tree.insert(0, at: .root)
        let a = try tree.insert(1, at: .child(of: root, key: "a"))
        let b = try tree.insert(2, at: .child(of: a, key: "b"))
        let c = try tree.insert(3, at: .child(of: b, key: "c"))

        #expect(tree.keyPath(to: root) == [])
        #expect(tree.keyPath(to: a) == ["a"])
        #expect(tree.keyPath(to: b) == ["a", "b"])
        #expect(tree.keyPath(to: c) == ["a", "b", "c"])
    }

    @Test
    func `position at key path resolves to correct node`() throws {
        var tree = Tree<Int>.Keyed<String>()
        let root = try tree.insert(0, at: .root)
        let a = try tree.insert(1, at: .child(of: root, key: "a"))
        let b = try tree.insert(2, at: .child(of: a, key: "b"))

        #expect(tree.position(at: [] as [String]) == root)
        #expect(tree.position(at: ["a"]) == a)
        #expect(tree.position(at: ["a", "b"]) == b)
        #expect(tree.position(at: ["nonexistent"]) == nil)
        #expect(tree.position(at: ["a", "nonexistent"]) == nil)
    }

    @Test
    func `value at key path returns stored value`() throws {
        var tree = Tree<Int>.Keyed<String>()
        let root = try tree.insert(0, at: .root)
        let a = try tree.insert(1, at: .child(of: root, key: "a"))
        _ = try tree.insert(2, at: .child(of: a, key: "b"))

        #expect(tree.value(at: [] as [String]) == 0)
        #expect(tree.value(at: ["a"]) == 1)
        #expect(tree.value(at: ["a", "b"]) == 2)
        #expect(tree.value(at: ["missing"]) == nil)
    }

    @Test
    func `update at key path replaces value`() throws {
        var tree = Tree<Int>.Keyed<String>()
        let root = try tree.insert(0, at: .root)
        let a = try tree.insert(1, at: .child(of: root, key: "a"))
        _ = try tree.insert(2, at: .child(of: a, key: "b"))

        try tree.update(99, at: ["a", "b"])
        #expect(tree.value(at: ["a", "b"]) == 99)
    }

    @Test
    func `insert at key path creates intermediate nodes`() throws {
        var tree = Tree<Int>.Keyed<String>()
        _ = try tree.insert(0, at: .root)

        let pos = try tree.insert(42, at: ["a", "b", "c"]) { _ in -1 }

        #expect(tree.peek(at: pos) == 42)
        #expect(tree.value(at: ["a"]) == -1)
        #expect(tree.value(at: ["a", "b"]) == -1)
        #expect(tree.value(at: ["a", "b", "c"]) == 42)
    }

    @Test
    func `insert at key path creates root when tree is empty`() throws {
        var tree = Tree<Int>.Keyed<String>()

        let pos = try tree.insert(42, at: ["a"]) { _ in 0 }
        #expect(tree.peek(at: pos) == 42)
        #expect(tree.root != nil)
        #expect(tree.value(at: ["a"]) == 42)
    }

    // MARK: - Traversal

    @Test
    func `forEachPreOrder visits nodes depth-first root-first`() throws {
        let tree = try makeTestTree()
        var result: [Int] = []
        tree.forEachPreOrder { value in
            result.append(value)
        }
        #expect(result == [0, 1, 3, 4, 2])
    }

    @Test
    func `forEachPostOrder visits nodes depth-first children-first`() throws {
        let tree = try makeTestTree()
        var result: [Int] = []
        tree.forEachPostOrder { value in
            result.append(value)
        }
        #expect(result == [3, 4, 1, 2, 0])
    }

    @Test
    func `forEachLevelOrder visits nodes breadth-first`() throws {
        let tree = try makeTestTree()
        var result: [Int] = []
        tree.forEachLevelOrder { value in
            result.append(value)
        }
        #expect(result == [0, 1, 2, 3, 4])
    }

    @Test
    func `preOrder sequence produces depth-first root-first values`() throws {
        let tree = try makeTestTree()
        let result = Swift.Array(tree.preOrder)
        #expect(result == [0, 1, 3, 4, 2])
    }

    @Test
    func `postOrder sequence produces depth-first children-first values`() throws {
        let tree = try makeTestTree()
        let result = Swift.Array(tree.postOrder)
        #expect(result == [3, 4, 1, 2, 0])
    }

    @Test
    func `levelOrder sequence produces breadth-first values`() throws {
        let tree = try makeTestTree()
        let result = Swift.Array(tree.levelOrder)
        #expect(result == [0, 1, 2, 3, 4])
    }

    // MARK: - Map / CompactMap

    @Test
    func `map produces flat array in pre-order`() throws {
        var tree = Tree<Int>.Keyed<String>()
        let root = try tree.insert(1, at: .root)
        _ = try tree.insert(2, at: .child(of: root, key: "a"))
        _ = try tree.insert(3, at: .child(of: root, key: "b"))

        let result = tree.map { $0 * 10 }
        #expect(result == [10, 20, 30])
    }

    @Test
    func `compactMap filters nil values from flat array`() throws {
        var tree = Tree<Int>.Keyed<String>()
        let root = try tree.insert(1, at: .root)
        _ = try tree.insert(2, at: .child(of: root, key: "a"))
        _ = try tree.insert(3, at: .child(of: root, key: "b"))

        let result = tree.compactMap { $0 > 1 ? $0 : nil }
        #expect(result == [2, 3])
    }

    // MARK: - MapValues

    @Test
    func `mapValues transforms all values preserving structure`() throws {
        var tree = Tree<Int>.Keyed<String>()
        let root = try tree.insert(1, at: .root)
        _ = try tree.insert(2, at: .child(of: root, key: "a"))
        _ = try tree.insert(3, at: .child(of: root, key: "b"))

        let doubled = tree.mapValues { $0 * 2 }
        #expect(Swift.Array(doubled.preOrder) == [2, 4, 6])
    }

    @Test
    func `mapValues preserves key path structure`() throws {
        var tree = Tree<Int>.Keyed<String>()
        let root = try tree.insert(0, at: .root)
        let a = try tree.insert(1, at: .child(of: root, key: "a"))
        _ = try tree.insert(2, at: .child(of: a, key: "b"))

        let mapped = tree.mapValues { String($0) }
        #expect(mapped.value(at: ["a", "b"]) == "2")
        #expect(mapped.value(at: ["a"]) == "1")
    }

    @Test
    func `mapValues with key path includes path in transform`() throws {
        var tree = Tree<Int>.Keyed<String>()
        let root = try tree.insert(0, at: .root)
        let a = try tree.insert(1, at: .child(of: root, key: "a"))
        _ = try tree.insert(2, at: .child(of: a, key: "b"))

        let mapped = tree.mapValues { (path: [String], value: Int) -> String in
            "\(path.joined(separator: "/")):\(value)"
        }
        #expect(mapped.value(at: [] as [String]) == ":0")
        #expect(mapped.value(at: ["a"]) == "a:1")
        #expect(mapped.value(at: ["a", "b"]) == "a/b:2")
    }

    // MARK: - Error Descriptions

    @Test
    func `error descriptions are non-empty`() {
        let errors: [__TreeKeyedError<String>] = [
            .empty,
            .invalidPosition,
            .rootOccupied,
            .keyOccupied("test"),
            .keyNotFound("test"),
            .cannotRemoveNonLeaf,
        ]

        for error in errors {
            #expect(!error.description.isEmpty)
        }
    }
}

// MARK: - Helpers

extension TreeKeyedTests.Unit {

    /// Builds a test tree:
    ///        0
    ///       / \
    ///      1   2
    ///     / \
    ///    3   4
    private func makeTestTree() throws -> Tree<Int>.Keyed<String> {
        var tree = Tree<Int>.Keyed<String>()
        let root = try tree.insert(0, at: .root)
        let left = try tree.insert(1, at: .child(of: root, key: "L"))
        _ = try tree.insert(2, at: .child(of: root, key: "R"))
        _ = try tree.insert(3, at: .child(of: left, key: "LL"))
        _ = try tree.insert(4, at: .child(of: left, key: "LR"))
        return tree
    }
}

// MARK: - Edge Case Tests

extension TreeKeyedTests.EdgeCase {

    @Test
    func `insert throws rootOccupied when root already exists`() throws {
        var tree = Tree<Int>.Keyed<String>()
        _ = try tree.insert(1, at: .root)

        #expect {
            try tree.insert(2, at: .root)
        } throws: { error in
            guard let e = error as? __TreeKeyedError<String>,
                case .rootOccupied = e
            else { return false }
            return true
        }
    }

    @Test
    func `insert throws keyOccupied when child key exists`() throws {
        var tree = Tree<Int>.Keyed<String>()
        let root = try tree.insert(0, at: .root)
        _ = try tree.insert(1, at: .child(of: root, key: "child"))

        #expect {
            try tree.insert(2, at: .child(of: root, key: "child"))
        } throws: { error in
            guard let keyedError = error as? __TreeKeyedError<String> else { return false }
            switch keyedError {
            case .keyOccupied(let key):
                return key == "child"
            default:
                return false
            }
        }
    }

    @Test
    func `remove throws cannotRemoveNonLeaf for node with children`() throws {
        var tree = Tree<Int>.Keyed<String>()
        let root = try tree.insert(0, at: .root)
        _ = try tree.insert(1, at: .child(of: root, key: "child"))

        #expect {
            try tree.remove(at: root)
        } throws: { error in
            guard let e = error as? __TreeKeyedError<String>,
                case .cannotRemoveNonLeaf = e
            else { return false }
            return true
        }
    }

    @Test
    func `stale position returns nil for peek after remove`() throws {
        var tree = Tree<Int>.Keyed<String>()
        let root = try tree.insert(0, at: .root)
        let child = try tree.insert(1, at: .child(of: root, key: "a"))

        _ = try tree.remove(at: child)
        #expect(tree.peek(at: child) == nil)
    }

    @Test
    func `stale position returns nil for navigation after remove`() throws {
        var tree = Tree<Int>.Keyed<String>()
        let root = try tree.insert(0, at: .root)
        let child = try tree.insert(1, at: .child(of: root, key: "a"))

        _ = try tree.remove(at: child)
        #expect(tree.parent(of: child) == nil)
        #expect(tree.isLeaf(child) == false)
    }

    @Test
    func `stale position throws invalidPosition on insert`() throws {
        var tree = Tree<Int>.Keyed<String>()
        let root = try tree.insert(0, at: .root)
        let child = try tree.insert(1, at: .child(of: root, key: "a"))

        _ = try tree.remove(at: child)

        #expect {
            try tree.insert(2, at: .child(of: child, key: "b"))
        } throws: { error in
            guard let e = error as? __TreeKeyedError<String>,
                case .invalidPosition = e
            else { return false }
            return true
        }
    }

    @Test
    func `empty tree traversal produces no values`() {
        let tree = Tree<Int>.Keyed<String>()
        var count = 0
        tree.forEachPreOrder { _ in count += 1 }
        #expect(count == 0)
        #expect(Swift.Array(tree.preOrder).isEmpty)
    }

    @Test
    func `single node traversal produces one value for all orders`() throws {
        var tree = Tree<Int>.Keyed<String>()
        _ = try tree.insert(42, at: .root)
        #expect(Swift.Array(tree.preOrder) == [42])
        #expect(Swift.Array(tree.postOrder) == [42])
        #expect(Swift.Array(tree.levelOrder) == [42])
    }

    @Test
    func `compactMapValues drops entire tree when root is filtered`() throws {
        var tree = Tree<Int>.Keyed<String>()
        let root = try tree.insert(1, at: .root)
        _ = try tree.insert(2, at: .child(of: root, key: "a"))
        _ = try tree.insert(3, at: .child(of: root, key: "b"))

        let filtered = tree.compactMapValues { $0 % 2 == 0 ? $0 : nil }
        #expect(filtered.isEmpty)
    }
}

// MARK: - Integration Tests

extension TreeKeyedTests.Integration {

    @Test
    func `copy-on-write preserves original after mutation of copy`() throws {
        var tree1 = Tree<Int>.Keyed<String>()
        let root = try tree1.insert(0, at: .root)
        _ = try tree1.insert(1, at: .child(of: root, key: "a"))

        var tree2 = tree1

        try tree2.update(at: root, 99)

        #expect(tree1.peek(at: root) == 0)
        #expect(tree2.peek(at: root) == 99)
    }

    @Test
    func `zip produces structural intersection of two trees`() throws {
        var lhs = Tree<Int>.Keyed<String>()
        let lRoot = try lhs.insert(1, at: .root)
        _ = try lhs.insert(2, at: .child(of: lRoot, key: "a"))
        _ = try lhs.insert(3, at: .child(of: lRoot, key: "b"))

        var rhs = Tree<String>.Keyed<String>()
        let rRoot = try rhs.insert("x", at: .root)
        _ = try rhs.insert("y", at: .child(of: rRoot, key: "a"))
        _ = try rhs.insert("z", at: .child(of: rRoot, key: "b"))

        let zipped = zip(lhs, rhs)
        #expect(zipped.count == 3)

        var values: [(Int, String)] = []
        zipped.forEachPreOrder { pair in
            values.append(pair)
        }
        #expect(values.count == 3)
        #expect(values[0].0 == 1 && values[0].1 == "x")
        #expect(values[1].0 == 2 && values[1].1 == "y")
        #expect(values[2].0 == 3 && values[2].1 == "z")
    }

    @Test
    func `zip drops non-overlapping branches`() throws {
        var lhs = Tree<Int>.Keyed<String>()
        let lRoot = try lhs.insert(1, at: .root)
        _ = try lhs.insert(2, at: .child(of: lRoot, key: "a"))
        _ = try lhs.insert(3, at: .child(of: lRoot, key: "b"))

        var rhs = Tree<Int>.Keyed<String>()
        let rRoot = try rhs.insert(10, at: .root)
        _ = try rhs.insert(20, at: .child(of: rRoot, key: "a"))

        let zipped = zip(lhs, rhs)
        #expect(zipped.count == 2)
    }

    @Test
    func `zip with empty tree produces empty result`() throws {
        var lhs = Tree<Int>.Keyed<String>()
        _ = try lhs.insert(1, at: .root)
        let rhs = Tree<Int>.Keyed<String>()

        let zipped = zip(lhs, rhs)
        #expect(zipped.isEmpty)
    }

    @Test
    func `prune removes matching subtrees and preserves others`() throws {
        var tree = Tree<Int>.Keyed<String>()
        let root = try tree.insert(0, at: .root)
        let a = try tree.insert(1, at: .child(of: root, key: "a"))
        _ = try tree.insert(2, at: .child(of: a, key: "deep"))
        _ = try tree.insert(10, at: .child(of: root, key: "b"))

        tree.prune { $0 >= 10 }

        #expect(tree.count == 3)
        #expect(tree.child(of: root, key: "b") == nil)
        #expect(tree.child(of: root, key: "a") != nil)
    }

    @Test
    func `prune entire tree removes all nodes`() throws {
        var tree = Tree<Int>.Keyed<String>()
        _ = try tree.insert(1, at: .root)

        tree.prune { _ in true }
        #expect(tree.isEmpty)
    }

    @Test
    func `prune with false predicate preserves all nodes`() throws {
        var tree = Tree<Int>.Keyed<String>()
        let root = try tree.insert(0, at: .root)
        _ = try tree.insert(1, at: .child(of: root, key: "a"))
        _ = try tree.insert(2, at: .child(of: root, key: "b"))

        tree.prune { _ in false }
        #expect(tree.count == 3)
    }

    @Test
    func `compactMapValues keeps surviving branches with transformed values`() throws {
        var tree = Tree<Int>.Keyed<String>()
        let root = try tree.insert(0, at: .root)
        _ = try tree.insert(1, at: .child(of: root, key: "a"))
        _ = try tree.insert(2, at: .child(of: root, key: "b"))

        let filtered = tree.compactMapValues { $0 != 1 ? $0 * 10 : nil }
        #expect(Swift.Array(filtered.preOrder) == [0, 20])
    }
}

// MARK: - Graph-Parity API Tests

// Shared fixture:
//   root: 0
//   ├── "a": 1
//   │   ├── "x": 10
//   │   └── "y": 11
//   └── "b": 2
//       └── "z": 20

private func makeGraphParityTree() throws -> Tree<Int>.Keyed<String> {
    var tree = Tree<Int>.Keyed<String>()
    let root = try tree.insert(0, at: .root)
    let a = try tree.insert(1, at: .child(of: root, key: "a"))
    _ = try tree.insert(10, at: .child(of: a, key: "x"))
    _ = try tree.insert(11, at: .child(of: a, key: "y"))
    let b = try tree.insert(2, at: .child(of: root, key: "b"))
    _ = try tree.insert(20, at: .child(of: b, key: "z"))
    return tree
}

// MARK: - Unit Tests (Graph-Parity)

extension TreeKeyedTests.Unit {

    // MARK: forEach

    @Test
    func `forEach visits all nodes in pre-order with key paths`() throws {
        let tree = try makeGraphParityTree()
        var visited: [([String], Int)] = []
        tree.forEach { path, value in
            visited.append((path, value))
        }

        #expect(visited.count == 6)
        #expect(visited[0].0 == [] && visited[0].1 == 0)
        #expect(visited[1].0 == ["a"] && visited[1].1 == 1)
        #expect(visited[2].0 == ["a", "x"] && visited[2].1 == 10)
        #expect(visited[3].0 == ["a", "y"] && visited[3].1 == 11)
        #expect(visited[4].0 == ["b"] && visited[4].1 == 2)
        #expect(visited[5].0 == ["b", "z"] && visited[5].1 == 20)
    }

    @Test
    func `forEach with typed throw propagates error`() throws {
        let tree = try makeGraphParityTree()

        struct StopError: Swift.Error {}

        #expect(throws: StopError.self) {
            try tree.forEach { (path: [String], value: Int) throws(StopError) in
                if value == 10 { throw StopError() }
            }
        }
    }

    // MARK: mapValues / compactMapValues

    @Test
    func `mapValues with recursivelyApply broadcasts value to all descendants`() throws {
        let tree = try makeGraphParityTree()

        let result = tree.mapValues { (path: [String], value: Int) -> (Int, recursivelyApply: Bool) in
            if path == ["a"] {
                return (-1, recursivelyApply: true)
            }
            return (value, recursivelyApply: false)
        }

        #expect(result.value(at: [] as [String]) == 0)
        #expect(result.value(at: ["a"]) == -1)
        #expect(result.value(at: ["a", "x"]) == -1)
        #expect(result.value(at: ["a", "y"]) == -1)
        #expect(result.value(at: ["b"]) == 2)
        #expect(result.value(at: ["b", "z"]) == 20)
    }

    @Test
    func `mapValues with key path and typed throws transforms values`() throws {
        let tree = try makeGraphParityTree()

        struct MapError: Swift.Error {}

        let result = try tree.mapValues { (path: [String], value: Int) throws(MapError) -> String in
            "\(path.joined(separator: "/")):\(value)"
        }

        #expect(result.value(at: [] as [String]) == ":0")
        #expect(result.value(at: ["a"]) == "a:1")
        #expect(result.value(at: ["a", "x"]) == "a/x:10")
        #expect(result.value(at: ["b", "z"]) == "b/z:20")
    }

    @Test
    func `compactMapValues with key path filters nodes and preserves structure`() throws {
        let tree = try makeGraphParityTree()

        let result = tree.compactMapValues { (path: [String], value: Int) -> Int? in
            value >= 10 ? value : nil
        }

        // Root (0) is filtered → entire tree dropped
        #expect(result.isEmpty)
    }

    @Test
    func `compactMapValues with recursivelyApply broadcasts and filters`() throws {
        let tree = try makeGraphParityTree()

        let result = tree.compactMapValues { (path: [String], value: Int) -> (Int, recursivelyApply: Bool)? in
            if path == ["b"] { return nil }  // Drop "b" subtree
            if path == ["a"] { return (99, recursivelyApply: true) }  // Broadcast to "a" subtree
            return (value, recursivelyApply: false)
        }

        #expect(result.value(at: [] as [String]) == 0)
        #expect(result.value(at: ["a"]) == 99)
        #expect(result.value(at: ["a", "x"]) == 99)
        #expect(result.value(at: ["a", "y"]) == 99)
        #expect(result.value(at: ["b"]) == nil)
        #expect(result.value(at: ["b", "z"]) == nil)
    }

    // MARK: map / compactMap / flatMap

    @Test
    func `map with key path produces array of transformed elements`() throws {
        let tree = try makeGraphParityTree()

        let result: [String] = tree.map { (path: [String], value: Int) -> String in
            "\(path.count):\(value)"
        }

        #expect(result == ["0:0", "1:1", "2:10", "2:11", "1:2", "2:20"])
    }

    @Test
    func `compactMap with key path filters nil results`() throws {
        let tree = try makeGraphParityTree()

        let result: [Int] = tree.compactMap { (_: [String], value: Int) -> Int? in
            value > 5 ? value : nil
        }

        #expect(result == [10, 11, 20])
    }

    @Test
    func `flatMap concatenates sequence results`() throws {
        let tree = try makeGraphParityTree()

        let result: [Int] = tree.flatMap { (_: [String], value: Int) -> [Int] in
            [value, value * 100]
        }

        #expect(result == [0, 0, 1, 100, 10, 1000, 11, 1100, 2, 200, 20, 2000])
    }

    // MARK: values(along:)

    @Test
    func `values along yields values along valid key path`() throws {
        let tree = try makeGraphParityTree()

        let result = Swift.Array(tree.values(along: ["a", "x"]))
        #expect(result == [1, 10] as [Int?])
    }
}

// MARK: - Edge Case Tests (Graph-Parity)

extension TreeKeyedTests.EdgeCase {

    @Test
    func `forEach on empty tree does not call body`() {
        let tree = Tree<Int>.Keyed<String>()
        var count = 0
        tree.forEach { (_: [String], _: Int) in count += 1 }
        #expect(count == 0)
    }

    @Test
    func `mapValues recursivelyApply on root broadcasts to entire tree`() throws {
        let tree = try makeGraphParityTree()

        let result = tree.mapValues { (path: [String], _: Int) -> (Int, recursivelyApply: Bool) in
            if path.isEmpty { return (-1, recursivelyApply: true) }
            return (0, recursivelyApply: false)  // Never reached
        }

        #expect(result.value(at: [] as [String]) == -1)
        #expect(result.value(at: ["a"]) == -1)
        #expect(result.value(at: ["a", "x"]) == -1)
        #expect(result.value(at: ["a", "y"]) == -1)
        #expect(result.value(at: ["b"]) == -1)
        #expect(result.value(at: ["b", "z"]) == -1)
    }

    @Test
    func `compactMapValues with key path returns empty tree when root is filtered out`() throws {
        let tree = try makeGraphParityTree()

        let result = tree.compactMapValues { (_: [String], _: Int) -> Int? in
            nil
        }

        #expect(result.isEmpty)
    }

    @Test
    func `values along returns nils after missing key`() throws {
        let tree = try makeGraphParityTree()

        let result = Swift.Array(tree.values(along: ["a", "missing", "deeper"]))
        #expect(result.count == 3)
        #expect(result[0] == 1)
        #expect(result[1] == nil)
        #expect(result[2] == nil)
    }

    @Test
    func `values along on empty tree returns empty sequence`() {
        let tree = Tree<Int>.Keyed<String>()

        let result = Swift.Array(tree.values(along: ["a", "b"]))
        #expect(result.isEmpty)
    }
}

// MARK: - Integration Tests (Graph-Parity)

extension TreeKeyedTests.Integration {

    @Test
    func `forEach async visits all nodes with correct key paths`() async throws {
        let tree = try makeGraphParityTree()
        var visited: [([String], Int)] = []

        await tree.forEach { (path: [String], value: Int) async in
            visited.append((path, value))
        }

        #expect(visited.count == 6)
        #expect(visited[0].0 == [] && visited[0].1 == 0)
        #expect(visited[1].0 == ["a"] && visited[1].1 == 1)
        #expect(visited[4].0 == ["b"] && visited[4].1 == 2)
    }

    @Test
    func `mapValues async with recursivelyApply matches sync behavior`() async throws {
        let tree = try makeGraphParityTree()

        let result = await tree.mapValues { (path: [String], value: Int) async -> (Int, recursivelyApply: Bool) in
            if path == ["a"] {
                return (-1, recursivelyApply: true)
            }
            return (value, recursivelyApply: false)
        }

        #expect(result.value(at: [] as [String]) == 0)
        #expect(result.value(at: ["a"]) == -1)
        #expect(result.value(at: ["a", "x"]) == -1)
        #expect(result.value(at: ["a", "y"]) == -1)
        #expect(result.value(at: ["b"]) == 2)
        #expect(result.value(at: ["b", "z"]) == 20)
    }
}

// MARK: - Unit Tests (Structural APIs)

extension TreeKeyedTests.Unit {

    // MARK: init(rootValue:)

    @Test
    func `init with rootValue creates single-node tree`() {
        let tree = Tree<Int>.Keyed<String>(rootValue: 42)
        #expect(!tree.isEmpty)
        #expect(tree.count == 1)
        #expect(tree.root != nil)
        #expect(tree.rootValue == 42)
    }

    // MARK: rootValue

    @Test
    func `rootValue returns root value and nil for empty tree`() throws {
        let empty = Tree<Int>.Keyed<String>()
        #expect(empty.rootValue == nil)

        let tree = Tree<Int>.Keyed<String>(rootValue: 99)
        #expect(tree.rootValue == 99)
    }

    @Test
    func `rootValue setter updates existing root`() {
        var tree = Tree<Int>.Keyed<String>(rootValue: 1)
        tree.rootValue = 2
        #expect(tree.rootValue == 2)
    }

    @Test
    func `rootValue setter creates root when tree is empty`() {
        var tree = Tree<Int>.Keyed<String>()
        tree.rootValue = 42
        #expect(tree.rootValue == 42)
        #expect(tree.count == 1)
    }

    // MARK: Subscripts

    @Test
    func `sparse subscript get returns value at key path`() throws {
        var tree = Tree<Int?>.Keyed<String>()
        try tree.insert(10, at: ["a", "x"], intermediateValue: { _ in nil })
        try tree.insert(20, at: ["b"], intermediateValue: { _ in nil })

        #expect(tree[["a", "x"]] == 10)
        #expect(tree[["b"]] == 20)
        #expect(tree[["c"]] == nil)
    }

    @Test
    func `sparse subscript set creates intermediates with nil`() {
        var tree = Tree<Int?>.Keyed<String>()
        tree[["a", "b", "c"]] = 42

        #expect(tree[["a", "b", "c"]] == 42)
        #expect(tree[["a"]] == nil)  // intermediate created with nil
        #expect(tree[["a", "b"]] == nil)  // intermediate created with nil
        #expect(tree.count == 4)  // root + a + b + c
    }

    @Test
    func `sparse subscript optional chaining mutation works`() {
        var tree = Tree<[Int]?>.Keyed<String>()
        tree[["data"]] = [1, 2, 3]

        tree[["data"]]?.append(4)

        #expect(tree[["data"]] == [1, 2, 3, 4])
    }

    // MARK: subtree

    @Test
    func `subtree extracts standalone copy of subtree`() throws {
        let tree = try makeGraphParityTree()

        let sub = tree.subtree(at: ["a"])
        #expect(sub != nil)
        #expect(sub!.rootValue == 1)
        #expect(sub!.count == 3)  // a(1), x(10), y(11)
        #expect(sub!.value(at: ["x"]) == 10)
        #expect(sub!.value(at: ["y"]) == 11)
    }
}

// MARK: - Edge Case Tests (Structural APIs)

extension TreeKeyedTests.EdgeCase {

    @Test
    func `read-only subscript returns nil for missing path`() {
        let tree = Tree<Int>.Keyed<String>(rootValue: 1)
        let result: Int? = tree[["nonexistent"]]
        #expect(result == nil)
    }

    @Test
    func `sparse subscript set at empty key path creates root`() {
        var tree = Tree<Int?>.Keyed<String>()
        #expect(tree.isEmpty)

        tree[[] as [String]] = 42
        #expect(tree.rootValue == 42)
        #expect(tree.count == 1)
    }

    @Test
    func `sparse insert at empty key path updates existing root`() throws {
        var tree = Tree<Int?>.Keyed<String>(rootValue: 1)
        let pos = try tree.insert(Optional(99), at: [] as [String])
        #expect(tree.rootValue == 99)
        #expect(pos == tree.root)
    }

    @Test
    func `subtree returns nil for nonexistent path`() {
        let tree = Tree<Int>.Keyed<String>(rootValue: 1)
        #expect(tree.subtree(at: ["missing"]) == nil)
    }

    @Test
    func `children of root returns snapshot safe for mutation`() throws {
        var tree = Tree<Int>.Keyed<String>(rootValue: 0)
        let root = tree.root!
        try tree.insert(1, at: .child(of: root, key: "a"))
        try tree.insert(2, at: .child(of: root, key: "b"))

        let snapshot = tree.children(of: root)!
        #expect(snapshot.count == 2)

        // Mutate tree while iterating snapshot
        for (_, childPos) in snapshot {
            if let val = tree.peek(at: childPos) {
                try tree.update(at: childPos, val * 10)
            }
        }

        #expect(tree.value(at: ["a"]) == 10)
        #expect(tree.value(at: ["b"]) == 20)
    }
}

// MARK: - Integration Tests (Structural APIs)

extension TreeKeyedTests.Integration {

    @Test
    func `sparse graph workflow matches Graph usage pattern`() {
        // Mimics swift-testing pattern: Graph<String, Test?>()
        var tree = Tree<String?>.Keyed<String>()

        // Insert via sparse subscript (like graph[keyPath] = value)
        tree[["suite", "testA"]] = "test A"
        tree[["suite", "testB"]] = "test B"
        tree[["standalone"]] = "standalone"

        // Read back
        #expect(tree[["suite", "testA"]] == "test A")
        #expect(tree[["suite", "testB"]] == "test B")
        #expect(tree[["standalone"]] == "standalone")
        #expect(tree[["suite"]] == nil)  // intermediate has nil

        // Optional chaining mutation (like graph[keyPath]?.mutate())
        tree[["suite", "testA"]]?.append(" (modified)")
        #expect(tree[["suite", "testA"]] == "test A (modified)")

        // compactMap to extract non-nil values (like graph.compactMap(\.value))
        let values = tree.compactMap { (_: [String], value: String?) -> String? in value }
        #expect(values.count == 3)
    }

    @Test
    func `subtree is independent of source tree mutations`() throws {
        var tree = try makeGraphParityTree()

        // Extract subtree at "a"
        let sub = tree.subtree(at: ["a"])!
        #expect(sub.rootValue == 1)
        #expect(sub.value(at: ["x"]) == 10)

        // Mutate source tree
        try tree.update(999, at: ["a"])
        try tree.update(888, at: ["a", "x"])

        // Subtree is unchanged (independent copy)
        #expect(sub.rootValue == 1)
        #expect(sub.value(at: ["x"]) == 10)

        // Source tree has new values
        #expect(tree.value(at: ["a"]) == 999)
        #expect(tree.value(at: ["a", "x"]) == 888)
    }
}
