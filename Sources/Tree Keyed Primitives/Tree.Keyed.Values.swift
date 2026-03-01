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

// MARK: - Values Along Key Path

extension Tree.Keyed where Value: Copyable {

    /// Returns values at each step along the key path.
    ///
    /// For each key in the path, yields the value at the child node reached
    /// by that key. If the child doesn't exist, yields nil. Once a missing
    /// child is encountered, all subsequent values are nil.
    ///
    /// Named `values(along:)` per [API-NAME-002] — Graph's `takeValues(at:)`
    /// is a compound name not in stdlib.
    ///
    /// - Parameter keyPath: The keys to walk from the root.
    /// - Returns: An array of optional values, one per key.
    /// - Complexity: O(d) where d is the length of the key path.
    @inlinable
    public func values(
        along keyPath: some Swift.Sequence<Key>
    ) -> [Value?] {
        guard let rootIndex = _rootIndex else { return [] }

        var result: [Value?] = []
        var currentIndex: Index<Node>? = rootIndex

        for key in keyPath {
            guard let index = currentIndex else {
                result.append(nil)
                continue
            }

            let nodePtr = unsafe _arena.pointer(at: index)
            if let childIndex = unsafe nodePtr.pointee._children[key] {
                let childPtr = unsafe _arena.pointer(at: childIndex)
                result.append(unsafe childPtr.pointee.value)
                currentIndex = childIndex
            } else {
                result.append(nil)
                currentIndex = nil
            }
        }

        return result
    }
}
