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
        let tree: Tree<Element>.Keyed<Key>

        @usableFromInline
        var pending: Queue<Index<Tree<Element>.Keyed<Key>.Node>>

        @usableFromInline
        var _element: Element? = nil

        init(tree: Tree<Element>.Keyed<Key>) {
            self.tree = tree
            self.pending = Queue<Index<Tree<Element>.Keyed<Key>.Node>>()

            if let rootIndex = tree._rootIndex {
                pending.enqueue(rootIndex)
            }
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
