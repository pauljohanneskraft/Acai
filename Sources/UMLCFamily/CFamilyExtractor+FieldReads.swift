import UMLTreeSitter

extension CFamilyExtractor {
    /// Field-read resolver for C/C++: bare identifiers plus the `field_identifier` of a `this->field`
    /// / `obj.field` access. Constructed inline (the extractor stays stateless).
    var fieldReadResolver: FieldReadResolver {
        FieldReadResolver(context: context, identifierTypes: ["identifier", "field_identifier"])
    }
}
