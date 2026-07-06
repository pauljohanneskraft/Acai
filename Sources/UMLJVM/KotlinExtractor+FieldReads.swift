import UMLTreeSitter

extension KotlinExtractor {
    /// Field-read resolver for Kotlin: bare references and `this.<prop>` navigation members are both
    /// `simple_identifier` nodes. Constructed inline (the extractor stays stateless).
    var fieldReadResolver: FieldReadResolver {
        FieldReadResolver(context: context, identifierTypes: ["simple_identifier"])
    }
}
