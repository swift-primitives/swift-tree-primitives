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

@Suite("Tree.N variants + Builder")
struct TreeNVariantsBuilderTests {
    @Suite struct InlineTree {}
    @Suite struct SmallTree {}
    @Suite struct BoundedTree {}
}

extension TreeNVariantsBuilderTests.InlineTree {
    @Test
    func `Inline within capacity`() throws {
        let tree = try Tree<Int>.N<2>.Inline<8> { 1; 2; 3 }
        let isEmpty = tree.isEmpty
        #expect(!isEmpty)
    }

    @Test
    func `Inline throws on overflow`() {
        do {
            _ = try Tree<Int>.N<2>.Inline<2> { 1; 2; 3 }
            Issue.record("expected throw")
        } catch {
            // expected
        }
    }
}

extension TreeNVariantsBuilderTests.SmallTree {
    @Test
    func `Small within inline`() throws {
        var tree = try Tree<Int>.N<2>.Small<8> { 1; 2; 3 }
        let isEmpty = tree.isEmpty
        #expect(!isEmpty)
    }

    @Test
    func `Small spills to heap`() throws {
        var tree = try Tree<Int>.N<2>.Small<2> { 1; 2; 3; 4; 5 }
        let isEmpty = tree.isEmpty
        #expect(!isEmpty)
    }
}

extension TreeNVariantsBuilderTests.BoundedTree {
    @Test
    func `Bounded within capacity`() throws {
        let tree = try Tree<Int>.N<2>.Bounded(capacity: 8) { 1; 2; 3 }
        let isEmpty = tree.isEmpty
        #expect(!isEmpty)
    }
}
