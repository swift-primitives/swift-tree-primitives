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

public import Storage_Generational_Primitives
public import Store_Primitive

// MARK: - The shared arena node (non-public arena detail)
//
// The generational-column slot type, generalized over the per-conformer child-
// link representation `ChildLinks` (dense `[Handle]` for the dynamic tree, sparse
// `InlineArray<n, Handle?>` for the n-ary tree, the ordered keyed dictionary for
// the keyed tree). This is an INTERNAL arena detail of `__TreeArena`: it never
// appears in any public signature (the public surface traffics in
// `Element` / `ChildLinks` / `Store.Generational.Handle` / `__TreePosition`),
// so it is `@usableFromInline`, not `public`. Conformers never name it.

@usableFromInline
struct __TreeNode<Element: ~Copyable, ChildLinks>: ~Copyable {
    /// The element stored in this node.
    @usableFromInline var element: Element
    /// The node's child links, in the conformer's representation.
    @usableFromInline var links: ChildLinks
    /// The handle of this node's parent (`nil` for the root).
    @usableFromInline var parentHandle: Store.Generational.Handle?

    @usableFromInline
    init(
        element: consuming Element,
        links: consuming ChildLinks,
        parentHandle: Store.Generational.Handle?
    ) {
        self.element = element
        self.links = links
        self.parentHandle = parentHandle
    }
}

extension __TreeNode: Copyable where Element: Copyable, ChildLinks: Copyable {}

// Conditionally Sendable when its stored element + links are (the parent handle is
// always Sendable). This is the foundation of the family's PROPER Sendable chain —
// `__TreeArena` → `Shared` → `Column.Generational` → here — so no tree type needs
// `@unchecked` ([MEM-SAFE-024]).
extension __TreeNode: Sendable where Element: Sendable, ChildLinks: Sendable {}
