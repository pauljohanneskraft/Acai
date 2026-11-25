/// One plugin's classification of every Tree-sitter node kind its corpus produces.
struct NodeKindInventory: Sendable {
    /// Kinds the extractor must turn into a declaration.
    let extracted: [String: ExtractedKind]
    /// Kinds that could carry a declaration but are deliberately skipped, each with the reason.
    let ignored: [String: String]
    /// Kinds that declare nothing: expressions, statements, type references, keyword-shaped tokens.
    let notDeclarations: Set<String>
    /// Kinds that count as an enclosing node although they declare nothing, like a Python `if`.
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
    /// When set, only occurrences carrying a direct child of each of these kinds declare anything.
    let requiredChildren: [String]
    /// The same gate by Tree-sitter field: a C++ nested-type `field_declaration` has no `declarator`.
    let requiredFields: [String]
    /// Set when extraction is broken wherever the kind occurs; recorded with `withKnownIssue`.
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
