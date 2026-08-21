public import Index_Primitives
public import Storage_Generational_Primitives
public import Store_Primitive
public import Tree_Index_Primitives
public import Tree_Primitive

extension TreeStorage {

    public struct Dynamic<Element: ~Copyable>: ~Copyable {

        @usableFromInline
        var _arena: __TreeArena<Element, [Store.Generational.Handle]>

        @inlinable
        public init() { _arena = __TreeArena<Element, [Store.Generational.Handle]>() }

        @inlinable
        public init(minimumCapacity: Index<Element>.Count) {
            _arena = __TreeArena<Element, [Store.Generational.Handle]>(
                minimumCapacity: minimumCapacity
            )
        }

        @inlinable
        public init() where Element: Copyable {
            _arena = __TreeArena<Element, [Store.Generational.Handle]>()
        }

        @inlinable
        public init(minimumCapacity: Index<Element>.Count) where Element: Copyable {
            _arena = __TreeArena<Element, [Store.Generational.Handle]>(
                minimumCapacity: minimumCapacity
            )
        }
    }
}

extension TreeStorage.Dynamic where Element: ~Copyable {

    public typealias Address = Index<Self>
}

extension TreeStorage.Dynamic: __TreeStorage where Element: ~Copyable {

    @inlinable
    public var _count: Index<Element>.Count { _arena.count }

    @inlinable
    public var _rootHandle: Store.Generational.Handle? {
        get { _arena.rootHandle }
        set { _arena.rootHandle = newValue }
    }

    @inlinable
    public func _liveHandle(_ position: __TreePosition) -> Store.Generational.Handle? {
        _arena.liveHandle(position)
    }

    @inlinable
    public mutating func _insertNode(
        _ element: consuming Element,
        parent: Store.Generational.Handle?
    ) -> Store.Generational.Handle {
        _arena.insertNode(element, links: [], parent: parent)
    }

    @inlinable
    public mutating func _removeNode(_ handle: Store.Generational.Handle) -> Element {
        _arena.removeNode(handle)
    }

    @inlinable
    public mutating func _removeAll() { _arena.removeAll() }

    @inlinable
    public func _parentHandle(of handle: Store.Generational.Handle) -> Store.Generational.Handle? {
        _arena.parentHandle(of: handle)
    }

    @inlinable
    public func _withElement<R: ~Copyable>(
        at handle: Store.Generational.Handle,
        _ body: (borrowing Element) -> R
    ) -> R {
        _arena.withElement(at: handle, body)
    }

    @inlinable
    public mutating func _withElementMut<R: ~Copyable>(
        at handle: Store.Generational.Handle,
        _ body: (inout Element) -> R
    ) -> R {
        _arena.withElementMut(at: handle, body)
    }

    @inlinable
    public func _childHandle(
        at handle: Store.Generational.Handle,
        address index: Index<Self>
    ) -> Store.Generational.Handle? {
        let i = Int(bitPattern: index)
        return _arena.withLinks(at: handle) { (i >= 0 && i < $0.count) ? $0[i] : nil }
    }

    @inlinable
    public func _validateLink(
        to parent: Store.Generational.Handle,
        at index: Index<Self>
    ) throws(__TreeError) {
        let i = Int(bitPattern: index)
        let childCount = _arena.withLinks(at: parent) { $0.count }
        guard i >= 0, i <= childCount else { throw .childIndexOutOfBounds }
    }

    @inlinable
    public mutating func _linkChild(
        _ child: Store.Generational.Handle,
        to parent: Store.Generational.Handle,
        at index: Index<Self>
    ) {
        let i = Int(bitPattern: index)
        _arena.withLinksMut(at: parent) { $0.insert(child, at: i) }
    }

    @inlinable
    public mutating func _unlinkChild(
        _ child: Store.Generational.Handle,
        from parent: Store.Generational.Handle
    ) {
        _arena.withLinksMut(at: parent) {
            if let position = $0.firstIndex(of: child) { $0.remove(at: position) }
        }
    }

    @inlinable
    public func _childCount(at handle: Store.Generational.Handle) -> Int {
        _arena.withLinks(at: handle) { $0.count }
    }

    @inlinable
    public func _forEachChild(
        at handle: Store.Generational.Handle,
        _ body: (Store.Generational.Handle) -> Void
    ) {
        _arena.withLinks(at: handle) { links in
            links.indices.forEach { index in body(links[index]) }
        }
    }
}

extension TreeStorage.Dynamic: Copyable where Element: Copyable {}

extension TreeStorage.Dynamic: Sendable where Element: Sendable {}

extension __Tree where S: ~Copyable {

    @inlinable
    public init<Element: ~Copyable>() where S == TreeStorage.Dynamic<Element> {
        self.init(storage: TreeStorage.Dynamic<Element>())
    }

    @inlinable
    public init<Element: ~Copyable>(minimumCapacity: Index_Primitives.Index<Element>.Count)
    where S == TreeStorage.Dynamic<Element> {
        self.init(storage: TreeStorage.Dynamic<Element>(minimumCapacity: minimumCapacity))
    }

    @inlinable
    public init<Element>() where S == TreeStorage.Dynamic<Element> {
        self.init(storage: TreeStorage.Dynamic<Element>())
    }

    @inlinable
    public init<Element>(minimumCapacity: Index_Primitives.Index<Element>.Count)
    where S == TreeStorage.Dynamic<Element> {
        self.init(storage: TreeStorage.Dynamic<Element>(minimumCapacity: minimumCapacity))
    }
}
