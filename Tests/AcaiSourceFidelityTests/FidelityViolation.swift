import AcaiCore

/// One way an artifact failed to agree with the source it was parsed from.
struct FidelityViolation: Sendable, CustomStringConvertible, Equatable {
    enum Rule: String, Sendable {
        case missingLocation
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

    /// The name a parser gives a declaration the language leaves anonymous.
    struct AnonymousName: Sendable {
        /// Appended to whatever the declaration is attached to, or the whole name when the stem is
        /// empty.
        let suffix: String
        /// The keyword that has to appear in the declaration's own span for the name to stand in.
        let keyword: String
        let reason: String
    }

    var anonymousNames: [AnonymousName] = []
    /// Characters that may follow a type in the source without the reference recording them.
    var unmodelledTypeSuffixes: [Character: String] = [:]
    /// Whether the language sugars a generic collection, so `Array<T>` is also written `[T]`.
    var sugarsGenericCollections = false
}
