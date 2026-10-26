import AcaiQuality
import AcaiCore
import AcaiDiagram
import AcaiLibrary

/// Every whole-artifact report shown in the codebase detail pane, computed once and cached.
struct CodebaseAnalysis: Sendable {
    let metrics: CodeMetrics
    let guidedRoute: [GuidedRouteStop]
    let deadCode: DeadCodeScan.Report
    let health: HealthCheck.Report
    /// Counted regardless of the rules, which only report cycles when one asks to.
    let typeCycleCount: Int
    /// Always present: the configured `quality.yml` if a check is configured and its rules load,
    /// otherwise the built-in curated smell budgets.
    let quality: QualityReport
    let usesConfiguredRules: Bool
    let qualityError: String?
}

extension CodebaseAnalysis {
    /// Pure and `nonisolated`, so callers run it off the main actor.
    ///
    /// The rules' `includeGeneratedTypes` (default `false`) governs the whole statistics pane —
    /// metrics, health, and dead-code are computed on the same filtered artifact the quality
    /// report uses, keeping the pane internally consistent with the CLI/MCP default.
    init(artifact: CodeArtifact, configuration: QualityCheckConfiguration?) {
        self.init(artifact: artifact, configuration: configuration, checkpoint: {})
    }

    /// `checkpoint` runs between passes, so a caller can abandon the work part-way.
    init(
        artifact rawArtifact: CodeArtifact, configuration: QualityCheckConfiguration?,
        checkpoint: () throws -> Void
    ) rethrows {
        let rules: QualityRules
        if let configuration, !configuration.rulesPath.isEmpty {
            do {
                rules = try configuration.loadRules()
                self.usesConfiguredRules = true
                self.qualityError = nil
            } catch {
                rules = QualityRules.defaultQuality
                self.usesConfiguredRules = false
                self.qualityError = error.localizedDescription
            }
        } else {
            rules = QualityRules.defaultQuality
            self.usesConfiguredRules = false
            self.qualityError = nil
        }

        try checkpoint()
        let artifact = rules.includeGeneratedTypes
            ? rawArtifact
            : rawArtifact.filteringGeneratedTypes(using: rawArtifact.standardLanguageResolver)

        self.metrics = artifact.computeMetrics()
        try checkpoint()
        self.guidedRoute = GuidedRouteBuilder(artifact: artifact, metrics: metrics).stops
        self.deadCode = DeadCodeScan(
            artifact: artifact,
            languages: artifact.standardLanguageResolver
        ).report
        try checkpoint()
        self.health = HealthCheck(artifact: artifact).report
        self.typeCycleCount = CycleFinder(
            artifact: artifact, languageResolver: artifact.standardLanguageResolver
        ).cycles(scope: .types).count
        try checkpoint()
        self.quality = rules.report(for: artifact)
    }
}
