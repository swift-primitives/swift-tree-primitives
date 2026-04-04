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


public import Queue_Dynamic_Primitives
// MARK: - Hoisted Diff Type (Module Level)
//
// Swift does not allow nested types inside generic types to be easily accessed.
// `Diff` is hoisted to module level and exposed via typealias to provide
// the expected Nest.Name API.
//
// This is a documented exception per [API-EXC-001] due to Swift language
// limitations with generic nested types.
//
// Use the typealias form in your code: Tree.Keyed<Key, Value>.Diff

/// Hoisted implementation of ``Tree/Keyed/Diff``.
///
/// Represents the set of structural and value differences between two
/// keyed trees. Produced by ``Tree/Keyed/diff(from:to:)``.
///
/// - Note: Use ``Tree/Keyed/Diff`` in your code, not this type directly.
public struct __TreeKeyedDiff<Key: Hash.`Protocol`, Value: Equatable> {
    /// The ordered list of operations describing all changes.
    public let operations: [Operation]

    /// Creates a diff from a list of operations.
    ///
    /// - Parameter operations: The change operations.
    public init(operations: [Operation]) {
        self.operations = operations
    }

    /// Whether the two trees were identical.
    public var isEmpty: Bool { operations.isEmpty }
}

// MARK: - Conditional Sendable

extension __TreeKeyedDiff: Sendable where Key: Sendable, Value: Sendable {}

// MARK: - Conditional Equatable

extension __TreeKeyedDiff: Equatable where Key: Equatable {}

// MARK: - Typealias

extension Tree.Keyed where Element: Equatable, Key: Copyable {
    /// The result of comparing two keyed trees.
    public typealias Diff = __TreeKeyedDiff<Key, Value>
}
