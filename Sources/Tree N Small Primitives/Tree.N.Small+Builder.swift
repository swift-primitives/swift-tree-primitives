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

extension Tree.N.Small where n == 2, Element: Copyable {
    /// Constructs a SmallVec binary tree from a result-builder closure.
    ///
    /// Wraps the dynamic `Tree<E>.N<2>.Builder`. Elements placed in BFS
    /// level-order. Throws on insertion errors per Tree.N.Small.Error.
    @_disfavoredOverload
    public init(
        @Tree<Element>.N<2>.Builder _ builder: () -> [Element]
    ) throws(Self.Error) {
        self.init()
        let elements = builder()
        guard !elements.isEmpty else { return }

        var positions: [Tree.Position] = []
        try positions.append(self.insert(elements[0], at: .root))

        var i = 1
        var parentIndex = 0
        while i < elements.count {
            let parent = positions[parentIndex]
            if i < elements.count {
                try positions.append(self.insert(elements[i], at: .left(of: parent)))
                i += 1
            }
            if i < elements.count {
                try positions.append(self.insert(elements[i], at: .right(of: parent)))
                i += 1
            }
            parentIndex += 1
        }
    }
}
