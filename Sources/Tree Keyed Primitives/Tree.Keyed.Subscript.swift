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

// MARK: - Subscript (Read-Only)

extension Tree.Keyed where Element: Copyable {

    /// Returns the value at the given key path, or nil if the path doesn't resolve.
    ///
    /// - Parameter keyPath: The keys from root to the target node.
    /// - Returns: The value at the key path, or nil.
    /// - Complexity: O(d) where d is the length of the key path.
    @_disfavoredOverload
    @inlinable
    public subscript(keyPath: [Key]) -> Value? {
        value(at: keyPath)
    }

    /// Returns the value at the given key path, or nil if the path doesn't resolve.
    ///
    /// - Parameter keyPath: The keys from root to the target node.
    /// - Returns: The value at the key path, or nil.
    /// - Complexity: O(d) where d is the length of the key path.
    @_disfavoredOverload
    @inlinable
    public subscript(keyPath: Key...) -> Value? {
        self[keyPath]
    }
}

// MARK: - Subscript (Sparse)

extension Tree.Keyed where Element: Copyable {

    /// Gets or sets the value at the given key path in a sparse tree.
    ///
    /// On get, returns the value at the key path, or nil if the node doesn't exist.
    /// On set, creates the root and intermediate nodes with nil values as needed.
    ///
    /// For empty key path, targets the root node. Creates the root if needed.
    /// Assigns `Optional.none` explicitly when `newValue` is nil.
    ///
    /// - Parameter keyPath: The keys from root to the target node.
    /// - Returns: The value at the key path (which may itself be nil), or nil if the node doesn't exist.
    /// - Complexity: O(d) where d is the length of the key path.
    @inlinable
    public subscript<U>(keyPath: [Key]) -> Value where Value == U? {
        get {
            value(at: keyPath) ?? nil
        }
        set {
            if keyPath.isEmpty {
                if root != nil {
                    _ = try? update(newValue, at: keyPath)
                } else {
                    _ = try? insert(newValue, at: .root)
                }
            } else {
                _ = try? insert(newValue, at: keyPath)
            }
        }
    }

    /// Gets or sets the value at the given key path in a sparse tree.
    ///
    /// Variadic overload of ``subscript(_:)-2k3j``.
    @inlinable
    public subscript<U>(keyPath: Key...) -> Value where Value == U? {
        get { self[keyPath] }
        set { self[keyPath] = newValue }
    }
}

// MARK: - Sparse Insert Convenience

extension Tree.Keyed where Element: Copyable {

    /// Inserts a value at the given key path, creating intermediate nodes with nil values.
    ///
    /// If the tree is empty, creates the root with nil. If intermediate nodes along
    /// the path don't exist, they are created with nil values.
    ///
    /// Returns the position of the inserted (or updated) node. Unlike Graph's
    /// `insertValue` which returns the old value, Tree.Keyed returns the position
    /// for consistency with position-based navigation.
    ///
    /// - Parameters:
    ///   - value: The value to insert at the terminal key.
    ///   - keyPath: The keys from root to the insertion point.
    /// - Returns: The position of the inserted or updated node.
    @inlinable
    @discardableResult
    public mutating func insert<U>(
        _ value: Value,
        at keyPath: [Key]
    ) throws(__TreeKeyedError<Key>) -> Tree.Position where Value == U? {
        if keyPath.isEmpty {
            if root != nil {
                try update(value, at: keyPath)
                return root!
            } else {
                return try insert(value, at: .root)
            }
        }
        return try insert(value, at: keyPath, intermediateValue: { _ in nil })
    }
}
