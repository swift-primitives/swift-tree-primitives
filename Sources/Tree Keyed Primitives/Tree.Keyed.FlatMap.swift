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

// MARK: - Flat Map

extension Tree.Keyed where Value: Copyable {

    /// Flat-maps each node's key path and value through the transform,
    /// concatenating the resulting sequences.
    ///
    /// Delegates to ``map(_:)-3v8k`` per [IMPL-033].
    ///
    /// - Parameter transform: A closure that receives the key path and value,
    ///   returning a sequence of elements.
    /// - Returns: A flat array of all elements from all returned sequences.
    @inlinable
    public func flatMap<S: Swift.Sequence, E>(
        _ transform: ([Key], Value) throws(E) -> S
    ) throws(E) -> [S.Element] {
        try map(transform).flatMap { $0 }
    }

    /// Async variant of ``flatMap(_:)-3k7x``.
    @inlinable
    public func flatMap<S: Swift.Sequence, E>(
        _ transform: ([Key], Value) async throws(E) -> S
    ) async throws(E) -> [S.Element] {
        try await map(transform).flatMap { $0 }
    }
}
