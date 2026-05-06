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

extension Tree.Unbounded.Nested where Element: Copyable {
    /// A result builder for declaratively constructing nested
    /// Tree.Unbounded nodes.
    ///
    /// Used in two roles:
    ///
    /// 1. **Outer body** of the convenience init: produces a single-element
    ///    array containing the root `Node`. Multiple top-level expressions
    ///    trap with a precondition.
    ///
    /// 2. **Children block** inside `Node(_:children:)`: produces 0+ child
    ///    Nodes, appended in declaration order.
    ///
    /// ```swift
    /// let tree = Tree<String>.Unbounded {
    ///     Node("root") {
    ///         Node("a") {
    ///             Node("a-1")
    ///             Node("a-2")
    ///         }
    ///         Node("b")
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

extension Tree.Unbounded where Element: Copyable {
    /// Constructs a Tree.Unbounded from a nested-DSL builder closure.
    ///
    /// The body declares exactly one root `Node`. Each Node may have any
    /// number of children declared via `Node(value) { ... }`; children
    /// are appended in declaration order.
    ///
    /// Trapping precondition: body must declare exactly 0 or 1 root nodes
    /// (zero = empty tree).
    ///
    /// ```swift
    /// let tree = Tree<String>.Unbounded {
    ///     Node("root") {
    ///         Node("a")
    ///         Node("b") {
    ///             Node("b-1")
    ///         }
    ///         Node("c")
    ///     }
    /// }
    /// ```
    ///
    /// - Complexity: O(n) where n is the number of nodes declared.
    ///
    /// - Note: Marked `@_disfavoredOverload` so empty-body call sites
    ///   (`Tree<String>.Unbounded { }`) and Element-literal call sites
    ///   (`Tree<String>.Unbounded { "a"; "b"; "c" }`) resolve to the
    ///   Round-1 flat builder. Node-literal call sites
    ///   (`Tree<String>.Unbounded { Node("root") { ... } }`) resolve
    ///   here.
    @inlinable
    @_disfavoredOverload
    public init(
        @Tree<Element>.Unbounded.Nested.Builder _ builder: () -> [Tree<Element>.Unbounded.Nested.Node]
    ) {
        let roots = builder()
        precondition(
            roots.count <= 1,
            "Tree.Unbounded.Nested builder must declare at most 1 root node"
        )
        self.init()
        guard let root = roots.first else { return }
        let rootPos = try! self.insert(root.element, at: .root)
        Self._insertChildren(root.children, parent: rootPos, into: &self)
    }

    @inlinable
    static func _insertChildren(
        _ children: [Tree<Element>.Unbounded.Nested.Node],
        parent: Tree.Position,
        into tree: inout Tree<Element>.Unbounded
    ) {
        for child in children {
            let pos = try! tree.insert(child.element, at: .appendChild(of: parent))
            _insertChildren(child.children, parent: pos, into: &tree)
        }
    }
}
