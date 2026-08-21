public import Tree_Primitive

@frozen
public enum __TreeError: Swift.Error, Sendable, Equatable {

    case invalidPosition

    case rootOccupied

    case slotOccupied

    case childIndexOutOfBounds

    case cannotRemoveNonLeaf
}

extension __Tree where S: __TreeStorage & ~Copyable {

    public typealias Error = S.Error
}
