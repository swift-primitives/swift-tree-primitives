public import Property_Primitives
public import Tree_Index_Primitives

public enum __TreeForEach {}

extension __TreeProtocol where Self: ~Copyable {

    public typealias Property<Tag> = Property_Primitives.Property<Tag, Self>

    @inlinable
    public var forEach: Property<__TreeForEach>.Borrow {
        _read {
            yield Property<__TreeForEach>.Borrow(self)
        }
    }
}

extension Property_Primitives.Property.Borrow
where Base: __TreeProtocol & ~Copyable, Tag == __TreeForEach {

    @inlinable
    public func preOrder(_ body: (borrowing Base.Element) -> Void) {
        base.value._forEachPreOrder(body)
    }

    @inlinable
    public func postOrder(_ body: (borrowing Base.Element) -> Void) {
        base.value._forEachPostOrder(body)
    }

    @inlinable
    public func levelOrder(_ body: (borrowing Base.Element) -> Void) {
        base.value._forEachLevelOrder(body)
    }
}
