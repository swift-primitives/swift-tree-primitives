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

// MARK: - Hoisted shared insert position (module level)
//
// Where to insert a new node, parameterized by the conformer's `Address` (a
// child index for dynamic trees, a bounded slot for n-ary trees, a key for keyed
// trees). Hoisted per [API-EXC-001] and surfaced per conformer as
// ``Tree/Protocol/InsertPosition``. Use the typealias form in your code.

/// Hoisted implementation of the shared tree insert position.
///
/// - Note: Use ``Tree/Protocol/InsertPosition`` in your code, not this type directly.
@frozen
public enum __TreeInsertPosition<Address> {
    /// Insert as the root (only valid when the tree is empty).
    case root
    /// Insert as a child of `position` at `address` (an index, slot, or key,
    /// per the conformer's `Address`).
    case child(of: __TreePosition, at: Address)
}
