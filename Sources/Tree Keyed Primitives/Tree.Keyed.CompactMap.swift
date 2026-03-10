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

// MARK: - Compact Map / Map to Array

extension Tree.Keyed where Element: Copyable {

    /// Returns an array of transformed values from a pre-order traversal.
    ///
    /// - Parameter transform: A closure that transforms each value.
    /// - Returns: An array of transformed values in pre-order.
    @inlinable
    public func map<U>(_ transform: (Value) -> U) -> [U] {
        var result: [U] = []
        forEachPreOrder { value in
            result.append(transform(value))
        }
        return result
    }

    /// Returns an array of non-nil transformed values from a pre-order traversal.
    ///
    /// - Parameter transform: A closure that optionally transforms each value.
    /// - Returns: An array of non-nil transformed values in pre-order.
    @inlinable
    public func compactMap<U>(_ transform: (Value) -> U?) -> [U] {
        var result: [U] = []
        forEachPreOrder { value in
            if let transformed = transform(value) {
                result.append(transformed)
            }
        }
        return result
    }

    // MARK: - Compact Map / Map with Key Path

    /// Returns an array of non-nil transformed values from a pre-order traversal,
    /// with key path context.
    ///
    /// Delegates to ``forEach(_:)-7k3x`` per [IMPL-033].
    ///
    /// - Parameter transform: A closure that receives the key path and value,
    ///   returning the new value or nil to exclude it.
    /// - Returns: An array of non-nil transformed values in pre-order.
    @inlinable
    public func compactMap<U, E>(
        _ transform: ([Key], Value) throws(E) -> U?
    ) throws(E) -> [U] {
        var result = [U]()
        try forEach { (path, value) throws(E) in
            if let newValue = try transform(path, value) {
                result.append(newValue)
            }
        }
        return result
    }

    /// Returns an array of transformed values from a pre-order traversal,
    /// with key path context.
    ///
    /// Delegates to ``compactMap(_:)-6p4z`` per [IMPL-033].
    ///
    /// - Parameter transform: A closure that receives the key path and value,
    ///   returning the new value.
    /// - Returns: An array of transformed values in pre-order.
    @inlinable
    public func map<U, E>(
        _ transform: ([Key], Value) throws(E) -> U
    ) throws(E) -> [U] {
        try compactMap(transform)
    }

    // MARK: - Compact Map / Map with Key Path (Async)

    /// Async variant of ``compactMap(_:)-6p4z``.
    @inlinable
    public func compactMap<U, E>(
        _ transform: ([Key], Value) async throws(E) -> U?
    ) async throws(E) -> [U] {
        var result = [U]()
        try await forEach { (path, value) async throws(E) in
            if let newValue = try await transform(path, value) {
                result.append(newValue)
            }
        }
        return result
    }

    /// Async variant of ``map(_:)-3v8k``.
    @inlinable
    public func map<U, E>(
        _ transform: ([Key], Value) async throws(E) -> U
    ) async throws(E) -> [U] {
        try await compactMap(transform)
    }
}
