import AcaiTreeSitter

extension JSExtractor {
    /// Field-read resolver for JS/TS: bare identifiers, `this.<member>` property names, and
    /// object-literal shorthands. Constructed inline (the extractor stays stateless).
    var fieldReadResolver: FieldReadResolver {
        FieldReadResolver(
            context: context,
            identifierTypes: ["identifier", "property_identifier", "shorthand_property_identifier"]
        )
    }
}
