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

internal import Queue_Primitives_Core
public import Queue_Dynamic_Primitives
internal import Buffer_Arena_Primitives

// MARK: - Level-Order Iterator

extension Tree.N.Bounded.Order.Level {

    /// An iterator for level-order traversal.
    public struct Iterator: Sequence_Primitives.Sequence.Iterator.`Protocol`, IteratorProtocol {
        @usableFromInline
        let tree: Tree.N<n>.Bounded

        @usableFromInline
        var pending: Queue<Index<Tree.N<n>.Node>>

        @usableFromInline
        var _element: Element? = nil

        init(tree: Tree.N<n>.Bounded) {
            self.tree = tree
            self.pending = Queue<Index<Tree.N<n>.Node>>()
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
            let element = unsafe nodePtr.pointee.element

            for slot in 0..<n {
                if let child = unsafe nodePtr.pointee.childIndices[slot] {
                    pending.enqueue(child)
                }
            }

            return element
        }
    }
}
