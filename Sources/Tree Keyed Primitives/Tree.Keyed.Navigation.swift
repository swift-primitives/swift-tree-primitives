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
// MARK: - Navigation

extension Tree.Keyed where Element: ~Copyable {

    /// Returns the position of the child with the given key.
    ///
    /// - Parameters:
    ///   - position: The position of the parent node.
    ///   - key: The child key to look up.
    /// - Returns: The position of the child, or `nil` if the key is not found.
    /// - Note: Returns `nil` if the position is invalid (stale or out of bounds).
    @inlinable
    public func child(of position: Tree.Position, key: Key) -> Tree.Position? {
        do {
            try _validate(position)
        } catch {
            return nil
        }
        let nodePtr = unsafe _arena.pointer(at: _slot(position.index))
        guard let childIndex = unsafe nodePtr.pointee._children[key] else { return nil }
        let token = _arena.token(at: childIndex)
        return Tree.Position(index: childIndex, token: token)
    }

    /// Returns the position of the parent of the node at the given position.
    ///
    /// - Parameter position: The position of the child node.
    /// - Returns: The position of the parent, or `nil` if the node is the root.
    /// - Note: Returns `nil` if the position is invalid (stale or out of bounds).
    @inlinable
    public func parent(of position: Tree.Position) -> Tree.Position? {
        do {
            try _validate(position)
        } catch {
            return nil
        }
        guard let parentIndex = unsafe _arena.pointer(at: _slot(position.index)).pointee.parentIndex else {
            return nil
        }
        let token = _arena.token(at: parentIndex)
        return Tree.Position(index: parentIndex, token: token)
    }

    /// Returns the key under which this node is stored in its parent.
    ///
    /// - Parameter position: The position of the node.
    /// - Returns: The parent key, or `nil` if the node is the root or position is invalid.
    @inlinable
    public func key(of position: Tree.Position) -> Key? {
        do {
            try _validate(position)
        } catch {
            return nil
        }
        return unsafe _arena.pointer(at: _slot(position.index)).pointee.parentKey
    }

    /// Returns whether the node at the given position is a leaf (has no children).
    ///
    /// - Parameter position: The position to check.
    /// - Returns: `true` if the node has no children, `false` otherwise.
    /// - Note: Returns `false` if the position is invalid (stale or out of bounds).
    @inlinable
    public func isLeaf(_ position: Tree.Position) -> Bool {
        do {
            try _validate(position)
        } catch {
            return false
        }
        return unsafe _arena.pointer(at: _slot(position.index)).pointee._children.isEmpty
    }

    /// Returns the number of children of the node at the given position.
    ///
    /// - Parameter position: The position to check.
    /// - Returns: The number of children, or `nil` if position is invalid.
    @inlinable
    public func childCount(of position: Tree.Position) -> Count? {
        do {
            try _validate(position)
        } catch {
            return nil
        }
        return unsafe _arena.pointer(at: _slot(position.index)).pointee._children.count.retag(Node.self)
    }

    /// Returns the keys and positions of all children of the node at the given position.
    ///
    /// Returns a snapshot array that is safe to iterate while mutating the tree.
    /// Positions remain valid across copy-on-write mutations because
    /// `Buffer.Arena.copy()` preserves all slot indices and generation tokens
    /// verbatim (see `Buffer.Arena Copyable.swift:24-37`).
    ///
    /// - Parameter position: The position of the parent node.
    /// - Returns: An array of (key, position) pairs in insertion order, or nil if position is invalid.
    @inlinable
    public func children(of position: Tree.Position) -> [(key: Key, position: Tree.Position)]? {
        do {
            try _validate(position)
        } catch {
            return nil
        }
        var result: [(key: Key, position: Tree.Position)] = []
        let nodePtr = unsafe _arena.pointer(at: _slot(position.index))
        unsafe nodePtr.pointee._children.forEach { key, childIndex in
            let token = _arena.token(at: childIndex)
            result.append((key, Tree.Position(index: childIndex, token: token)))
        }
        return result
    }

    /// Calls the given closure for each child of the node at the given position.
    ///
    /// Children are visited in insertion order.
    ///
    /// - Parameters:
    ///   - position: The position of the parent node.
    ///   - body: A closure called with each child's key and position.
    @inlinable
    public func forEachChild(
        of position: Tree.Position,
        _ body: (Key, Tree.Position) -> Void
    ) {
        do {
            try _validate(position)
        } catch {
            return
        }
        let nodePtr = unsafe _arena.pointer(at: _slot(position.index))
        unsafe nodePtr.pointee._children.forEach { key, childIndex in
            let token = _arena.token(at: childIndex)
            body(key, Tree.Position(index: childIndex, token: token))
        }
    }
}
