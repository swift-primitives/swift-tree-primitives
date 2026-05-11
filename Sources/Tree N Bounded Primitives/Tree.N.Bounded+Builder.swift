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

extension Tree.N.Bounded where n == 2, Element: Copyable {
    /// Constructs a heap-allocated bounded binary tree from a result-builder closure.
    ///
    /// Wraps the dynamic `Tree<E>.N<2>.Builder`. Elements placed in BFS
    /// level-order. Capacity at outer init; overflow throws.
    @_disfavoredOverload
    public init(
        capacity: Count,
        @Tree<Element>.N<2>.Builder _ builder: () -> [Element]
    ) throws(Tree.N.Bounded.Error) {
        var bounded = Tree<Element>.N<2>.Bounded(capacity: capacity)
        let elements = builder()
        guard !elements.isEmpty else {
            self = bounded
            return
        }

        var positions: [Tree.Position] = []
        try positions.append(bounded.insert(elements[0], at: .root))

        var i = 1
        var parentIndex = 0
        while i < elements.count {
            let parent = positions[parentIndex]
            if i < elements.count {
                try positions.append(bounded.insert(elements[i], at: .left(of: parent)))
                i += 1
            }
            if i < elements.count {
                try positions.append(bounded.insert(elements[i], at: .right(of: parent)))
                i += 1
            }
            parentIndex += 1
        }
        self = bounded
    }
}
