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

internal import Queue_Primitives

extension Tree.Keyed.Order.Level {

    /// An iterator for level-order traversal.
    public struct Iterator: Sequence_Primitives.Sequence.Iterator.`Protocol`, IteratorProtocol {
        @usableFromInline
        let tree: Tree.Keyed<Key, Value>

        @usableFromInline
        var pending: Queue<Index<Tree.Keyed<Key, Value>.Node>>

        @usableFromInline
        var _spanBuffer: [Value] = []

        init(tree: Tree.Keyed<Key, Value>) {
            self.tree = tree
            self.pending = Queue<Index<Tree.Keyed<Key, Value>.Node>>()

            if let rootIndex = tree._rootIndex {
                pending.enqueue(rootIndex)
            }
        }

        @_lifetime(&self)
        @inlinable
        public mutating func nextSpan(maximumCount: Cardinal) -> Span<Value> {
            _spanBuffer.removeAll(keepingCapacity: true)
            var remaining = Int(maximumCount.rawValue)
            while remaining > 0, !pending.isEmpty {
                let index = pending.dequeue()!
                let nodePtr = unsafe tree._arena.pointer(at: index)
                let value = unsafe nodePtr.pointee.value

                unsafe nodePtr.pointee._children.forEach { _, childIndex in
                    pending.enqueue(childIndex)
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

            let index = pending.dequeue()!
            let nodePtr = unsafe tree._arena.pointer(at: index)
            let value = unsafe nodePtr.pointee.value

            unsafe nodePtr.pointee._children.forEach { _, childIndex in
                pending.enqueue(childIndex)
            }

            return value
        }
    }
}
