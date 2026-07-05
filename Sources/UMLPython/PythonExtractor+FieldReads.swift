import UMLTreeSitter

extension PythonExtractor {
    /// Field-read resolver for Python: bare names and the `attribute` of a `self.<attr>` access are
    /// both `identifier` nodes. Constructed inline (the extractor stays stateless).
    var fieldReadResolver: FieldReadResolver {
        FieldReadResolver(context: context, identifierTypes: ["identifier"])
    }
}
