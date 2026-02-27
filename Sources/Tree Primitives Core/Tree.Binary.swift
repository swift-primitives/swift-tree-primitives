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

extension Tree {
    /// A binary tree (2-ary tree).
    ///
    /// This is a typealias for `Tree.N<Element, 2>`.
    public typealias Binary<Element: ~Copyable> = Tree.N<Element, 2>
}
