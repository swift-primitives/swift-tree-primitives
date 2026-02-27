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

/// Namespace for tree data structure primitives.
///
/// `Tree` serves as the organizational namespace for tree-related types.
/// All tree implementations are nested within this enum.
///
/// ## Available Types
///
/// - ``Tree/Binary``: A general-purpose binary tree
///
/// ## Example
///
/// ```swift
/// var tree = Tree.Binary<Int>()
/// let root = try tree.insert(1, at: .root)
/// let left = try tree.insert(2, at: .left(of: root))
/// let right = try tree.insert(3, at: .right(of: root))
/// ```
public enum Tree {}
