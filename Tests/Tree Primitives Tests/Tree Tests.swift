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

import Tree_Primitives
// The permanent suite compares the typed node count (`Index<Element>.Count`, a Tagged
// type) against integer literals (`tree.count == 0`). The literal `init(integerLiteral:)`
// lives in `Tagged_Primitives_Standard_Library_Integration`, surfaced here via
// `Index_Primitives`' `@_exported` chain ([MemberImportVisibility]; the umbrella's plain
// `public import` of the sub-namespaces does not propagate the deep `@_exported` SLI conformance).
import Index_Primitives

// At-target reshape ([DS-025]): the canonical dynamic tree is `Tree<TreeStorage.Dynamic<E>>`
// (the `TreeDynamic` alias). This local alias keeps the permanent suite's bodies VERBATIM
// (`Tree<Int>` / `Tree<Int>.Position`) — the re-skeleton mirrors `Array`'s `MoveArray<E>`
// test alias, exercising the SAME engine through the new column-generic surface.
fileprivate typealias Tree<Element: ~Copyable> = TreeDynamic<Element>

// MARK: - struct Tree (the canonical dynamic tree) — permanent suite
//
// Migrated into tree-core at R1 W4 when `Tree.Unbounded` retired into `struct Tree`
// (its role IS this type). Covers the shared engine through the dynamic conformer:
// traversal correctness (the post-order dropped-subtree regression), removeSubtree
// slot-freeing, the folded child / forEach views, position-survives-growth, CoW
// clone-independence, and decode / stale-reject. Order-view / Builder / Nested
// coverage retired with `Tree.Unbounded` (struct Tree exposes neither surface).

@Suite("Tree")
struct TreeTests {
    @Suite struct Unit {}
    @Suite struct EdgeCase {}
}

// MARK: - Fixtures

extension TreeTests {
    /// Nested:  0 → [1, 2], 1 → [3, 4]. Pre-order [0,1,3,4,2]; post-order [3,4,1,2,0].
    fileprivate static func makeNested() throws -> Tree<Int> {
        var tree = Tree<Int>()
        let root = try tree.insert(0, at: .root)
        let left = try tree.insert(1, at: .child(of: root, at: 0))
        _ = try tree.insert(2, at: .child(of: root, at: 1))
        _ = try tree.insert(3, at: .child(of: left, at: 0))
        _ = try tree.insert(4, at: .child(of: left, at: 1))
        return tree
    }

    /// Chain 0 → 1 → 2 → 3 → 4 (each node one child). Post-order [4,3,2,1,0].
    fileprivate static func makeChain() throws -> Tree<Int> {
        var tree = Tree<Int>()
        var position = try tree.insert(0, at: .root)
        for value in 1...4 {
            position = try tree.insert(value, at: .child(of: position, at: 0))
        }
        return tree
    }

    /// Wide 0 → [1, 2, 3, 4, 5] (all leaves). Post-order [1,2,3,4,5,0].
    fileprivate static func makeWide() throws -> Tree<Int> {
        var tree = Tree<Int>()
        let root = try tree.insert(0, at: .root)
        _ = try tree.insert(1, at: .child(of: root, at: 0))
        _ = try tree.insert(2, at: .child(of: root, at: 1))
        _ = try tree.insert(3, at: .child(of: root, at: 2))
        _ = try tree.insert(4, at: .child(of: root, at: 3))
        _ = try tree.insert(5, at: .child(of: root, at: 4))
        return tree
    }

    fileprivate static func preOrder(_ tree: borrowing Tree<Int>) -> [Int] {
        var result: [Int] = []
        tree.forEach.preOrder { result.append($0) }
        return result
    }

    fileprivate static func postOrder(_ tree: borrowing Tree<Int>) -> [Int] {
        var result: [Int] = []
        tree.forEach.postOrder { result.append($0) }
        return result
    }

    fileprivate static func levelOrder(_ tree: borrowing Tree<Int>) -> [Int] {
        var result: [Int] = []
        tree.forEach.levelOrder { result.append($0) }
        return result
    }
}

// MARK: - Unit: traversal correctness (incl. the post-order dropped-subtree regression)

extension TreeTests.Unit {
    @Test
    func `pre / post / level order on the nested fixture`() throws {
        let tree = try TreeTests.makeNested()
        #expect(TreeTests.preOrder(tree) == [0, 1, 3, 4, 2])
        #expect(TreeTests.postOrder(tree) == [3, 4, 1, 2, 0])
        #expect(TreeTests.levelOrder(tree) == [0, 1, 2, 3, 4])
    }

    @Test
    func `post-order visits every node across shapes`() throws {
        #expect(TreeTests.postOrder(try TreeTests.makeNested()) == [3, 4, 1, 2, 0])
        #expect(TreeTests.postOrder(try TreeTests.makeChain()) == [4, 3, 2, 1, 0])
        #expect(TreeTests.postOrder(try TreeTests.makeWide()) == [1, 2, 3, 4, 5, 0])
    }
}

// MARK: - Unit: removeSubtree frees exactly its slots

extension TreeTests.Unit {
    @Test
    func `removeSubtree at root frees every slot`() throws {
        var tree = try TreeTests.makeNested()
        #expect(tree.count == 5)
        let root = try #require(tree.root)
        try tree.removeSubtree(at: root)
        #expect(tree.isEmpty)
        #expect(tree.count == 0)
        #expect(tree.root == nil)
    }

    @Test
    func `removeSubtree of an interior node frees exactly that subtree`() throws {
        var tree = try TreeTests.makeNested()
        let root = try #require(tree.root)
        let leftChild = tree.child.leftmost(of: root)   // bind: `child` view is ~Escapable
        let left = try #require(leftChild)
        try tree.removeSubtree(at: left)
        #expect(tree.count == 2)
        #expect(TreeTests.preOrder(tree) == [0, 2])
        #expect(TreeTests.postOrder(tree) == [2, 0])
    }
}

// MARK: - Unit: the folded child / forEach views

extension TreeTests.Unit {
    @Test
    func `child view: at / count / leftmost / rightmost`() throws {
        let tree = try TreeTests.makeWide()   // 0 → [1, 2, 3, 4, 5]
        let root = try #require(tree.root)
        // Bind view results to locals first — the `child` view is ~Escapable, which the
        // #expect / #require macros cannot decompose as a call receiver.
        let rootChildCount = tree.child.count(of: root)
        #expect(rootChildCount == 5)
        let firstOpt = tree.child.at(0, of: root)
        let lastOpt = tree.child.at(4, of: root)
        let first = try #require(firstOpt)
        let last = try #require(lastOpt)
        let leftmost = tree.child.leftmost(of: root)
        let rightmost = tree.child.rightmost(of: root)
        #expect(leftmost == first)
        #expect(rightmost == last)
        #expect(tree.peek(at: first) == 1)
        #expect(tree.peek(at: last) == 5)
        // a leaf has no children
        let firstChildCount = tree.child.count(of: first)
        #expect(firstChildCount == 0)
        let firstLeftmost = tree.child.leftmost(of: first)
        #expect(firstLeftmost == nil)
    }
}

// MARK: - Unit: positions survive growth (the bidirectional net)

extension TreeTests.Unit {
    @Test
    func `positions survive growth (1,000-node chain)`() throws {
        var tree = Tree<Int>()
        var positions: [Tree<Int>.Position] = []
        positions.append(try tree.insert(0, at: .root))
        // Grow a 1,000-deep chain, recording every position; growth must preserve them.
        for value in 1...1000 {
            positions.append(try tree.insert(value, at: .child(of: positions[value - 1], at: 0)))
        }
        #expect(tree.count == 1001)
        // Every recorded position still decodes to its value after all the growth.
        for (value, position) in positions.enumerated() {
            #expect(tree.peek(at: position) == value)
        }
    }
}

// MARK: - Unit: copy-on-write clone-independence

extension TreeTests.Unit {
    @Test
    func `mutating a copy leaves the original intact`() throws {
        let original = try TreeTests.makeNested()   // 5 nodes
        var copy = original
        let copyRoot = try #require(copy.root)
        try copy.removeSubtree(at: copyRoot)        // empty the copy
        #expect(copy.isEmpty)
        // The original is undisturbed (generation-preserving CoW clone).
        #expect(original.count == 5)
        #expect(TreeTests.postOrder(original) == [3, 4, 1, 2, 0])
    }
}

// MARK: - Unit: decode / stale-reject

extension TreeTests.Unit {
    @Test
    func `a stale position (after removal) is rejected`() throws {
        var tree = try TreeTests.makeWide()
        let root = try #require(tree.root)
        let leafChild = tree.child.leftmost(of: root)   // first child (a leaf); bind (~Escapable view)
        let leaf = try #require(leafChild)
        try tree.remove(at: leaf)
        // The stale handle no longer validates, and peek returns nil.
        #expect(throws: __TreeError.self) { try tree.validate(leaf) }
        #expect(tree.peek(at: leaf) == nil)
    }
}

// MARK: - Edge cases

extension TreeTests.EdgeCase {
    @Test
    func `empty and single-node traversals`() throws {
        let empty = Tree<Int>()
        #expect(TreeTests.postOrder(empty) == [])

        var single = Tree<Int>()
        _ = try single.insert(42, at: .root)
        #expect(TreeTests.preOrder(single) == [42])
        #expect(TreeTests.postOrder(single) == [42])
    }

    @Test
    func `removeSubtree on a single-node tree empties it`() throws {
        var tree = Tree<Int>()
        let root = try tree.insert(42, at: .root)
        try tree.removeSubtree(at: root)
        #expect(tree.isEmpty)
        #expect(tree.count == 0)
    }
}
