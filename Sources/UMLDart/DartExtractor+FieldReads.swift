import UMLTreeSitter

extension DartExtractor {
    /// Field-read resolver for Dart: bare references and `this.<prop>` navigation members are both
    /// `identifier` nodes. Constructed inline (the extractor stays stateless).
    var fieldReadResolver: FieldReadResolver {
        FieldReadResolver(context: context, identifierTypes: ["identifier"])
    }
}
