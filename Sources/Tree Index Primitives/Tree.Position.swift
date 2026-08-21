public import Index_Primitives
public import Tree_Primitive

public struct __TreePosition: Sendable, Equatable, Hashable {

    public let index: Index<Self>

    public let token: UInt32

    @inlinable
    public init(index: Index<Self>, token: UInt32) {
        self.index = index
        self.token = token
    }

    @inlinable
    public init<T: ~Copyable & ~Escapable>(index: Index<T>, token: UInt32) {
        self.init(index: index.retag(Self.self), token: token)
    }

    @inlinable
    public init(index: Int, token: UInt32) {
        self.init(
            index: Index<Self>(Ordinal(UInt(index))),
            token: token
        )
    }
}

extension __Tree where S: ~Copyable {

    public typealias Position = __TreePosition
}
