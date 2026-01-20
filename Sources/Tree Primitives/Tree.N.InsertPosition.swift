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
// Swift does not allow nested types with value generic parameters inside
// generic types to be easily accessed. `InsertPosition` is hoisted to module
// level and exposed via typealias to provide the expected Nest.Name API.
//
// This is a documented exception per [API-EXC-001] due to Swift language
// limitations with generic nested types containing value generics.
//
// Use the typealias form in your code: Tree<Element>.N<n>.InsertPosition

/// Hoisted implementation of ``Tree/N/InsertPosition``.
///
/// Specifies where to insert a new node in an n-ary tree.
///
/// ## No appendChild
///
/// Per [TREE-010], `Tree<Element>.N<n>` does not provide `.appendChild(of:)` -
/// only explicit `.child(of:slot:)`. This keeps bounded-arity semantics honest
/// (no implicit slot selection).
///
/// - Note: Use ``Tree/N/InsertPosition`` in your code, not this type directly.
public enum __TreeNInsertPosition<let n: Int>: Sendable, Equatable {
    /// Insert as the root of the tree.
    case root

    /// Insert as a child of the given position at the specified slot.
    ///
    /// - Parameters:
    ///   - position: The parent position.
    ///   - slot: The child slot index (0..<n).
    case child(of: Tree.Position, slot: __TreeNChildSlot<n>)
}

// MARK: - Binary Tree Convenience (n == 2)

extension __TreeNInsertPosition where n == 2 {

    /// Insert as the left child of the given position.
    ///
    /// Convenience for `.child(of: position, slot: .left)`.
    @inlinable
    public static func left(of position: Tree.Position) -> Self {
        .child(of: position, slot: .left)
    }

    /// Insert as the right child of the given position.
    ///
    /// Convenience for `.child(of: position, slot: .right)`.
    @inlinable
    public static func right(of position: Tree.Position) -> Self {
        .child(of: position, slot: .right)
    }
}

// MARK: - Ternary Tree Convenience (n == 3)

extension __TreeNInsertPosition where n == 3 {

    /// Insert as the left child of the given position.
    @inlinable
    public static func left(of position: Tree.Position) -> Self {
        .child(of: position, slot: .left)
    }

    /// Insert as the middle child of the given position.
    @inlinable
    public static func middle(of position: Tree.Position) -> Self {
        .child(of: position, slot: .middle)
    }

    /// Insert as the right child of the given position.
    @inlinable
    public static func right(of position: Tree.Position) -> Self {
        .child(of: position, slot: .right)
    }
}

// MARK: - Quad Tree Convenience (n == 4)

extension __TreeNInsertPosition where n == 4 {

    /// Insert as the northwest child of the given position.
    @inlinable
    public static func northwest(of position: Tree.Position) -> Self {
        .child(of: position, slot: .northwest)
    }

    /// Insert as the northeast child of the given position.
    @inlinable
    public static func northeast(of position: Tree.Position) -> Self {
        .child(of: position, slot: .northeast)
    }

    /// Insert as the southwest child of the given position.
    @inlinable
    public static func southwest(of position: Tree.Position) -> Self {
        .child(of: position, slot: .southwest)
    }

    /// Insert as the southeast child of the given position.
    @inlinable
    public static func southeast(of position: Tree.Position) -> Self {
        .child(of: position, slot: .southeast)
    }
}
