import AcaiQuality
import AcaiCore
import AcaiDiagram
import AcaiLibrary

/// Every whole-artifact report shown in the codebase detail pane, computed once and cached.
struct CodebaseAnalysis: Sendable {
    let metrics: CodeMetrics
    let deadCode: DeadCodeScan.Report
    let health: HealthCheck.Report
    /// Always present: the configured `quality.yml` if a check is configured and its rules load,
    /// otherwise the built-in curated smell budgets.
    let quality: QualityReport
    let usesConfiguredRules: Bool
    let qualityError: String?

    /// Pure and `nonisolated`, so callers run it off the main actor.
    ///
    /// The rules' `includeGeneratedTypes` (default `false`) governs the whole statistics pane —
    /// metrics, health, and dead-code are computed on the same filtered artifact the quality
    /// report uses, keeping the pane internally consistent with the CLI/MCP default.
    init(artifact rawArtifact: CodeArtifact, configuration: QualityCheckConfiguration?) {
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

        let artifact = rules.includeGeneratedTypes
            ? rawArtifact
            : rawArtifact.filteringGeneratedTypes(using: rawArtifact.standardLanguageResolver)

        self.metrics = artifact.computeMetrics()
        self.deadCode = DeadCodeScan(
            artifact: artifact,
            languages: artifact.standardLanguageResolver
        ).report
        self.health = HealthCheck(artifact: artifact).report
        self.quality = rules.report(for: artifact)
    }
}
