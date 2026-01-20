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

// MARK: - Hoisted ChildSlot Type (Module Level)
//
// Swift does not allow nested types with value generic parameters inside
// generic types to be easily accessed. `ChildSlot` is hoisted to module level
// and exposed via typealias to provide the expected Nest.Name API.
//
// This is a documented exception per [API-EXC-001] due to Swift language
// limitations with generic nested types containing value generics.
//
// Use the typealias form in your code: Tree<Element>.N<n>.ChildSlot

/// Hoisted implementation of ``Tree/N/ChildSlot``.
///
/// Represents a statically bounded child slot index for n-ary trees.
/// Valid slot indices are in the range `0..<n`.
///
/// ## Sparse Slot Semantics
///
/// Per [TREE-003], `Tree<Element>.N<n>` uses sparse child slots. Each node
/// stores `childIndices[0..<n]` where `-1` denotes empty. Holes are permitted.
/// This type ensures slot indices are within bounds at construction time.
///
/// - Note: Use ``Tree/N/ChildSlot`` in your code, not this type directly.
public struct __TreeNChildSlot<let n: Int>: Sendable, Equatable, Hashable {

    /// The slot index within the range `0..<n`.
    @usableFromInline
    let index: Int

    /// Creates a child slot from a raw index.
    ///
    /// - Parameter index: The slot index. Must be in range `0..<n`.
    /// - Returns: `nil` if the index is out of bounds.
    @inlinable
    public init?(_ index: Int) {
        guard index >= 0 && index < n else { return nil }
        self.index = index
    }

    /// Creates a child slot without bounds checking.
    ///
    /// - Warning: The caller must ensure `index` is in range `0..<n`.
    @usableFromInline
    init(__unchecked index: Int) {
        self.index = index
    }
}

// MARK: - Binary Tree Convenience (n == 2)

extension __TreeNChildSlot where n == 2 {

    /// The left child slot (index 0).
    @inlinable
    public static var left: Self { Self(__unchecked: 0) }

    /// The right child slot (index 1).
    @inlinable
    public static var right: Self { Self(__unchecked: 1) }
}

// MARK: - Ternary Tree Convenience (n == 3)

extension __TreeNChildSlot where n == 3 {

    /// The left child slot (index 0).
    @inlinable
    public static var left: Self { Self(__unchecked: 0) }

    /// The middle child slot (index 1).
    @inlinable
    public static var middle: Self { Self(__unchecked: 1) }

    /// The right child slot (index 2).
    @inlinable
    public static var right: Self { Self(__unchecked: 2) }
}

// MARK: - Quad Tree Convenience (n == 4)

extension __TreeNChildSlot where n == 4 {

    /// The northwest child slot (index 0).
    @inlinable
    public static var northwest: Self { Self(__unchecked: 0) }

    /// The northeast child slot (index 1).
    @inlinable
    public static var northeast: Self { Self(__unchecked: 1) }

    /// The southwest child slot (index 2).
    @inlinable
    public static var southwest: Self { Self(__unchecked: 2) }

    /// The southeast child slot (index 3).
    @inlinable
    public static var southeast: Self { Self(__unchecked: 3) }
}

// MARK: - CustomStringConvertible

extension __TreeNChildSlot: CustomStringConvertible {
    public var description: String {
        "ChildSlot(\(index))"
    }
}
