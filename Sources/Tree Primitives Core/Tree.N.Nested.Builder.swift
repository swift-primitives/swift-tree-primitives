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

extension Tree.N.Nested where n == 2, Element: Copyable {
    /// A result builder for declaratively constructing nested Tree.Binary nodes.
    ///
    /// Used in two roles:
    ///
    /// 1. **Outer body** of the convenience init: produces a single-element
    ///    array containing the root `Node`. Multiple top-level expressions
    ///    trap with a precondition (binary trees have one root).
    ///
    /// 2. **Children block** inside `Node(_:children:)`: produces 0, 1, or
    ///    2 child Nodes. The first becomes the `.left` slot, the second
    ///    becomes the `.right` slot. More than 2 traps.
    ///
    /// The same builder enum serves both contexts — the constraint
    /// (one vs two-or-fewer) is enforced at the consumer (the convenience
    /// init or `Node.init`).
    ///
    /// ```swift
    /// let tree = Tree<Int>.Binary.Nested {
    ///     Node(1) {
    ///         Node(2) {
    ///             Node(4)
    ///             Node(5)
    ///         }
    ///         Node(3)
    ///     }
    /// }
    /// ```
    @resultBuilder
    public enum Builder {

        // MARK: - Expression Building

        @inlinable
        public static func buildExpression(_ expression: Node) -> [Node] {
            [expression]
        }

        @inlinable
        public static func buildExpression(_ expression: [Node]) -> [Node] {
            expression
        }

        @inlinable
        public static func buildExpression(_ expression: Node?) -> [Node] {
            expression.map { [$0] } ?? []
        }

        // MARK: - Partial Block Building

        @inlinable
        public static func buildPartialBlock(first: [Node]) -> [Node] {
            first
        }

        @inlinable
        public static func buildPartialBlock(first: Void) -> [Node] {
            []
        }

        @inlinable
        public static func buildPartialBlock(first: Never) -> [Node] {}

        @inlinable
        public static func buildPartialBlock(
            accumulated: [Node],
            next: [Node]
        ) -> [Node] {
            accumulated + next
        }

        // MARK: - Block Building

        @inlinable
        public static func buildBlock() -> [Node] {
            []
        }

        // MARK: - Control Flow

        @inlinable
        public static func buildOptional(_ component: [Node]?) -> [Node] {
            component ?? []
        }

        @inlinable
        public static func buildEither(first: [Node]) -> [Node] {
            first
        }

        @inlinable
        public static func buildEither(second: [Node]) -> [Node] {
            second
        }

        @inlinable
        public static func buildArray(_ components: [[Node]]) -> [Node] {
            components.flatMap { $0 }
        }

        @inlinable
        public static func buildLimitedAvailability(_ component: [Node]) -> [Node] {
            component
        }
    }
}

// MARK: - Convenience Init

extension Tree.N where n == 2, Element: Copyable {
    /// Constructs a Tree.Binary from a nested-DSL builder closure.
    ///
    /// The body declares exactly one root `Node`. Each Node may have 0, 1,
    /// or 2 children declared via `Node(value) { ... }`. First child →
    /// `.left`, second child → `.right`.
    ///
    /// Trapping preconditions:
    /// - Body must declare exactly 0 or 1 root nodes (zero = empty tree).
    /// - Each Node may have at most 2 children.
    ///
    /// ```swift
    /// let tree = Tree<Int>.Binary.Nested {
    ///     Node(1) {
    ///         Node(2)
    ///         Node(3)
    ///     }
    /// }
    /// ```
    ///
    /// - Complexity: O(n) where n is the number of nodes declared.
    ///
    /// - Note: Marked `@_disfavoredOverload` so empty-body call sites
    ///   (`Tree<Int>.N<2> { }`) and Element-literal call sites
    ///   (`Tree<Int>.N<2> { 1; 2; 3 }`) resolve to the Round-1 flat-BFS
    ///   builder. Node-literal call sites
    ///   (`Tree<Int>.N<2> { Node(1) { ... } }`) still resolve here,
    ///   since the Round-1 builder cannot accept Node expressions.
    @inlinable
    @_disfavoredOverload
    public init(
        @Tree<Element>.N<2>.Nested.Builder _ builder: () -> [Tree<Element>.N<2>.Nested.Node]
    ) {
        let roots = builder()
        precondition(
            roots.count <= 1,
            "Tree.Binary.Nested builder must declare at most 1 root node"
        )
        self.init()
        guard let root = roots.first else { return }
        let rootPos = try! self.insert(root.element, at: .root)
        Self._insertChildren(root.children, parent: rootPos, into: &self)
    }

    @inlinable
    static func _insertChildren(
        _ children: [Tree<Element>.N<2>.Nested.Node],
        parent: Tree.Position,
        into tree: inout Tree<Element>.N<2>
    ) {
        if children.count >= 1 {
            let leftNode = children[0]
            let leftPos = try! tree.insert(leftNode.element, at: .left(of: parent))
            _insertChildren(leftNode.children, parent: leftPos, into: &tree)
        }
        if children.count >= 2 {
            let rightNode = children[1]
            let rightPos = try! tree.insert(rightNode.element, at: .right(of: parent))
            _insertChildren(rightNode.children, parent: rightPos, into: &tree)
        }
    }
}

