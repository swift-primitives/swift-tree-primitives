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

extension __TreeKeyedDiff {
    /// A single change between two keyed trees.
    public enum Operation {
        /// A node was added at the given path with the given value.
        case added(path: [Key], value: Value)

        /// A node was removed from the given path with the given value.
        case removed(path: [Key], value: Value)

        /// A node at the given path changed from `old` to `new`.
        case modified(path: [Key], old: Value, new: Value)
    }
}

// MARK: - Conditional Sendable

extension __TreeKeyedDiff.Operation: Sendable where Key: Sendable, Value: Sendable {}

// MARK: - Conditional Equatable

extension __TreeKeyedDiff.Operation: Equatable where Key: Equatable {}
