public import Storage_Generational_Primitives
public import Store_Primitive

@usableFromInline
struct __TreeNode<Element: ~Copyable, ChildLinks>: ~Copyable {

    @usableFromInline var element: Element

    @usableFromInline var links: ChildLinks

    @usableFromInline var parentHandle: Store.Generational.Handle?

    @usableFromInline
    init(
        element: consuming Element,
        links: consuming ChildLinks,
        parentHandle: Store.Generational.Handle?
    ) {
        self.element = element
        self.links = links
        self.parentHandle = parentHandle
    }
}

extension __TreeNode: Copyable where Element: Copyable, ChildLinks: Copyable {}

extension __TreeNode: Sendable where Element: Sendable, ChildLinks: Sendable {}
