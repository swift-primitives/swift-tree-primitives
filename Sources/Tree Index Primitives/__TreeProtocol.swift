public import Storage_Generational_Primitives
public import Store_Primitive
import Tree_Primitive

public protocol Traversable: ~Copyable {

    associatedtype Element: ~Copyable

    associatedtype Address

    var isEmpty: Bool { get }

    var root: __TreePosition? { get }

    func _position(of handle: Store.Generational.Handle) -> __TreePosition

    func _liveHandle(_ position: __TreePosition) -> Store.Generational.Handle?

    func _child(of position: __TreePosition, at address: Address) -> __TreePosition?

    func _childCount(at handle: Store.Generational.Handle) -> Int

    func _forEachChild(
        at handle: Store.Generational.Handle,
        _ body: (Store.Generational.Handle) -> Void
    )

    func _withElement<R: ~Copyable>(
        at handle: Store.Generational.Handle,
        _ body: (borrowing Element) -> R
    ) -> R

    func _forEachPreOrder(_ body: (borrowing Element) -> Void)

    func _forEachPostOrder(_ body: (borrowing Element) -> Void)

    func _forEachLevelOrder(_ body: (borrowing Element) -> Void)
}

extension __TreeProtocol where Self: ~Copyable {

    public typealias InsertPosition = __TreeInsertPosition<Address>
}

public typealias __TreeProtocol = Traversable
