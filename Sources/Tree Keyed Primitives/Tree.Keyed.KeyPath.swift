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

// MARK: - Key Path Operations

extension Tree.Keyed where Value: ~Copyable {

    /// Reconstructs the key path from the root to the given position.
    ///
    /// Walks up the parent chain collecting `parentKey` values, then reverses.
    ///
    /// - Parameter position: The position of the node.
    /// - Returns: The key path from root to node, or `nil` if position is invalid.
    ///   Returns an empty array for the root node.
    /// - Complexity: O(d) where d is the depth of the node.
    @inlinable
    public func keyPath(to position: Tree.Position) -> [Key]? {
        do {
            try _validate(position)
        } catch {
            return nil
        }

        var path: [Key] = []
        var current = _slot(position.index)

        while let parentKey = unsafe _arena.pointer(at: current).pointee.parentKey {
            path.append(parentKey)
            guard let parentIndex = unsafe _arena.pointer(at: current).pointee.parentIndex else {
                break
            }
            current = parentIndex
        }

        path.reverse()
        return path
    }

    /// Returns the position of the node at the given key path.
    ///
    /// - Parameter keyPath: The sequence of keys from root to the target node.
    /// - Returns: The position of the node, or `nil` if any key in the path is not found
    ///   or the tree is empty.
    /// - Complexity: O(d) where d is the length of the key path.
    @inlinable
    public func position(at keyPath: some Swift.Sequence<Key>) -> Tree.Position? {
        guard let rootIndex = _rootIndex else { return nil }

        var current = rootIndex
        for key in keyPath {
            let nodePtr = unsafe _arena.pointer(at: current)
            guard let childIndex = unsafe nodePtr.pointee._children[key] else {
                return nil
            }
            current = childIndex
        }

        let token = _arena.token(at: current)
        return Tree.Position(index: current, token: token)
    }
}

// MARK: - Key Path Operations (Copyable)

extension Tree.Keyed where Value: Copyable {

    /// Returns the value at the given key path.
    ///
    /// - Parameter keyPath: The sequence of keys from root to the target node.
    /// - Returns: The value at the key path, or `nil` if any key is not found.
    /// - Complexity: O(d) where d is the length of the key path.
    @inlinable
    public func value(at keyPath: some Swift.Sequence<Key>) -> Value? {
        guard let pos = position(at: keyPath) else { return nil }
        return peek(at: pos)
    }

    /// Replaces the value at the given key path.
    ///
    /// - Parameters:
    ///   - newValue: The new value.
    ///   - keyPath: The sequence of keys from root to the target node.
    /// - Throws: ``Error/invalidPosition`` if the key path does not resolve to a node.
    @inlinable
    public mutating func update(_ newValue: Value, at keyPath: some Swift.Sequence<Key>) throws(__TreeKeyedError<Key>) {
        guard let pos = position(at: keyPath) else {
            throw .invalidPosition
        }
        try update(at: pos, newValue)
    }

    /// Inserts a value at the given key path, creating intermediate nodes as needed.
    ///
    /// If intermediate nodes along the path do not exist, they are created with
    /// the value provided by `intermediateValue`. If the root does not exist,
    /// it is created using `intermediateValue` with the first key.
    ///
    /// - Parameters:
    ///   - value: The value to insert at the terminal key.
    ///   - keyPath: The sequence of keys from root to the insertion point.
    ///     Must be non-empty.
    ///   - intermediateValue: A closure that provides values for intermediate nodes
    ///     that need to be created. Called with the key of each intermediate node.
    /// - Returns: The position of the newly inserted (or updated) node.
    @inlinable
    @discardableResult
    public mutating func insert(
        _ value: Value,
        at keyPath: [Key],
        intermediateValue: (Key) -> Value
    ) throws(__TreeKeyedError<Key>) -> Tree.Position {
        makeUnique()
        precondition(!keyPath.isEmpty, "Key path must not be empty")

        // Ensure root exists
        if _rootIndex == nil {
            let arenaPos = _arena.insert(Node(value: intermediateValue(keyPath[0])))
            _rootIndex = arenaPos.slot
        }

        var currentIndex = _rootIndex!

        // Walk down to the parent of the terminal node, creating intermediates
        for i in 0..<(keyPath.count - 1) {
            let key = keyPath[i]
            let nodePtr = unsafe _arena.pointer(at: currentIndex)
            if let childIndex = unsafe nodePtr.pointee._children[key] {
                currentIndex = childIndex
            } else {
                let arenaPos = _arena.insert(
                    Node(value: intermediateValue(key), parentIndex: currentIndex, parentKey: key)
                )
                let parentPtr = unsafe _arena.pointer(at: currentIndex)
                unsafe (parentPtr.pointee._children.set(key, arenaPos.slot))
                currentIndex = arenaPos.slot
            }
        }

        // Insert or update terminal node
        let terminalKey = keyPath[keyPath.count - 1]
        let parentPtr = unsafe _arena.pointer(at: currentIndex)
        if let existingChild = unsafe parentPtr.pointee._children[terminalKey] {
            let childPtr = unsafe _arena.pointer(at: existingChild)
            unsafe (childPtr.pointee.value = value)
            let token = _arena.token(at: existingChild)
            return Tree.Position(index: existingChild, token: token)
        } else {
            let arenaPos = _arena.insert(
                Node(value: value, parentIndex: currentIndex, parentKey: terminalKey)
            )
            // Re-fetch parent pointer after possible growth
            let freshParentPtr = unsafe _arena.pointer(at: currentIndex)
            unsafe (freshParentPtr.pointee._children.set(terminalKey, arenaPos.slot))
            return Tree.Position(index: arenaPos.slot, token: arenaPos.token)
        }
    }
}
