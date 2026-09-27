import AcaiCore

/// A single breach of a conformance rule, carrying enough context to print a compiler-style,
/// CI-grep-friendly line and to render machine-readable JSON.
public struct Violation: Codable, Equatable, Sendable {
    /// Which rule family was breached: `forbidden-dependency`, `cycle`, `budget`, …
    public var ruleKind: String
    /// Human-readable explanation of what is wrong.
    public var message: String
    /// The offending element: a type id, module name, or `A→B` edge.
    public var subject: String
    /// Where the breach is, when a single source location applies (the offending type).
    public var source: SourceLocation?
    /// Structured extras (e.g. `metric`/`value` for a budget breach).
    public var detail: [String: String]

    public init(
        ruleKind: String,
        message: String,
        subject: String,
        source: SourceLocation? = nil,
        detail: [String: String] = [:]
    ) {
        self.ruleKind = ruleKind
        self.message = message
        self.subject = subject
        self.source = source
        self.detail = detail
    }
}

/// The outcome of evaluating a rules file against an artifact. `isPassing` is the fitness-function
/// verdict the CLI turns into a process exit code.
public struct QualityReport: Codable, Equatable, Sendable {
    /// The shape this build writes. Bump on any change a reader could misinterpret. Missing on disk
    /// (written before this field existed) decodes as `0`.
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var violations: [Violation]
    public var checkedRuleCount: Int

    public init(violations: [Violation], checkedRuleCount: Int) {
        self.schemaVersion = Self.currentSchemaVersion
        self.violations = violations
        self.checkedRuleCount = checkedRuleCount
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, violations, checkedRuleCount
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 0
        self.violations = try container.decode([Violation].self, forKey: .violations)
        self.checkedRuleCount = try container.decode(Int.self, forKey: .checkedRuleCount)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(violations, forKey: .violations)
        try container.encode(checkedRuleCount, forKey: .checkedRuleCount)
    }

    public var isPassing: Bool { violations.isEmpty }
}
