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

extension Tree.Keyed where Value: Equatable, Key: Copyable {
    /// Top-down keyed comparison — walks both trees in parallel by key.
    ///
    /// Produces a diff describing all structural and value changes between
    /// `old` and `new`. The algorithm is O(n+m) where n and m are the node
    /// counts of the two trees.
    ///
    /// - Parameters:
    ///   - old: The reference tree.
    ///   - new: The tree to compare against.
    /// - Returns: A diff describing added, removed, and modified nodes.
    public static func diff(
        from old: borrowing Self,
        to new: borrowing Self
    ) -> __TreeKeyedDiff<Key, Value> {
        typealias Operation = __TreeKeyedDiff<Key, Value>.Operation
        var operations: [Operation] = []

        switch (old.root, new.root) {
        case (nil, nil):
            break

        case (nil, let newRoot?):
            _collectSubtree(
                of: new,
                at: newRoot,
                path: []
            ) { operations.append(.added(path: $0, value: $1)) }

        case (let oldRoot?, nil):
            _collectSubtree(
                of: old,
                at: oldRoot,
                path: []
            ) { operations.append(.removed(path: $0, value: $1)) }

        case (let oldRoot?, let newRoot?):
            // Compare root values
            if let oldValue = old.peek(at: oldRoot),
               let newValue = new.peek(at: newRoot),
               oldValue != newValue
            {
                operations.append(.modified(path: [], old: oldValue, new: newValue))
            }

            // Iterative parallel walk
            var pending: [(
                oldPos: Tree.Position,
                newPos: Tree.Position,
                path: [Key]
            )] = [(oldRoot, newRoot, [])]

            while let (oldPos, newPos, path) = pending.popLast() {
                let oldChildren = old.children(of: oldPos) ?? []
                let newChildren = new.children(of: newPos) ?? []

                // Process children present in old
                for (key, oldChildPos) in oldChildren {
                    let childPath = path + [key]

                    if let newChildPos = new.child(of: newPos, key: key) {
                        // Key in both trees — compare values, recurse
                        if let oldValue = old.peek(at: oldChildPos),
                           let newValue = new.peek(at: newChildPos),
                           oldValue != newValue
                        {
                            operations.append(
                                .modified(path: childPath, old: oldValue, new: newValue)
                            )
                        }
                        pending.append((oldChildPos, newChildPos, childPath))
                    } else {
                        // Key only in old — removed subtree
                        _collectSubtree(
                            of: old,
                            at: oldChildPos,
                            path: childPath
                        ) { operations.append(.removed(path: $0, value: $1)) }
                    }
                }

                // Process children present only in new
                for (key, newChildPos) in newChildren {
                    if old.child(of: oldPos, key: key) == nil {
                        let childPath = path + [key]
                        _collectSubtree(
                            of: new,
                            at: newChildPos,
                            path: childPath
                        ) { operations.append(.added(path: $0, value: $1)) }
                    }
                }
            }
        }

        return .init(operations: operations)
    }
}

// MARK: - Subtree Collection

extension Tree.Keyed where Value: Copyable, Key: Copyable {
    /// Pre-order traversal of a subtree, emitting each node's path and value.
    @usableFromInline
    static func _collectSubtree(
        of tree: borrowing Self,
        at position: Tree.Position,
        path: [Key],
        emit: ([Key], Value) -> Void
    ) {
        var pending: [(position: Tree.Position, path: [Key])] = [(position, path)]

        while let (pos, currentPath) = pending.popLast() {
            if let value = tree.peek(at: pos) {
                emit(currentPath, value)
            }

            if let children = tree.children(of: pos) {
                // Push in reverse order so first child is processed first
                for (key, childPos) in children.reversed() {
                    pending.append((childPos, currentPath + [key]))
                }
            }
        }
    }
}
