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

@Suite("Tree - Deinit")
struct TreeDeinitTests {

    final class Tracker: @unchecked Sendable {
        private var _storage: [Int] = []
        var deinitCount: Int { _storage.count }
        func append(_ id: Int) { _storage.append(id) }
    }

    struct TrackedElement: ~Copyable {
        let id: Int
        let tracker: Tracker
        init(_ id: Int, tracker: Tracker) { self.id = id; self.tracker = tracker }
        deinit { tracker.append(id) }
    }

    /// Copyable tracked element for Tree.N.Small (insert requires Copyable).
    final class TrackedBox: @unchecked Sendable {
        let id: Int
        let tracker: Tracker
        init(_ id: Int, tracker: Tracker) { self.id = id; self.tracker = tracker }
        deinit { tracker.append(id) }
    }

    // MARK: - Tree.N.Inline (binary tree, n=2)

    @Test
    func `Inline deinit destroys all elements`() throws {
        let tracker = Tracker()
        do {
            var tree = Tree.N<TrackedElement, 2>.Inline<8>()
            let root = try tree.insert(TrackedElement(1, tracker: tracker), at: .root)
            _ = try tree.insert(TrackedElement(2, tracker: tracker), at: .left(of: root))
            _ = try tree.insert(TrackedElement(3, tracker: tracker), at: .right(of: root))
        }
        #expect(tracker.deinitCount == 3)
    }

    @Test
    func `Inline empty deinit does not crash`() {
        do {
            let _ = Tree.N<TrackedElement, 2>.Inline<8>()
        }
    }

    // MARK: - Tree.N.Small

    @Test
    func `Small deinit destroys all elements`() throws {
        let tracker = Tracker()
        do {
            var tree = Tree.N<TrackedBox, 2>.Small<8>()
            let root = try tree.insert(TrackedBox(1, tracker: tracker), at: .root)
            _ = try tree.insert(TrackedBox(2, tracker: tracker), at: .left(of: root))
            _ = try tree.insert(TrackedBox(3, tracker: tracker), at: .right(of: root))
        }
        #expect(tracker.deinitCount == 3)
    }

    @Test
    func `Small empty deinit does not crash`() {
        do {
            let _ = Tree.N<TrackedBox, 2>.Small<8>()
        }
    }
}
