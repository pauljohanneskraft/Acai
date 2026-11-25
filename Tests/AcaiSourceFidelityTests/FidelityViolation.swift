import AcaiCore

/// One way an artifact failed to agree with the source it was parsed from.
struct FidelityViolation: Sendable, CustomStringConvertible, Equatable {
    enum Rule: String, Sendable {
        case location
        case identity
        case type
    }

    let rule: Rule
    let declaration: String
    let detail: String

    var description: String { "[\(rule.rawValue)] \(declaration) — \(detail)" }
}

/// A disagreement between artifact and source that a language genuinely forces, declared with the
/// reason it exists so every other language stays held to the strict reading.
struct DeclaredLanguageDifference: Sendable {

    /// A name the parser reports where the source never writes it.
    struct SubstitutedName: Sendable {
        /// The reported name, or its tail when the parser prefixes what the declaration attaches to.
        let suffix: String
        /// The keyword that has to appear in the declaration's own span for the name to stand in.
        let keyword: String
        let reason: String
    }

    var substitutedNames: [SubstitutedName] = []
    /// Characters that may follow a type in the source without the reference recording them.
    var unmodelledTypeSuffixes: [Character: String] = [:]
    /// Whether the language sugars a generic collection, so `Array<T>` is also written `[T]`.
    var sugarsGenericCollections = false
    /// Whether a constructor parameter may take its type from the field it initializes, as Dart's
    /// `this.x` formals do, which leaves that type unwritten in the constructor's own span.
    var forwardsFieldTypesToConstructorParameters = false
}
