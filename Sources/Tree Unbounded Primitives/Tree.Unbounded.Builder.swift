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

extension Tree.Unbounded where Element: Copyable {
    /// A result builder for declaratively constructing unbounded-arity trees.
    ///
    /// Layout: the first declared element becomes the root; subsequent
    /// elements are appended as direct children of the root in declaration
    /// order:
    ///
    /// ```swift
    /// let tree = Tree<Int>.Unbounded {
    ///     1     // root
    ///     2     // root's first child
    ///     3     // root's second child
    ///     4     // root's third child
    /// }
    /// ```
    ///
    /// ## Deeper Trees
    ///
    /// This builder produces a flat single-root tree. For multi-level
    /// trees with grandchildren, use the imperative `insert(at:)` API
    /// directly:
    ///
    /// ```swift
    /// var tree = Tree<Int>.Unbounded {
    ///     1; 2; 3
    /// }
    /// let root = tree.root!
    /// let firstChild = tree.child(of: root, at: 0)!
    /// try tree.insert(99, at: .appendChild(of: firstChild))
    /// ```
    ///
    /// ## Element Constraint
    ///
    /// Tree.Unbounded.Builder requires `Element: Copyable` because the
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

extension Tree.Unbounded where Element: Copyable {
    /// Constructs a flat single-root unbounded tree from a result-builder closure.
    ///
    /// - First element becomes the root
    /// - Subsequent elements become direct children of the root in declaration order
    ///
    /// ```swift
    /// let tree = Tree<String>.Unbounded {
    ///     "root"
    ///     "child1"
    ///     "child2"
    ///     "child3"
    /// }
    /// ```
    ///
    /// For multi-level trees, use the imperative API after construction.
    ///
    /// - Complexity: O(n) where n is the number of elements declared.
    @inlinable
    public init(@Tree<Element>.Unbounded.Builder _ builder: () -> [Element]) {
        self.init()
        let elements = builder()
        guard !elements.isEmpty else { return }

        let root: Tree.Position = try! self.insert(elements[0], at: .root)
        for i in 1..<elements.count {
            try! self.insert(elements[i], at: .appendChild(of: root))
        }
    }
}
