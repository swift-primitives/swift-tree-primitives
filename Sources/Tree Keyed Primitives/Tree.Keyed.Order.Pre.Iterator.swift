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

extension Tree.Keyed.Order.Pre {

    /// An iterator for pre-order traversal.
    public struct Iterator: Sequence_Primitives.Sequence.Iterator.`Protocol`, IteratorProtocol {
        @usableFromInline
        let tree: Tree.Keyed<Key, Value>

        @usableFromInline
        var pending: Stack<Index<Tree.Keyed<Key, Value>.Node>>

        @usableFromInline
        var _spanBuffer: [Value] = []

        init(tree: Tree.Keyed<Key, Value>) {
            self.tree = tree
            self.pending = Stack<Index<Tree.Keyed<Key, Value>.Node>>()
            if let rootIndex = tree._rootIndex {
                self.pending.push(rootIndex)
            }
        }

        @_lifetime(&self)
        @inlinable
        public mutating func nextSpan(maximumCount: Cardinal) -> Span<Value> {
            _spanBuffer.removeAll(keepingCapacity: true)
            var remaining = Int(maximumCount.rawValue)
            while remaining > 0, !pending.isEmpty {
                let index = pending.pop()!
                let nodePtr = unsafe tree._arena.pointer(at: index)
                let value = unsafe nodePtr.pointee.value

                // Collect children, push in reverse for correct order
                var childIndices: [Index<Tree.Keyed<Key, Value>.Node>] = []
                unsafe nodePtr.pointee._children.forEach { _, childIndex in
                    childIndices.append(childIndex)
                }
                for i in stride(from: childIndices.count - 1, through: 0, by: -1) {
                    pending.push(childIndices[i])
                }

                _spanBuffer.append(value)
                remaining -= 1
            }
            return _spanBuffer.span
        }

        @_lifetime(self: immortal)
        @inlinable
        public mutating func next() -> Value? {
            guard !pending.isEmpty else { return nil }

            let index = pending.pop()!
            let nodePtr = unsafe tree._arena.pointer(at: index)
            let value = unsafe nodePtr.pointee.value

            // Collect children, push in reverse for correct order
            var childIndices: [Index<Tree.Keyed<Key, Value>.Node>] = []
            unsafe nodePtr.pointee._children.forEach { _, childIndex in
                childIndices.append(childIndex)
            }
            for i in stride(from: childIndices.count - 1, through: 0, by: -1) {
                pending.push(childIndices[i])
            }

            return value
        }
    }
}
