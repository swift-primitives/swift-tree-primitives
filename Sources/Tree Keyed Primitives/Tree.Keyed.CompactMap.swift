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

extension Tree.Keyed where Value: Copyable {

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
}
