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

public import Queue_Dynamic_Primitives
internal import Stack_Primitives

// MARK: - In-Order Iterator

extension Tree.N.Order.In {

    /// An iterator for in-order traversal.
    ///
    /// Only available for binary trees (n == 2).
    public struct Iterator: Sequence_Primitives.Sequence.Iterator.`Protocol`, IteratorProtocol {
        @usableFromInline
        let tree: Tree.N<n>

        @usableFromInline
        var pending: Stack<Index<Tree.N<n>.Node>>

        @usableFromInline
        var current: Index<Tree.N<n>.Node>?

        @usableFromInline
        var _element: Element? = nil

        init(tree: Tree.N<n>) {
            self.tree = tree
            self.pending = Stack<Index<Tree.N<n>.Node>>()
            self.current = tree._rootIndex
        }

        @_lifetime(&self)
        @inlinable
        public mutating func nextSpan(maximumCount: Cardinal) -> Span<Element> {
            let ptr = unsafe withUnsafeMutablePointer(to: &_element) { p in
                unsafe UnsafePointer<Element>(
                    unsafe UnsafeRawPointer(p).assumingMemoryBound(to: Element.self)
                )
            }
            guard maximumCount > .zero else {
                let span = unsafe Span(_unsafeStart: ptr, count: 0)
                return unsafe _overrideLifetime(span, mutating: &self)
            }
            guard let value = next() else {
                let span = unsafe Span(_unsafeStart: ptr, count: 0)
                return unsafe _overrideLifetime(span, mutating: &self)
            }
            _element = value
            let span = unsafe Span(_unsafeStart: ptr, count: 1)
            return unsafe _overrideLifetime(span, mutating: &self)
        }

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
