public import Index_Primitives
public import Storage_Generational_Primitives
public import Store_Primitive

public protocol __TreeStorage: ~Copyable {

    associatedtype Element: ~Copyable

    associatedtype Address

    associatedtype Error: Swift.Error = __TreeError

    var _count: Index_Primitives.Index<Element>.Count { get }

    var _rootHandle: Store.Generational.Handle? { get set }

    func _liveHandle(_ position: __TreePosition) -> Store.Generational.Handle?

    mutating func _insertNode(
        _ element: consuming Element,
        parent: Store.Generational.Handle?
    ) -> Store.Generational.Handle

    mutating func _removeNode(_ handle: Store.Generational.Handle) -> Element

    mutating func _removeAll()

    func _parentHandle(of handle: Store.Generational.Handle) -> Store.Generational.Handle?

    func _withElement<R: ~Copyable>(
        at handle: Store.Generational.Handle,
        _ body: (borrowing Element) -> R
    ) -> R

    mutating func _withElementMut<R: ~Copyable>(
        at handle: Store.Generational.Handle,
        _ body: (inout Element) -> R
    ) -> R

    func _childHandle(
        at handle: Store.Generational.Handle,
        address: Address
    ) -> Store.Generational.Handle?

    func _validateLink(
        to parent: Store.Generational.Handle,
        at address: Address
    ) throws(__TreeError)

    mutating func _linkChild(
        _ child: Store.Generational.Handle,
        to parent: Store.Generational.Handle,
        at address: Address
    )

    mutating func _unlinkChild(
        _ child: Store.Generational.Handle,
        from parent: Store.Generational.Handle
    )

    func _childCount(at handle: Store.Generational.Handle) -> Int

    func _forEachChild(
        at handle: Store.Generational.Handle,
        _ body: (Store.Generational.Handle) -> Void
    )
}
