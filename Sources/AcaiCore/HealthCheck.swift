/// A trust/health report over an artifact's parse diagnostics: how much of the codebase parsed
/// cleanly, and where it didn't. A low score means the parser stumbled, so any audit built on this
/// artifact is correspondingly untrustworthy — surface it before interpreting cycles/metrics/dead-code.
public struct HealthCheck: Sendable {
    public struct Report: Codable, Equatable, Sendable {
        /// Heuristic trust score in `0...1` (1 = no diagnostics). Defined as
        /// `1 - min(1, diagnostics / max(1, types))`: one diagnostic per type drives it to 0.
        public var score: Double
        public var typeCount: Int
        public var diagnosticCount: Int
        /// Diagnostic counts keyed by kind (`error`, `missing`, `unresolvedReference`).
        public var countsByKind: [String: Int]
        /// Every diagnostic, each carrying its `SourceLocation` for a precise jump target.
        public var diagnostics: [ParseDiagnostic]
    }

    /// The compact form of ``Report`` other commands embed in their own output: the score and
    /// diagnostic breakdown, without the full per-diagnostic list `acai analyze --health` provides.
    public struct Summary: Codable, Equatable, Sendable {
        public var score: Double
        public var diagnosticCount: Int
        public var countsByKind: [String: Int]

        public init(score: Double, diagnosticCount: Int, countsByKind: [String: Int]) {
            self.score = score
            self.diagnosticCount = diagnosticCount
            self.countsByKind = countsByKind
        }
    }

    /// Below this score, a command consuming an artifact should surface that its analysis rests on an
    /// untrustworthy parse rather than staying silent about it.
    public static let trustThreshold: Double = 0.8

    private let artifact: CodeArtifact

    public init(artifact: CodeArtifact) {
        self.artifact = artifact
    }

    public var report: Report {
        let diagnostics = artifact.metadata.parseDiagnostics
        let typeCount = artifact.flattened().count
        let countsByKind = Dictionary(
            grouping: diagnostics, by: { $0.kind.rawValue }).mapValues(\.count)
        let penalty = min(1, Double(diagnostics.count) / Double(max(1, typeCount)))
        return Report(
            score: 1 - penalty,
            typeCount: typeCount,
            diagnosticCount: diagnostics.count,
            countsByKind: countsByKind,
            diagnostics: diagnostics.sorted {
                ($0.location.filePath, $0.location.line) < ($1.location.filePath, $1.location.line)
            })
    }

    public var summary: Summary {
        let full = report
        return Summary(score: full.score, diagnosticCount: full.diagnosticCount, countsByKind: full.countsByKind)
    }
}

extension HealthCheck.Summary {
    /// Combines two summaries (e.g. a diff's old and new sides) into the weaker-trust view: the lower
    /// score, and diagnostic counts summed kind-by-kind.
    public func combined(with other: Self) -> Self {
        var countsByKind = countsByKind
        for (kind, count) in other.countsByKind {
            countsByKind[kind, default: 0] += count
        }
        return Self(
            score: min(score, other.score),
            diagnosticCount: diagnosticCount + other.diagnosticCount,
            countsByKind: countsByKind)
    }
}
