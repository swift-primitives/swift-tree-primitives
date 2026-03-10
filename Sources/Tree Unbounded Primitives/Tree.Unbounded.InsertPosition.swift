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
// Use the typealias form in your code: Tree.Unbounded<Element>.InsertPosition

/// Hoisted implementation of ``Tree/Unbounded/InsertPosition``.
///
/// Specifies where to insert a new node in an unbounded tree.
///
/// ## Dynamic Children
///
/// Unlike bounded-arity trees (`Tree.N<n>`), unbounded trees support:
/// - Inserting at a specific child index: `.child(of:at:)`
/// - Appending as the last child: `.appendChild(of:)`
///
/// - Note: Use ``Tree/Unbounded/InsertPosition`` in your code, not this type directly.
public enum __TreeUnboundedInsertPosition: Sendable, Equatable {
    /// Insert as the root of the tree.
    case root

    /// Insert as a child of the given position at the specified index.
    ///
    /// - Parameters:
    ///   - position: The parent position.
    ///   - index: The child index (0..<childCount inserts, childCount appends).
    case child(of: __TreePosition, at: Int)

    /// Append as the last child of the given position.
    ///
    /// Equivalent to `.child(of: position, at: childCount)`.
    case appendChild(of: __TreePosition)
}
