public import Property_Primitives
public import Storage_Generational_Primitives
public import Store_Primitive
public import Tree_Index_Primitives

public enum __TreeChild {}

extension __TreeProtocol where Self: ~Copyable {

    @inlinable
    public var child: Property<__TreeChild>.Borrow {
        _read {
            yield Property<__TreeChild>.Borrow(self)
        }
    }
}

extension Property_Primitives.Property.Borrow
where Base: __TreeProtocol & ~Copyable, Tag == __TreeChild {

    @inlinable
    public func at(_ address: Base.Address, of position: __TreePosition) -> __TreePosition? {
        base.value._child(of: position, at: address)
    }

    @inlinable
    public func count(of position: __TreePosition) -> Int? {
        guard let handle = base.value._liveHandle(position) else { return nil }
        return base.value._childCount(at: handle)
    }

    @inlinable
    public func leftmost(of position: __TreePosition) -> __TreePosition? {
        guard let handle = base.value._liveHandle(position) else { return nil }
        var first: Store.Generational.Handle?
        base.value._forEachChild(at: handle) { if first == nil { first = $0 } }
        guard let first else { return nil }
        return base.value._position(of: first)
    }

    @inlinable
    public func rightmost(of position: __TreePosition) -> __TreePosition? {
        guard let handle = base.value._liveHandle(position) else { return nil }
        var last: Store.Generational.Handle?
        base.value._forEachChild(at: handle) { last = $0 }
        guard let last else { return nil }
        return base.value._position(of: last)
    }
}
