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

public import Property_Primitives

// MARK: - Tree.forEach — the closure-based traversal accessor (R1 W4 [API-NAME-002])
//
// The legacy `forEachPreOrder` / `forEachPostOrder` / `forEachLevelOrder` compound
// methods are replaced by the `forEach` fluent accessor (`tree.forEach.preOrder { }`).
// Read-only, so it is callable on a `let`/borrowing tree — built on
// `Property<Tag, Base>.Borrow`, the [PRP-001]-canonical mechanism (a bespoke
// borrowing view walls on 6.3.2; W4 probe-confirmed). The shared traversal logic
// lives in the `_forEach*` defaults (`__TreeProtocol+Defaults.swift`); this view is
// the public surface and forwards to them.

/// Phantom tag for the tree-family ``Tree/forEach`` view ([API-EXC-001] hoist, like
/// the other `__Tree*` types). Non-generic, so a single view ranges over every
/// conformer; use ``Tree/forEach`` at call sites, not this type.
public enum __TreeForEach {}

extension __TreeProtocol where Self: ~Copyable {
    /// The `Property` accessor-namespace alias for the tree family ([PRP-003]).
    public typealias Property<Tag> = Property_Primitives.Property<Tag, Self>

    /// Closure-based traversal: `tree.forEach.preOrder { }` / `.postOrder { }` /
    /// `.levelOrder { }` (plus `.inOrder` on binary `Tree.N`, `.child` / `.path` on
    /// `Tree.Keyed`). Read-only — callable on a `let` or borrowed tree.
    @inlinable
    public var forEach: Property<__TreeForEach>.Borrow {
        _read {
            yield Property<__TreeForEach>.Borrow(self)
        }
    }
}

// MARK: - Shared traversal orders (every conformer inherits these)

extension Property_Primitives.Property.Borrow
where Base: __TreeProtocol & ~Copyable, Tag == __TreeForEach {
    /// Visits every element in pre-order (root, then children left-to-right).
    @inlinable
    public func preOrder(_ body: (borrowing Base.Element) -> Void) {
        base.value._forEachPreOrder(body)
    }

    /// Visits every element in post-order (children left-to-right, then parent).
    @inlinable
    public func postOrder(_ body: (borrowing Base.Element) -> Void) {
        base.value._forEachPostOrder(body)
    }

    /// Visits every element in level-order (breadth-first).
    @inlinable
    public func levelOrder(_ body: (borrowing Base.Element) -> Void) {
        base.value._forEachLevelOrder(body)
    }
}
