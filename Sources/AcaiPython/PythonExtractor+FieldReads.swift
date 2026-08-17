import AcaiTreeSitter

extension PythonExtractor {
    /// Bare names and the `attribute` of a `self.<attr>` access are both `identifier` nodes.
    var fieldReadResolver: FieldReadResolver {
        FieldReadResolver(context: context, identifierTypes: ["identifier"])
    }
}
