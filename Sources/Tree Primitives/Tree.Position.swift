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

extension Tree {

    /// A position (cursor) to a node in a tree.
    ///
    /// `Position` is a lightweight, type-safe handle for navigating and
    /// operating on tree nodes. Positions are invalidated when the referenced
    /// node is removed.
    ///
    /// ## Token-Based Validation
    ///
    /// Each position carries a token that is validated against the tree's internal
    /// token buffer before any node access. This provides O(1) safety checking:
    /// - Stale positions (after removal) are detected and rejected
    /// - No node memory is accessed without validation
    /// - Tokens use odd/even scheme: odd = occupied, even = free
    ///
    /// ## Usage
    ///
    /// `Position` is shared across all tree variants:
    /// - `Tree<Element>.N<n>` (bounded arity)
    /// - `Tree<Element>` (unbounded arity, future)
    ///
    /// This allows positions to be used uniformly regardless of tree arity.
    public struct Position: Sendable, Equatable, Hashable {

        /// The index of the node in the arena storage.
        @usableFromInline
        let index: Int

        /// Token for validity checking (odd = occupied, even = free).
        @usableFromInline
        let token: UInt32

        /// Creates a position with the given index and token.
        ///
        /// - Parameters:
        ///   - index: The arena index of the node.
        ///   - token: The validation token (must be odd for valid positions).
        @usableFromInline
        init(index: Int, token: UInt32) {
            self.index = index
            self.token = token
        }

        /// Creates a position from a typed index and token.
        ///
        /// Boundary overload per [IMPL-010]: `Int(bitPattern:)` lives here,
        /// not at call sites.
        @usableFromInline
        init<T: ~Copyable>(index: Index<T>, token: UInt32) {
            self.init(index: Int(bitPattern: index), token: token)
        }
    }
}
