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
public import Storage_Generational_Primitives
public import Store_Primitive
public import Tree_Index_Primitives

// MARK: - Tree.child — the child-navigation accessor (R1 W4 [API-NAME-002])
//
// Folds the legacy `child(of:at:)` navigation plus the compound `childCount` /
// `leftmostChild` / `rightmostChild` methods into the `child` fluent accessor
// (`tree.child.at(addr, of: pos)`, `.count(of:)`, `.leftmost(of:)` /
// `.rightmost(of:)`). Read-only `Property<Tag, Base>.Borrow`, callable on a
// `let`/borrow. `at` forwards to the shared `_child` default; `count` reads the
// `_childCount` requirement; `leftmost`/`rightmost` are added per-conformer (n-ary).

/// Phantom tag for the tree-family ``Tree/child`` view ([API-EXC-001] hoist).
public enum __TreeChild {}

extension __TreeProtocol where Self: ~Copyable {
    /// Child navigation: `tree.child.at(address, of: position)`, `.count(of:)`,
    /// and (n-ary) `.leftmost(of:)` / `.rightmost(of:)`.
    ///
    /// Read-only.
    @inlinable
    public var child: Property<__TreeChild>.Borrow {
        _read {
            yield Property<__TreeChild>.Borrow(self)
        }
    }
}

// MARK: - Shared child navigation (every conformer inherits these)

extension Property_Primitives.Property.Borrow
where Base: __TreeProtocol & ~Copyable, Tag == __TreeChild {
    /// The position of the child at `address`, or `nil` if absent / `position`
    /// invalid.
    ///
    /// `address` is the conformer's child domain (a child index for the
    /// dynamic tree, a bounded slot for `Tree.N`, a key for `Tree.Keyed`).
    @inlinable
    public func at(_ address: Base.Address, of position: __TreePosition) -> __TreePosition? {
        base.value._child(of: position, at: address)
    }

    /// The number of children of the node at `position`, or `nil` if invalid.
    @inlinable
    public func count(of position: __TreePosition) -> Int? {
        guard let handle = base.value._liveHandle(position) else { return nil }
        return base.value._childCount(at: handle)
    }

    /// The position of the first child of the node at `position`, or `nil` if it has
    /// no children / `position` is invalid.
    ///
    /// (For `Tree.N`, the first occupied slot;
    /// folds the legacy n-ary `leftmostChild`, generalized to every ordered tree.)
    @inlinable
    public func leftmost(of position: __TreePosition) -> __TreePosition? {
        guard let handle = base.value._liveHandle(position) else { return nil }
        var first: Store.Generational.Handle?
        base.value._forEachChild(at: handle) { if first == nil { first = $0 } }
        guard let first else { return nil }
        return base.value._position(of: first)
    }

    /// The position of the last child of the node at `position`, or `nil` if it has
    /// no children / `position` is invalid.
    ///
    /// (For `Tree.N`, the last occupied slot;
    /// folds the legacy n-ary `rightmostChild`, generalized to every ordered tree.)
    @inlinable
    public func rightmost(of position: __TreePosition) -> __TreePosition? {
        guard let handle = base.value._liveHandle(position) else { return nil }
        var last: Store.Generational.Handle?
        base.value._forEachChild(at: handle) { last = $0 }
        guard let last else { return nil }
        return base.value._position(of: last)
    }
}
