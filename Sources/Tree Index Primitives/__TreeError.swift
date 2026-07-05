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

public import Tree_Primitive

// MARK: - Hoisted shared tree error (module level)
//
// The shared, non-generic error for the tree family's common surface (the
// `Tree.Protocol` orchestration: insert / remove / decode). Hoisted to module
// level per [API-EXC-001] so the conformers (in separate packages) and the
// shared defaults can all name one error type. Keyed retains its own small
// generic error (`__TreeKeyedError<Key>`, W3) for its keyed-specific surface —
// `.keyOccupied(Key)` / `.keyNotFound(Key)` — which the shared, non-generic
// error cannot carry.
//
// Use ``Tree/Error`` (the per-conformer typealias) in your code, not this type
// directly.

/// Hoisted implementation of the shared tree error.
///
/// Errors raised by the shared `Tree.Protocol` operations.
///
/// - Note: Use the per-conformer `Error` typealias in your code (e.g.
///   ``Tree/Error``), not this type directly.
@frozen
public enum __TreeError: Swift.Error, Sendable, Equatable {
    /// The position does not refer to a live node (stale, or out of bounds).
    case invalidPosition
    /// A root insert was attempted while the tree already has a root.
    case rootOccupied
    /// A child slot is already occupied (bounded-arity / keyed trees).
    case slotOccupied
    /// A child index is out of bounds (dynamic-arity trees).
    case childIndexOutOfBounds
    /// A non-leaf node cannot be removed by `remove(at:)` (use `removeSubtree(at:)`).
    case cannotRemoveNonLeaf
}

// MARK: - Tree.Error — the column-agnostic namespaced alias
//
// The zero-dependency root `Tree<S>` (`Tree Primitive`) cannot name `__TreeError`
// (which carries no external deps but lives here, the addressing/seam foundation), so
// the alias attaches by extension from this sub-namespace — the Buffer-root model where
// disciplines attach to the namespace from their own target.

extension __Tree where S: ~Copyable {
    /// The error type for the shared tree operations.
    ///
    /// The `where S: ~Copyable` restatement keeps the alias reachable from move-only
    /// columns (the M1 alias-reachability discipline, [DS-028]).
    public typealias Error = __TreeError
}
