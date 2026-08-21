public import Index_Primitives
public import Tree_Primitive

extension __Tree where S: ~Copyable {

    public typealias Index<Tag: ~Copyable & ~Escapable> = Index_Primitives.Index<Tag>
}
