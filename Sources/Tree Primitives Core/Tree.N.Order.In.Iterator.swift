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

// MARK: - In-Order Iterator

extension Tree.N.Order.In {

    /// An iterator for in-order traversal.
    ///
    /// Only available for binary trees (n == 2).
    public struct Iterator: Sequence_Primitives.Sequence.Iterator.`Protocol`, IteratorProtocol {
        @usableFromInline
        let tree: Tree.N<Element, n>

        @usableFromInline
        var pending: Stack<Index<Tree.N<Element, n>.Node>>

        @usableFromInline
        var current: Index<Tree.N<Element, n>.Node>?

        @usableFromInline
        var _spanBuffer: [Element] = []

        init(tree: Tree.N<Element, n>) {
            self.tree = tree
            self.pending = Stack<Index<Tree.N<Element, n>.Node>>()
            self.current = tree._rootIndex
        }

        @_lifetime(&self)
        @inlinable
        public mutating func nextSpan(maximumCount: Cardinal) -> Span<Element> {
            _spanBuffer.removeAll(keepingCapacity: true)
            var remaining = Int(maximumCount.rawValue)
            while remaining > 0 {
                while let c = current {
                    pending.push(c)
                    current = unsafe tree._arena.pointer(at: c).pointee.childIndices[0]
                }

                guard !pending.isEmpty else { break }

                let c = pending.pop()!
                let nodePtr = unsafe tree._arena.pointer(at: c)
                let element = unsafe nodePtr.pointee.element
                current = unsafe nodePtr.pointee.childIndices[1]

                _spanBuffer.append(element)
                remaining -= 1
            }
            return _spanBuffer.span
        }

        @_lifetime(self: immortal)
        @inlinable
        public mutating func next() -> Element? {
            while current != nil || !pending.isEmpty {
                // Go to leftmost node
                while let c = current {
                    pending.push(c)
                    current = unsafe tree._arena.pointer(at: c).pointee.childIndices[0]
                }

                // Process node
                let c = pending.pop()!
                let nodePtr = unsafe tree._arena.pointer(at: c)
                let element = unsafe nodePtr.pointee.element

                // Move to right subtree
                current = unsafe nodePtr.pointee.childIndices[1]

                return element
            }

            return nil
        }
    }
}
