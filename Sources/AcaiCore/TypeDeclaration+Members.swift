extension TypeDeclaration {
    /// Both the DOT and Mermaid class-diagram renderers partition a type's members the same way;
    /// defining it once here (on the value that owns the members) keeps the rule from drifting
    /// between backends.
    public func partitionedMembers(
        visibleAtLeast minimum: AccessLevel?
    ) -> (properties: [Member], methods: [Member]) {
        (
            properties: members.filter(\.isProperty).visible(atLeast: minimum),
            methods: members.filter(\.isMethod).visible(atLeast: minimum)
        )
    }
}
