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
// provide the expected Nest.Name API (Tree.Binary.Error, Tree.Binary.Bounded.Error, etc.).
//
// This is a documented exception per [API-EXC-001] due to Swift language
// limitations with generic nested types.
//
// Use the typealias forms in your code:
// - Tree.Binary<Element>.Error
// - Tree.Binary<Element>.Bounded.Error
// - Tree.Binary<Element>.Inline.Error
// - Tree.Binary<Element>.Small.Error

/// Hoisted implementation of ``Tree/Binary/Error``.
///
/// - Note: Use ``Tree/Binary/Error`` in your code, not this type directly.
public enum __TreeBinaryError: Swift.Error, Sendable, Equatable {
    /// The tree is empty.
    case empty

    /// The specified position is invalid.
    case invalidPosition

    /// The specified position is already occupied.
    case positionOccupied

    /// The requested capacity is invalid (negative).
    case invalidCapacity

    /// Cannot remove a node that has children. Use `removeSubtree` instead.
    case cannotRemoveNonLeaf
}

/// Hoisted implementation of ``Tree/Binary/Bounded/Error``.
///
/// - Note: Use ``Tree/Binary/Bounded/Error`` in your code, not this type directly.
public enum __TreeBinaryBoundedError: Swift.Error, Sendable, Equatable {
    /// The requested capacity is invalid (negative).
    case invalidCapacity

    /// The tree is full and cannot accept more nodes.
    case overflow

    /// The tree is empty.
    case empty

    /// The specified position is invalid.
    case invalidPosition

    /// The specified position is already occupied.
    case positionOccupied

    /// Cannot remove a node that has children. Use `removeSubtree` instead.
    case cannotRemoveNonLeaf
}

/// Hoisted implementation of ``Tree/Binary/Inline/Error``.
///
/// - Note: Use ``Tree/Binary/Inline/Error`` in your code, not this type directly.
public enum __TreeBinaryInlineError: Swift.Error, Sendable, Equatable {
    /// The tree is full and cannot accept more nodes.
    case overflow

    /// The tree is empty.
    case empty

    /// The specified position is invalid.
    case invalidPosition

    /// The specified position is already occupied.
    case positionOccupied

    /// Cannot remove a node that has children. Use `removeSubtree` instead.
    case cannotRemoveNonLeaf
}

/// Hoisted implementation of ``Tree/Binary/Small/Error``.
///
/// - Note: Use ``Tree/Binary/Small/Error`` in your code, not this type directly.
public enum __TreeBinarySmallError: Swift.Error, Sendable, Equatable {
    /// The tree is empty.
    case empty

    /// The specified position is invalid.
    case invalidPosition

    /// The specified position is already occupied.
    case positionOccupied

    /// Cannot remove a node that has children. Use `removeSubtree` instead.
    case cannotRemoveNonLeaf
}

// MARK: - Typealiases (Nest.Name API)
//
// IMPORTANT: Extensions MUST include `where Element: ~Copyable` to prevent
// implicit Copyable constraint. This is a documented Swift compiler limitation.

extension Tree.Binary where Element: ~Copyable {
    /// Errors that can occur during binary tree operations.
    ///
    /// ## Cases
    ///
    /// - ``Error/empty``: The tree is empty.
    /// - ``Error/invalidPosition``: The specified position is invalid.
    /// - ``Error/positionOccupied``: The specified position is already occupied.
    /// - ``Error/invalidCapacity``: The requested capacity is invalid (negative).
    /// - ``Error/cannotRemoveNonLeaf``: Cannot remove a node that has children.
    public typealias Error = __TreeBinaryError
}

extension Tree.Binary.Bounded where Element: ~Copyable {
    /// Errors that can occur during bounded binary tree operations.
    ///
    /// ## Cases
    ///
    /// - ``Error/invalidCapacity``: The requested capacity is invalid (negative).
    /// - ``Error/overflow``: The tree is full and cannot accept more nodes.
    /// - ``Error/empty``: The tree is empty.
    /// - ``Error/invalidPosition``: The specified position is invalid.
    /// - ``Error/positionOccupied``: The specified position is already occupied.
    /// - ``Error/cannotRemoveNonLeaf``: Cannot remove a node that has children.
    public typealias Error = __TreeBinaryBoundedError
}

extension Tree.Binary.Inline where Element: ~Copyable {
    /// Errors that can occur during inline binary tree operations.
    ///
    /// ## Cases
    ///
    /// - ``Error/overflow``: The tree is full and cannot accept more nodes.
    /// - ``Error/empty``: The tree is empty.
    /// - ``Error/invalidPosition``: The specified position is invalid.
    /// - ``Error/positionOccupied``: The specified position is already occupied.
    /// - ``Error/cannotRemoveNonLeaf``: Cannot remove a node that has children.
    public typealias Error = __TreeBinaryInlineError
}

extension Tree.Binary.Small where Element: ~Copyable {
    /// Errors that can occur during small binary tree operations.
    ///
    /// ## Cases
    ///
    /// - ``Error/empty``: The tree is empty.
    /// - ``Error/invalidPosition``: The specified position is invalid.
    /// - ``Error/positionOccupied``: The specified position is already occupied.
    /// - ``Error/cannotRemoveNonLeaf``: Cannot remove a node that has children.
    public typealias Error = __TreeBinarySmallError
}

// MARK: - CustomStringConvertible

extension __TreeBinaryError: CustomStringConvertible {
    public var description: String {
        switch self {
        case .empty:
            return "tree is empty"
        case .invalidPosition:
            return "invalid position"
        case .positionOccupied:
            return "position is already occupied"
        case .invalidCapacity:
            return "invalid capacity (negative)"
        case .cannotRemoveNonLeaf:
            return "cannot remove non-leaf node; use removeSubtree instead"
        }
    }
}

extension __TreeBinaryBoundedError: CustomStringConvertible {
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
        case .positionOccupied:
            return "position is already occupied"
        case .cannotRemoveNonLeaf:
            return "cannot remove non-leaf node; use removeSubtree instead"
        }
    }
}

extension __TreeBinaryInlineError: CustomStringConvertible {
    public var description: String {
        switch self {
        case .overflow:
            return "tree is full"
        case .empty:
            return "tree is empty"
        case .invalidPosition:
            return "invalid position"
        case .positionOccupied:
            return "position is already occupied"
        case .cannotRemoveNonLeaf:
            return "cannot remove non-leaf node; use removeSubtree instead"
        }
    }
}

extension __TreeBinarySmallError: CustomStringConvertible {
    public var description: String {
        switch self {
        case .empty:
            return "tree is empty"
        case .invalidPosition:
            return "invalid position"
        case .positionOccupied:
            return "position is already occupied"
        case .cannotRemoveNonLeaf:
            return "cannot remove non-leaf node; use removeSubtree instead"
        }
    }
}
