public import Column_Primitives
public import Index_Primitives
public import Ownership_Shared_Primitive
public import Storage_Generational_Primitives
public import Store_Primitive
public import Tree_Index_Primitives

@usableFromInline
struct __TreeArena<Element: ~Copyable, ChildLinks>: ~Copyable {

    @usableFromInline
    typealias Slot = __TreeNode<Element, ChildLinks>

    @usableFromInline
    var _column: Ownership.Shared<Slot, Column.Generational<Slot>>

    @usableFromInline
    var rootHandle: Store.Generational.Handle?

    @inlinable
    package init() {
        self._column = Ownership.Shared(Column.Generational<Slot>.create(slotCapacity: 1))
        self.rootHandle = nil
    }

    @inlinable
    package init() where Element: Copyable, ChildLinks: Copyable {
        self._column = Ownership.Shared(Column.Generational<Slot>.create(slotCapacity: 1))
        self.rootHandle = nil
    }

    @inlinable
    package init(minimumCapacity: Index<Element>.Count) {
        let slots = Index<Slot>.Count(UInt(Swift.max(Int(bitPattern: minimumCapacity), 1)))
        self._column = Ownership.Shared(Column.Generational<Slot>.create(slotCapacity: slots))
        self.rootHandle = nil
    }

    @inlinable
    package init(minimumCapacity: Index<Element>.Count)
    where Element: Copyable, ChildLinks: Copyable {
        let slots = Index<Slot>.Count(UInt(Swift.max(Int(bitPattern: minimumCapacity), 1)))
        self._column = Ownership.Shared(Column.Generational<Slot>.create(slotCapacity: slots))
        self.rootHandle = nil
    }

    @inlinable
    package var count: Index<Element>.Count {
        Index<Element>.Count(UInt(Int(bitPattern: _column.withColumn { $0.count })))
    }

    @inlinable
    package func liveHandle(_ position: __TreePosition) -> Store.Generational.Handle? {
        let slot = Int(bitPattern: position.index)
        guard
            slot >= 0,
            let handle = _column.withColumn({ $0.handle(at: Index<Slot>(Ordinal(UInt(slot)))) }),
            UInt32(truncatingIfNeeded: handle.generation) == position.token
        else { return nil }
        return handle
    }

    @inlinable
    package mutating func insertNode(
        _ element: consuming Element,
        links: consuming ChildLinks,
        parent: Store.Generational.Handle?
    ) -> Store.Generational.Handle {
        _column.withUnique(
            consuming: Slot(element: element, links: links, parentHandle: parent)
        ) { column, node -> Store.Generational.Handle in
            if column.count == column.capacity {
                let doubled = Index<Slot>.Count(UInt(2 &* Int(bitPattern: column.capacity)))
                column.grow(to: doubled)
            }
            return column.insert(node)
        }
    }

    @inlinable
    package mutating func removeNode(_ handle: Store.Generational.Handle) -> Element {
        guard let node = _column.withUnique({ $0.remove(handle) }) else {

            preconditionFailure("__TreeArena: live handle failed to resolve on removal")
        }
        return node.element
    }

    @inlinable
    package mutating func removeAll() {
        _column.withUnique { $0.removeAll() }
        rootHandle = nil
    }

    @inlinable
    package func parentHandle(of handle: Store.Generational.Handle) -> Store.Generational.Handle? {
        _column.withColumn { $0[handle].parentHandle }
    }

    @inlinable
    package func withElement<R: ~Copyable>(
        at handle: Store.Generational.Handle,
        _ body: (borrowing Element) -> R
    ) -> R {
        _column.withColumn { body($0[handle].element) }
    }

    @inlinable
    package func withLinks<R: ~Copyable>(
        at handle: Store.Generational.Handle,
        _ body: (borrowing ChildLinks) -> R
    ) -> R {
        _column.withColumn { body($0[handle].links) }
    }

    @inlinable
    package mutating func withLinksMut<R: ~Copyable>(
        at handle: Store.Generational.Handle,
        _ body: (inout ChildLinks) -> R
    ) -> R {
        _column.withUnique { body(&$0[handle].links) }
    }

    @inlinable
    package mutating func withElementMut<R: ~Copyable>(
        at handle: Store.Generational.Handle,
        _ body: (inout Element) -> R
    ) -> R {
        _column.withUnique { body(&$0[handle].element) }
    }
}

extension __TreeArena: Copyable where Element: Copyable, ChildLinks: Copyable {}

extension __TreeArena: Sendable where Element: Sendable, ChildLinks: Sendable {}
