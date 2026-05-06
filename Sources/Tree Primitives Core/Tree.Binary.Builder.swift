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

extension Tree.N where n == 2, Element: Copyable {
    /// A result builder for declaratively constructing binary trees.
    ///
    /// Each declared element is positioned in BFS (level-order) layout:
    /// the first element is the root, the next two are its left and right
    /// children, the next four are their children in order, and so on.
    /// This produces a *complete* binary tree from the declared sequence.
    ///
    /// ```swift
    /// let tree = Tree<Int>.Binary {
    ///     1     // root
    ///     2     // 1.left
    ///     3     // 1.right
    ///     4     // 2.left
    ///     5     // 2.right
    ///     6     // 3.left
    ///     7     // 3.right
    /// }
    /// ```
    ///
    /// Resulting tree:
    /// ```
    ///         1
    ///       /   \
    ///      2     3
    ///     / \   / \
    ///    4   5 6   7
    /// ```
    ///
    /// ## Sparse Trees
    ///
    /// This builder constructs *complete* binary trees (each level is
    /// fully filled). For sparse trees with missing children at specific
    /// positions, use the imperative `insert(at:)` API directly.
    ///
    /// ## Element Constraint
    ///
    /// Tree.Binary.Builder requires `Element: Copyable` because the
    /// builder uses `Swift.Array<Element>` as its intermediate. ~Copyable
    /// element support is a future ecosystem extension.
    @resultBuilder
    public enum Builder {

        // MARK: - Expression Building

        @inlinable
        public static func buildExpression(_ expression: Element) -> [Element] {
            [expression]
        }

        @inlinable
        public static func buildExpression(_ expression: [Element]) -> [Element] {
            expression
        }

        @inlinable
        public static func buildExpression(_ expression: Element?) -> [Element] {
            expression.map { [$0] } ?? []
        }

        // MARK: - Partial Block Building

        @inlinable
        public static func buildPartialBlock(first: [Element]) -> [Element] {
            first
        }

        @inlinable
        public static func buildPartialBlock(first: Void) -> [Element] {
            []
        }

        @inlinable
        public static func buildPartialBlock(first: Never) -> [Element] {}

        @inlinable
        public static func buildPartialBlock(
            accumulated: [Element],
            next: [Element]
        ) -> [Element] {
            accumulated + next
        }

        // MARK: - Block Building

        @inlinable
        public static func buildBlock() -> [Element] {
            []
        }

        // MARK: - Control Flow

        @inlinable
        public static func buildOptional(_ component: [Element]?) -> [Element] {
            component ?? []
        }

        @inlinable
        public static func buildEither(first: [Element]) -> [Element] {
            first
        }

        @inlinable
        public static func buildEither(second: [Element]) -> [Element] {
            second
        }

        @inlinable
        public static func buildArray(_ components: [[Element]]) -> [Element] {
            components.flatMap { $0 }
        }

        @inlinable
        public static func buildLimitedAvailability(_ component: [Element]) -> [Element] {
            component
        }
    }
}

// MARK: - Convenience Init

extension Tree.N where n == 2, Element: Copyable {
    /// Constructs a complete binary tree from a result-builder closure.
    ///
    /// Elements are placed in BFS level-order: first = root, next two =
    /// root's children (left, right), next four = grandchildren, etc.
    ///
    /// ```swift
    /// let tree = Tree<Int>.Binary {
    ///     1
    ///     2
    ///     3
    ///     4
    ///     5
    /// }
    /// // Root: 1, left: 2, right: 3, 2.left: 4, 2.right: 5
    /// ```
    ///
    /// - Complexity: O(n) where n is the number of elements declared.
    @inlinable
    public init(@Tree<Element>.N<2>.Builder _ builder: () -> [Element]) {
        self.init()
        let elements = builder()
        guard !elements.isEmpty else { return }

        // Insert root.
        var positions: [Tree.Position] = []
        try! positions.append(self.insert(elements[0], at: .root))

        // BFS level-order insert.
        var i = 1
        var parentIndex = 0
        while i < elements.count {
            let parent = positions[parentIndex]
            // Left child
            if i < elements.count {
                try! positions.append(self.insert(elements[i], at: .left(of: parent)))
                i += 1
            }
            // Right child
            if i < elements.count {
                try! positions.append(self.insert(elements[i], at: .right(of: parent)))
                i += 1
            }
            parentIndex += 1
        }
    }
}
