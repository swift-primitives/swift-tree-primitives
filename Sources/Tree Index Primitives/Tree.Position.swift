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

public import Index_Primitives
public import Tree_Primitive

// MARK: - Hoisted Position Type (Module Level)
//
// Position is hoisted to module level so it can be referenced by other hoisted
// types (__TreeNInsertPosition, __TreeKeyedInsertPosition,
// __TreeUnboundedInsertPosition) that cannot access Tree<Element>.Position.
//
// This is a documented exception per [API-EXC-001].
//
// Use the typealias form in your code: Tree<Element>.Position

/// Hoisted implementation of ``Tree/Position``.
///
/// A position (cursor) to a node in a tree. Shared across all tree variants.
///
/// - Note: Use ``Tree/Position`` in your code, not this type directly.
public struct __TreePosition: Sendable, Equatable, Hashable {

    /// The typed index of the node in the arena storage.
    public let index: Index<Self>

    /// Token for validity checking — the slot's generation projected into
    /// `UInt32` (`UInt32(truncatingIfNeeded: handle.generation)`); a position is
    /// live iff its token equals the slot's CURRENT projected generation.
    ///
    /// Wraps after 2^32 frees of one slot.
    public let token: UInt32

    /// Creates a position with the given typed index and token.
    @inlinable
    public init(index: Index<Self>, token: UInt32) {
        self.index = index
        self.token = token
    }

    /// Creates a position from any typed index, re-tagging to Position.
    ///
    /// Boundary overload per [IMPL-010]: `.retag()` lives here,
    /// not at call sites.
    @inlinable
    public init<T: ~Copyable & ~Escapable>(index: Index<T>, token: UInt32) {
        self.init(index: index.retag(Self.self), token: token)
    }

    /// Creates a position from a bare Int index.
    ///
    /// Boundary overload for Unbounded variant's Phase 5 bare-Int domain.
    @inlinable
    public init(index: Int, token: UInt32) {
        self.init(
            index: Index<Self>(Ordinal(UInt(index))),
            token: token
        )
    }
}

// MARK: - Typealias in Tree
//
// A NON-GENERIC namespaced typealias (no `S` capture) — the at-target reshape drops the
// `where Element: ~Copyable` constraint (the namespace's parameter is now the column `S`,
// and `Position` is column-agnostic).

extension Tree {
    /// A position (cursor) to a node in a tree.
    ///
    /// - SeeAlso: ``__TreePosition`` for the full documentation.
    public typealias Position = __TreePosition
}
