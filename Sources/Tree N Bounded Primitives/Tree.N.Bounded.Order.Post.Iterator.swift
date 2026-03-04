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
internal import Buffer_Arena_Primitives

// MARK: - Post-Order Iterator

extension Tree.N.Bounded.Order.Post {

    /// An iterator for post-order traversal.
    public struct Iterator: Sequence_Primitives.Sequence.Iterator.`Protocol`, IteratorProtocol {
        @usableFromInline
        let tree: Tree.N<Element, n>.Bounded

        @usableFromInline
        var pending: Stack<Index<Tree.N<Element, n>.Node>>

        @usableFromInline
        var lastVisited: Index<Tree.N<Element, n>.Node>?

        @usableFromInline
        var _element: Element? = nil

        init(tree: Tree.N<Element, n>.Bounded) {
            self.tree = tree
            self.pending = Stack<Index<Tree.N<Element, n>.Node>>()
            self.lastVisited = nil
            if let rootIndex = tree._rootIndex {
                pending.push(rootIndex)
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

        @_lifetime(self: immortal)
        @inlinable
        public mutating func next() -> Element? {
            while !pending.isEmpty {
                let current = pending.peek()!
                let nodePtr = unsafe tree._arena.pointer(at: current)
                let childIndices = unsafe nodePtr.pointee.childIndices

                var rightmostChild: Index<Tree.N<Element, n>.Node>? = nil
                for slot in stride(from: n - 1, through: 0, by: -1) {
                    if let child = childIndices[slot] {
                        rightmostChild = child
                        break
                    }
                }

                var leftmostChild: Index<Tree.N<Element, n>.Node>? = nil
                for slot in 0..<n {
                    if let child = childIndices[slot] {
                        leftmostChild = child
                        break
                    }
                }

                let isLeaf = rightmostChild == nil
                let cameFromRightmost = rightmostChild != nil && rightmostChild == lastVisited
                let cameFromLeftmostNoOther = leftmostChild != nil && leftmostChild == lastVisited && leftmostChild == rightmostChild

                if isLeaf || cameFromRightmost || cameFromLeftmostNoOther {
                    _ = pending.pop()
                    lastVisited = current
                    return unsafe nodePtr.pointee.element
                } else {
                    for slot in stride(from: n - 1, through: 0, by: -1) {
                        if let child = childIndices[slot] {
                            pending.push(child)
                        }
                    }
                }
            }

            return nil
        }
    }
}
