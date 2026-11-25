/// One plugin's hand-maintained classification of every Tree-sitter node kind its corpus produces.
///
/// A kind absent from all three buckets fails `NodeKindCoverageTests`, so widening a fixture forces
/// a decision about the syntax it introduced instead of letting the extractor drop it in silence.
struct NodeKindInventory: Sendable {
    /// Kinds the extractor must turn into a declaration.
    let extracted: [String: ExtractedKind]
    /// Kinds that could carry a declaration but are deliberately skipped, each with the reason.
    let ignored: [String: String]
    /// Kinds that declare nothing: expressions, statements, type references, keyword-shaped tokens.
    let notDeclarations: Set<String>
    /// Kinds that count as an enclosing node for an `ignoredInside` or `knownIssueInside` key even
    /// though they declare nothing — a Python module-level `if` is one.
    let scopeKinds: Set<String>

    init(
        extracted: [String: ExtractedKind],
        ignored: [String: String],
        notDeclarations: Set<String>,
        scopeKinds: Set<String> = []
    ) {
        self.extracted = extracted
        self.ignored = ignored
        self.notDeclarations = notDeclarations
        self.scopeKinds = scopeKinds
    }

    func classifies(_ kind: String) -> Bool {
        extracted[kind] != nil || ignored[kind] != nil || notDeclarations.contains(kind)
    }
}

/// A kind whose every occurrence must produce a declaration carrying the declared name.
struct ExtractedKind: Sendable {
    let name: NamePath
    /// When set, only occurrences carrying a direct child of every one of these kinds declare
    /// anything — a C `struct_specifier` declares a type only when it has both a name and a body,
    /// and a Kotlin `class_parameter` is promoted only when written `val`/`var`.
    let requiredChildren: [String]
    /// The same gate by Tree-sitter field: a C++ `field_declaration` holding a nested `class_specifier`
    /// has no `declarator` and declares nothing itself.
    let requiredFields: [String]
    /// Set when extraction is broken wherever the kind occurs; recorded with `withKnownIssue`, so
    /// the day it starts working the suite says so rather than staying quietly green.
    let knownIssue: String?
    /// Enclosing kinds inside which this kind is deliberately not extracted.
    let ignoredInside: [String: String]
    /// Enclosing kinds inside which extraction is broken, keyed to the issue.
    let knownIssueInside: [String: String]

    init(
        name: NamePath,
        requiredChildren: [String] = [],
        requiredFields: [String] = [],
        knownIssue: String? = nil,
        ignoredInside: [String: String] = [:],
        knownIssueInside: [String: String] = [:]
    ) {
        self.name = name
        self.requiredChildren = requiredChildren
        self.requiredFields = requiredFields
        self.knownIssue = knownIssue
        self.ignoredInside = ignoredInside
        self.knownIssueInside = knownIssueInside
    }

    /// How an occurrence of this kind directly inside `enclosing` must be treated.
    func expectation(inside enclosing: String?) -> Expectation {
        if let enclosing, let reason = ignoredInside[enclosing] {
            return .ignored(reason)
        }
        if let enclosing, let issue = knownIssueInside[enclosing] {
            return .knownGap(issue)
        }
        return knownIssue.map(Expectation.knownGap) ?? .declared
    }

    enum Expectation: Sendable, Equatable {
        case declared
        case knownGap(String)
        case ignored(String)
    }
}
