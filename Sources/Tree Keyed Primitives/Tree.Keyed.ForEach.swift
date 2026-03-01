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

// MARK: - ForEach with Key Path

extension Tree.Keyed where Value: Copyable {

    /// Iterates over all nodes in pre-order, passing the key path and value to the closure.
    ///
    /// Each node receives its full root-to-node key path. Children are visited
    /// in insertion order.
    ///
    /// - Parameter body: A closure called with the key path and value at each node.
    /// - Complexity: O(n) where n is the number of nodes.
    @inlinable
    public func forEach<E>(
        _ body: ([Key], Value) throws(E) -> Void
    ) throws(E) {
        guard let rootIndex = _rootIndex else { return }

        var pending = Stack<(index: Index<Node>, path: [Key])>()
        pending.push((rootIndex, []))

        while !pending.isEmpty {
            let (index, path) = pending.pop()!
            let nodePtr = unsafe _arena.pointer(at: index)
            try body(path, unsafe nodePtr.pointee.value)

            var children: [(key: Key, index: Index<Node>)] = []
            unsafe nodePtr.pointee._children.forEach { key, childIndex in
                children.append((key, childIndex))
            }
            for i in stride(from: children.count - 1, through: 0, by: -1) {
                var childPath = path
                childPath.append(children[i].key)
                pending.push((children[i].index, childPath))
            }
        }
    }

    /// Async variant of ``forEach(_:)-7k3x``.
    @inlinable
    public func forEach<E>(
        _ body: ([Key], Value) async throws(E) -> Void
    ) async throws(E) {
        guard let rootIndex = _rootIndex else { return }

        var pending = Stack<(index: Index<Node>, path: [Key])>()
        pending.push((rootIndex, []))

        while !pending.isEmpty {
            let (index, path) = pending.pop()!
            let nodePtr = unsafe _arena.pointer(at: index)
            try await body(path, unsafe nodePtr.pointee.value)

            var children: [(key: Key, index: Index<Node>)] = []
            unsafe nodePtr.pointee._children.forEach { key, childIndex in
                children.append((key, childIndex))
            }
            for i in stride(from: children.count - 1, through: 0, by: -1) {
                var childPath = path
                childPath.append(children[i].key)
                pending.push((children[i].index, childPath))
            }
        }
    }
}
