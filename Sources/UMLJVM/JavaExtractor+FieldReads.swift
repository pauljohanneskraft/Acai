import UMLTreeSitter

extension JavaExtractor {
    /// Field-read resolver for Java: bare identifiers and the `field` of a `this.<field>` access are
    /// both `identifier` nodes. Constructed inline (the extractor stays stateless).
    var fieldReadResolver: FieldReadResolver {
        FieldReadResolver(context: context, identifierTypes: ["identifier"])
    }
}
