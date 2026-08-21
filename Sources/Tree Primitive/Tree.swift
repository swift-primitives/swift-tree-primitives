@_documentation(visibility: public)
@frozen
public struct __Tree<S: ~Copyable> {

    @usableFromInline
    package var storage: S

    @inlinable
    public init(storage: consuming S) {
        self.storage = storage
    }
}

extension __Tree where S: ~Copyable {

    @inlinable
    public consuming func take() -> S {
        storage
    }
}

extension __Tree where S: ~Copyable {

    @inlinable
    public var _storage: S {
        _read { yield storage }
        _modify { yield &storage }
    }
}

extension __Tree: Copyable where S: Copyable {}

extension __Tree: Sendable where S: Sendable & ~Copyable {}
