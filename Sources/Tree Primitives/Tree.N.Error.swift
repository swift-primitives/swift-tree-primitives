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

// MARK: - Hoisted Error Types (Module Level)
//
// Swift does not allow nested types inside generic types to be easily accessed.
// These error types are hoisted to module level and exposed via typealiases to
// provide the expected Nest.Name API (Tree.N.Error, Tree.N.Bounded.Error, etc.).
//
// This is a documented exception per [API-EXC-001] due to Swift language
// limitations with generic nested types.
//
// Use the typealias forms in your code:
// - Tree<Element>.N<n>.Error
// - Tree<Element>.N<n>.Bounded.Error
// - Tree<Element>.N<n>.Inline.Error
// - Tree<Element>.N<n>.Small.Error

/// Hoisted implementation of ``Tree/N/Error``.
///
/// - Note: Use ``Tree/N/Error`` in your code, not this type directly.
public enum __TreeNError: Swift.Error, Sendable, Equatable {
    /// The tree is empty.
    case empty

    /// The specified position is invalid (stale or out of bounds).
    case invalidPosition

    /// The specified child slot is already occupied.
    case slotOccupied

    /// The requested capacity is invalid (negative).
    case invalidCapacity

    /// Cannot remove a node that has children. Use `removeSubtree` instead.
    case cannotRemoveNonLeaf

    /// The specified child slot index is out of bounds for the tree's arity.
    case invalidSlot
}

/// Hoisted implementation of ``Tree/N/Bounded/Error``.
///
/// - Note: Use ``Tree/N/Bounded/Error`` in your code, not this type directly.
public enum __TreeNBoundedError: Swift.Error, Sendable, Equatable {
    /// The requested capacity is invalid (negative).
    case invalidCapacity

    /// The tree is full and cannot accept more nodes.
    case overflow

    /// The tree is empty.
    case empty

    /// The specified position is invalid (stale or out of bounds).
    case invalidPosition

    /// The specified child slot is already occupied.
    case slotOccupied

    /// Cannot remove a node that has children. Use `removeSubtree` instead.
    case cannotRemoveNonLeaf

    /// The specified child slot index is out of bounds for the tree's arity.
    case invalidSlot
}

/// Hoisted implementation of ``Tree/N/Inline/Error``.
///
/// - Note: Use ``Tree/N/Inline/Error`` in your code, not this type directly.
public enum __TreeNInlineError: Swift.Error, Sendable, Equatable {
    /// The tree is full and cannot accept more nodes.
    case overflow

    /// The tree is empty.
    case empty

    /// The specified position is invalid (stale or out of bounds).
    case invalidPosition

    /// The specified child slot is already occupied.
    case slotOccupied

    /// Cannot remove a node that has children. Use `removeSubtree` instead.
    case cannotRemoveNonLeaf

    /// The specified child slot index is out of bounds for the tree's arity.
    case invalidSlot
}

/// Hoisted implementation of ``Tree/N/Small/Error``.
///
/// - Note: Use ``Tree/N/Small/Error`` in your code, not this type directly.
public enum __TreeNSmallError: Swift.Error, Sendable, Equatable {
    /// The tree is empty.
    case empty

    /// The specified position is invalid (stale or out of bounds).
    case invalidPosition

    /// The specified child slot is already occupied.
    case slotOccupied

    /// Cannot remove a node that has children. Use `removeSubtree` instead.
    case cannotRemoveNonLeaf

    /// The specified child slot index is out of bounds for the tree's arity.
    case invalidSlot
}

// MARK: - CustomStringConvertible

extension __TreeNError: CustomStringConvertible {
    public var description: String {
        switch self {
        case .empty:
            return "tree is empty"
        case .invalidPosition:
            return "invalid position"
        case .slotOccupied:
            return "child slot is already occupied"
        case .invalidCapacity:
            return "invalid capacity (negative)"
        case .cannotRemoveNonLeaf:
            return "cannot remove non-leaf node; use removeSubtree instead"
        case .invalidSlot:
            return "child slot index out of bounds"
        }
    }
}

extension __TreeNBoundedError: CustomStringConvertible {
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
        case .slotOccupied:
            return "child slot is already occupied"
        case .cannotRemoveNonLeaf:
            return "cannot remove non-leaf node; use removeSubtree instead"
        case .invalidSlot:
            return "child slot index out of bounds"
        }
    }
}

extension __TreeNInlineError: CustomStringConvertible {
    public var description: String {
        switch self {
        case .overflow:
            return "tree is full"
        case .empty:
            return "tree is empty"
        case .invalidPosition:
            return "invalid position"
        case .slotOccupied:
            return "child slot is already occupied"
        case .cannotRemoveNonLeaf:
            return "cannot remove non-leaf node; use removeSubtree instead"
        case .invalidSlot:
            return "child slot index out of bounds"
        }
    }
}

extension __TreeNSmallError: CustomStringConvertible {
    public var description: String {
        switch self {
        case .empty:
            return "tree is empty"
        case .invalidPosition:
            return "invalid position"
        case .slotOccupied:
            return "child slot is already occupied"
        case .cannotRemoveNonLeaf:
            return "cannot remove non-leaf node; use removeSubtree instead"
        case .invalidSlot:
            return "child slot index out of bounds"
        }
    }
}
