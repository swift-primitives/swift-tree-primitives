public import Buffer_Ring_Primitive
public import Index_Primitives
public import Queue_Primitives
public import Stack_Primitives
public import Storage_Generational_Primitives
public import Store_Primitive
public import Tree_Index_Primitives
public import Tree_Primitive

extension __Tree where S: __TreeStorage & ~Copyable {

    public typealias Element = S.Element

    public typealias Address = S.Address

    public typealias Count = Index_Primitives.Index<S.Element>.Count

    public typealias InsertPosition = __TreeInsertPosition<S.Address>

    @inlinable
    public var count: Count {

        storage._count
    }

    @inlinable
    public func _position(of handle: Store.Generational.Handle) -> __TreePosition {
        __TreePosition(index: handle.index, token: UInt32(truncatingIfNeeded: handle.generation))
    }

    @inlinable
    package func _decode(
        _ position: __TreePosition
    ) throws(__TreeError) -> Store.Generational.Handle {
        guard let handle = storage._liveHandle(position) else { throw .invalidPosition }
        return handle
    }

    @inlinable
    public var isEmpty: Bool { storage._rootHandle == nil }

    @inlinable
    public var root: __TreePosition? {
        guard let rootHandle = storage._rootHandle else { return nil }
        return _position(of: rootHandle)
    }

    @inlinable
    public func validate(_ position: __TreePosition) throws(__TreeError) {
        _ = try _decode(position)
    }

    @inlinable
    public func _child(of position: __TreePosition, at address: S.Address) -> __TreePosition? {

        guard let handle = try? _decode(position),
            let childHandle = storage._childHandle(at: handle, address: address)
        else { return nil }
        return _position(of: childHandle)
    }

    @inlinable
    public func parent(of position: __TreePosition) -> __TreePosition? {

        guard let handle = try? _decode(position),
            let parentHandle = storage._parentHandle(of: handle)
        else { return nil }
        return _position(of: parentHandle)
    }

    @inlinable
    public func _childCount(at handle: Store.Generational.Handle) -> Int {
        storage._childCount(at: handle)
    }

    @inlinable
    public func _forEachChild(
        at handle: Store.Generational.Handle,
        _ body: (Store.Generational.Handle) -> Void
    ) {
        storage._forEachChild(at: handle, body)
    }

    @inlinable
    public func _liveHandle(_ position: __TreePosition) -> Store.Generational.Handle? {
        storage._liveHandle(position)
    }

    @inlinable
    public func isLeaf(_ position: __TreePosition) -> Bool {

        guard let handle = try? _decode(position) else { return false }
        return storage._childCount(at: handle) == 0
    }

    @inlinable
    public func peek<R: ~Copyable>(
        at position: __TreePosition,
        _ body: (borrowing S.Element) -> R
    ) -> R? {

        guard let handle = try? _decode(position) else { return nil }
        return storage._withElement(at: handle, body)
    }

    @inlinable
    public func _withElement<R: ~Copyable>(
        at handle: Store.Generational.Handle,
        _ body: (borrowing S.Element) -> R
    ) -> R {
        storage._withElement(at: handle, body)
    }

    @inlinable
    @discardableResult
    public mutating func withElementMut<R: ~Copyable>(
        at position: __TreePosition,
        _ body: (inout S.Element) -> R
    ) -> R? {

        guard let handle = try? _decode(position) else { return nil }
        return storage._withElementMut(at: handle, body)
    }

    @inlinable
    @discardableResult
    public mutating func insert(
        _ element: consuming S.Element,
        at position: __TreeInsertPosition<S.Address>
    ) throws(__TreeError) -> __TreePosition {
        switch position {
        case .root:
            guard storage._rootHandle == nil else { throw .rootOccupied }
            let handle = storage._insertNode(element, parent: nil)
            storage._rootHandle = handle
            return _position(of: handle)

        case .child(of: let parent, at: let address):
            let parentHandle = try _decode(parent)
            try storage._validateLink(to: parentHandle, at: address)
            let handle = storage._insertNode(element, parent: parentHandle)
            storage._linkChild(handle, to: parentHandle, at: address)
            return _position(of: handle)
        }
    }

    @inlinable
    @discardableResult
    public mutating func remove(at position: __TreePosition) throws(__TreeError) -> S.Element {
        let handle = try _decode(position)
        guard storage._childCount(at: handle) == 0 else { throw .cannotRemoveNonLeaf }
        if let parentHandle = storage._parentHandle(of: handle) {
            storage._unlinkChild(handle, from: parentHandle)
        } else {
            storage._rootHandle = nil
        }
        return storage._removeNode(handle)
    }

    @inlinable
    public mutating func clear() { storage._removeAll() }

    @inlinable
    public var height: Index_Primitives.Index<S.Element>.Count? {
        guard let rootHandle = storage._rootHandle else { return nil }
        var maxDepth = 0
        var pending = Stack<(handle: Store.Generational.Handle, depth: Int)>()
        pending.push((rootHandle, 0))
        while let (handle, depth) = pending.pop() {
            maxDepth = Swift.max(maxDepth, depth)
            storage._forEachChild(at: handle) { pending.push(($0, depth + 1)) }
        }
        return Index_Primitives.Index<S.Element>.Count(UInt(maxDepth))
    }

    @inlinable
    public mutating func removeSubtree(at position: __TreePosition) throws(__TreeError) {
        let handle = try _decode(position)
        if let parentHandle = storage._parentHandle(of: handle) {
            storage._unlinkChild(handle, from: parentHandle)
        } else {
            storage._rootHandle = nil
        }

        var pending = Stack<Store.Generational.Handle>()
        var output = Stack<Store.Generational.Handle>()
        pending.push(handle)
        while let current = pending.pop() {
            output.push(current)
            storage._forEachChild(at: current) { pending.push($0) }
        }
        while let current = output.pop() {
            _ = storage._removeNode(current)
        }
    }

    @inlinable
    public func _forEachPreOrder(_ body: (borrowing S.Element) -> Void) {
        guard let rootHandle = storage._rootHandle else { return }
        var pending = Stack<Store.Generational.Handle>()
        pending.push(rootHandle)
        while let current = pending.pop() {
            storage._withElement(at: current) { body($0) }
            var kids: [Store.Generational.Handle] = []
            storage._forEachChild(at: current) { kids.append($0) }
            (0..<kids.count).reversed().forEach { index in pending.push(kids[index]) }
        }
    }

    @inlinable
    public func _forEachPostOrder(_ body: (borrowing S.Element) -> Void) {
        guard let rootHandle = storage._rootHandle else { return }
        var pending = Stack<Store.Generational.Handle>()
        var output = Stack<Store.Generational.Handle>()
        pending.push(rootHandle)
        while let current = pending.pop() {
            output.push(current)
            storage._forEachChild(at: current) { pending.push($0) }
        }
        while let current = output.pop() {
            storage._withElement(at: current) { body($0) }
        }
    }

    @inlinable
    public func _forEachLevelOrder(_ body: (borrowing S.Element) -> Void) {
        guard let rootHandle = storage._rootHandle else { return }
        var pending = Queue<Store.Generational.Handle>()
        pending.enqueue(rootHandle)
        while let current = pending.dequeue() {
            storage._withElement(at: current) { body($0) }
            storage._forEachChild(at: current) { pending.enqueue($0) }
        }
    }
}

extension __Tree where S: __TreeStorage & ~Copyable, S.Element: Copyable {

    @inlinable
    public func peek(at position: __TreePosition) -> S.Element? {
        peek(at: position) { $0 }
    }
}

extension __Tree: __TreeProtocol where S: __TreeStorage & ~Copyable {}
