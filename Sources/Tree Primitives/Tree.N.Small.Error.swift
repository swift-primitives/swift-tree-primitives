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
// provide the expected Nest.Name API (Tree.N.Small.Error).
//
// This is a documented exception per [API-EXC-001] due to Swift language
// limitations with generic nested types.
//
// Use the typealias form in your code:
// - Tree<Element>.N<n>.Small.Error

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

    /// The element stride exceeds the inline storage slot size.
    case elementStrideTooLarge

    /// The element alignment exceeds the inline slot alignment.
    case elementAlignmentTooLarge
}

// MARK: - CustomStringConvertible

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
        case .elementStrideTooLarge:
            return "element stride exceeds inline storage slot size"
        case .elementAlignmentTooLarge:
            return "element alignment exceeds inline slot alignment"
        }
    }
}
