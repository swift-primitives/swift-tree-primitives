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
// provide the expected Nest.Name API (Tree.Keyed.Error).
//
// This is a documented exception per [API-EXC-001] due to Swift language
// limitations with generic nested types.
//
// Use the typealias form in your code:
// - Tree.Keyed<Key, Value>.Error

/// Hoisted implementation of ``Tree/Keyed/Error``.
///
/// - Note: Use ``Tree/Keyed/Error`` in your code, not this type directly.
public enum __TreeKeyedError<Key: Hash.`Protocol`>: Swift.Error {
    /// The tree is empty.
    case empty

    /// The specified position is invalid (stale or out of bounds).
    case invalidPosition

    /// The root position is already occupied.
    case rootOccupied

    /// The specified child key is already occupied at the given parent.
    case keyOccupied(Key)

    /// The specified key was not found among a node's children.
    case keyNotFound(Key)

    /// Cannot remove a node that has children. Use `removeSubtree` instead.
    case cannotRemoveNonLeaf
}

// MARK: - CustomStringConvertible

extension __TreeKeyedError: CustomStringConvertible {
    public var description: String {
        switch self {
        case .empty:
            return "tree is empty"
        case .invalidPosition:
            return "invalid position"
        case .rootOccupied:
            return "root position is already occupied"
        case .keyOccupied(let key):
            return "child key '\(key)' is already occupied"
        case .keyNotFound(let key):
            return "child key '\(key)' not found"
        case .cannotRemoveNonLeaf:
            return "cannot remove non-leaf node; use removeSubtree instead"
        }
    }
}

// MARK: - Conditional Sendable

extension __TreeKeyedError: Sendable where Key: Sendable {}
