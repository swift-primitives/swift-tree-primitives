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

internal import Stack_Primitives

extension Tree.Keyed.Order.Post {

    /// An iterator for post-order traversal.
    ///
    /// Uses a two-stack approach: first builds reverse post-order via pre-order,
    /// then yields values in the correct order.
    public struct Iterator: Sequence_Primitives.Sequence.Iterator.`Protocol`, IteratorProtocol {
        @usableFromInline
        let tree: Tree.Keyed<Key, Value>

        @usableFromInline
        var output: Stack<Index<Tree.Keyed<Key, Value>.Node>>

        @usableFromInline
        var _spanBuffer: [Value] = []

        init(tree: Tree.Keyed<Key, Value>) {
            self.tree = tree
            self.output = Stack<Index<Tree.Keyed<Key, Value>.Node>>()

            // Build reverse post-order via pre-order traversal
            var pending = Stack<Index<Tree.Keyed<Key, Value>.Node>>()
            if let rootIndex = tree._rootIndex {
                pending.push(rootIndex)
            }

            while !pending.isEmpty {
                let index = pending.pop()!
                output.push(index)

                let nodePtr = unsafe tree._arena.pointer(at: index)
                unsafe nodePtr.pointee._children.forEach { _, childIndex in
                    pending.push(childIndex)
                }
            }
        }

        @_lifetime(&self)
        @inlinable
        public mutating func nextSpan(maximumCount: Cardinal) -> Span<Value> {
            _spanBuffer.removeAll(keepingCapacity: true)
            var remaining = Int(maximumCount.rawValue)
            while remaining > 0, !output.isEmpty {
                let index = output.pop()!
                let nodePtr = unsafe tree._arena.pointer(at: index)
                _spanBuffer.append(unsafe nodePtr.pointee.value)
                remaining -= 1
            }
            return _spanBuffer.span
        }

        @_lifetime(self: immortal)
        @inlinable
        public mutating func next() -> Value? {
            guard !output.isEmpty else { return nil }
            let index = output.pop()!
            let nodePtr = unsafe tree._arena.pointer(at: index)
            return unsafe nodePtr.pointee.value
        }
    }
}
