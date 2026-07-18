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
    public var violations: [Violation]
    public var checkedRuleCount: Int

    public init(violations: [Violation], checkedRuleCount: Int) {
        self.violations = violations
        self.checkedRuleCount = checkedRuleCount
    }

    public var isPassing: Bool { violations.isEmpty }
}
