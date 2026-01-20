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

// MARK: - Hoisted Error Type (Module Level)
//
// Swift does not allow nested types inside generic types to be easily accessed.
// This error type is hoisted to module level and exposed via typealias to
// provide the expected Nest.Name API (Tree.Unbounded.Bounded.Error).
//
// This is a documented exception per [API-EXC-001] due to Swift language
// limitations with generic nested types.
//
// Use the typealias form in your code:
// - Tree.Unbounded<Element>.Bounded.Error

/// Hoisted implementation of ``Tree/Unbounded/Bounded/Error``.
///
/// - Note: Use ``Tree/Unbounded/Bounded/Error`` in your code, not this type directly.
public enum __TreeUnboundedBoundedError: Swift.Error, Sendable, Equatable {
    /// The requested capacity is invalid (negative).
    case invalidCapacity

    /// The tree is full and cannot accept more nodes.
    case overflow

    /// The tree is empty.
    case empty

    /// The specified position is invalid (stale or out of bounds).
    case invalidPosition

    /// The root position is already occupied.
    case rootOccupied

    /// The specified child index is out of bounds.
    case childIndexOutOfBounds

    /// Cannot remove a node that has children. Use `removeSubtree` instead.
    case cannotRemoveNonLeaf
}

// MARK: - CustomStringConvertible

extension __TreeUnboundedBoundedError: CustomStringConvertible {
    public var description: String {
        switch self {
        case .invalidCapacity:
            return "invalid capacity (negative)"
        case .overflow:
            return "tree is full"
        case .empty:
            return "tree is empty"
        case .invalidPosition:
            return "invalid position"
        case .rootOccupied:
            return "root position is already occupied"
        case .childIndexOutOfBounds:
            return "child index out of bounds"
        case .cannotRemoveNonLeaf:
            return "cannot remove non-leaf node; use removeSubtree instead"
        }
    }
}
