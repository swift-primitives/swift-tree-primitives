@frozen
public enum __TreeInsertPosition<Address> {

    case root

    case child(of: __TreePosition, at: Address)
}
