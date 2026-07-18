/// A trust/health report over an artifact's parse diagnostics: how much of the codebase parsed
/// cleanly, and where it didn't. A low score means the parser stumbled (unresolved references, ERROR
/// nodes, missing tokens), so the *rest* of any audit built on this artifact is correspondingly
/// untrustworthy — surface it before interpreting cycles/metrics/dead-code.
///
/// A value you instantiate over an artifact (`HealthCheck(artifact:).report`). Agnostic: it reads
/// `metadata.parseDiagnostics` and names no language.
public struct HealthCheck: Sendable {
    /// The rendered health verdict.
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
}
