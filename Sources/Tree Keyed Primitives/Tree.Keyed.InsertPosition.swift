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

// MARK: - Hoisted InsertPosition Type (Module Level)
//
// Swift does not allow nested types inside generic types to be easily accessed.
// `InsertPosition` is hoisted to module level and exposed via typealias to
// provide the expected Nest.Name API.
//
// This is a documented exception per [API-EXC-001] due to Swift language
// limitations with generic nested types.
//
// Use the typealias form in your code: Tree.Keyed<Key, Value>.InsertPosition

/// Hoisted implementation of ``Tree/Keyed/InsertPosition``.
///
/// Specifies where to insert a new node in a keyed tree.
///
/// ## Keyed Children
///
/// Unlike bounded-arity trees (`Tree.N<n>`), keyed trees use dictionary keys
/// to identify children. Each child is associated with a unique key within
/// its parent's child set.
///
/// - Note: Use ``Tree/Keyed/InsertPosition`` in your code, not this type directly.
public enum __TreeKeyedInsertPosition<Key: Hash.`Protocol`> {
    /// Insert as the root of the tree.
    case root

    /// Insert as a child of the given position with the specified key.
    ///
    /// - Parameters:
    ///   - position: The parent position.
    ///   - key: The child key (must be unique among the parent's children).
    case child(of: Tree.Position, key: Key)
}

// MARK: - Conditional Sendable

extension __TreeKeyedInsertPosition: Sendable where Key: Sendable {}
