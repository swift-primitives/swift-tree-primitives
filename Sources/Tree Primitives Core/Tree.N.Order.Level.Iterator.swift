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

// MARK: - Level-Order Iterator

extension Tree.N.Order.Level {

    /// An iterator for level-order traversal.
    public struct Iterator: Sequence_Primitives.Sequence.Iterator.`Protocol`, IteratorProtocol {
        @usableFromInline
        let tree: Tree.N<Element, n>

        @usableFromInline
        var pending: Queue<Index<Tree.N<Element, n>.Node>>

        @usableFromInline
        var _spanBuffer: [Element] = []

        init(tree: Tree.N<Element, n>) {
            self.tree = tree
            self.pending = Queue<Index<Tree.N<Element, n>.Node>>()

            if let rootIndex = tree._rootIndex {
                pending.enqueue(rootIndex)
            }
        }

        @_lifetime(&self)
        @inlinable
        public mutating func nextSpan(maximumCount: Cardinal) -> Span<Element> {
            _spanBuffer.removeAll(keepingCapacity: true)
            var remaining = Int(maximumCount.rawValue)
            while remaining > 0, !pending.isEmpty {
                let index = pending.dequeue()!
                let nodePtr = unsafe tree._arena.pointer(at: index)
                let element = unsafe nodePtr.pointee.element
                let childIndices = unsafe nodePtr.pointee.childIndices

                for slot in 0..<n {
                    if let child = childIndices[slot] {
                        pending.enqueue(child)
                    }
                }

                _spanBuffer.append(element)
                remaining -= 1
            }
            return _spanBuffer.span
        }

        @_lifetime(self: immortal)
        @inlinable
        public mutating func next() -> Element? {
            guard !pending.isEmpty else { return nil }

            let index = pending.dequeue()!
            let nodePtr = unsafe tree._arena.pointer(at: index)
            let element = unsafe nodePtr.pointee.element
            let childIndices = unsafe nodePtr.pointee.childIndices

            for slot in 0..<n {
                if let child = childIndices[slot] {
                    pending.enqueue(child)
                }
            }

            return element
        }
    }
}
