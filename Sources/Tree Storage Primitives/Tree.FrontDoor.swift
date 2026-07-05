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

public import Tree_Primitive

// MARK: - Tree<Element> — the CANONICAL front door ([DS-028])

/// A dynamic (unbounded-arity) tree over the default column: the dense ordered-children
/// generational arena.
///
/// This is the canonical front-door alias ([DS-028]) — the sanctioned [API-NAME-004]
/// generic-instantiation exception that pins the default column so consumers spell
/// `Tree<Element>`, never the carrier `__Tree` or a full column. The alias fully
/// specializes: conformances, the pinned constructors, and `~Copyable` elements all flow
/// through it with zero forwarding and zero runtime cost.
///
/// ```swift
/// var tree = Tree<String>()                        // growable dynamic tree (this alias)
/// let root = try tree.insert("root", at: .root)
/// let child = try tree.insert("child", at: .child(of: root, at: 0))
/// tree.forEach.preOrder { print($0) }              // root, child
/// ```
///
/// It supersedes the retired `TreeDynamic` compound ergonomic alias (§9.6.5,
/// [API-NAME-001] hygiene): the 6.3.2 frontend crash that forced the compound spelling
/// is fixed on 6.3.3, so the front door is the canonical name. Column variants live
/// behind nested aliases on the family: `Tree<Element>.Keyed<Key>` is the keyed column
/// (swift-tree-keyed-primitives); the bounded-arity `Tree<Element>.N<n>` door is pending
/// the tree-n column re-skeleton.
///
/// Supplied by this sub-namespace because it names the dynamic column
/// `TreeStorage.Dynamic` (the zero-dep root cannot).
public typealias Tree<Element: ~Copyable> = __Tree<TreeStorage.Dynamic<Element>>
