import AcaiQuality
import AcaiCore
import AcaiDiagram
import AcaiLibrary

/// Every whole-artifact report shown in the codebase detail pane, computed once and cached.
///
/// Each report is an expensive scan over the full artifact that only changes when the codebase is
/// reindexed (or, for the quality check, when its rules change). Bundling them into one
/// `Sendable` value lets the view model compute them together on a background thread and hand the
/// result back to the UI, so nothing re-runs on resize/scroll/expand. A value you instantiate over
/// the artifact (`CodebaseAnalysis(artifact:configuration:)`).
struct CodebaseAnalysis: Sendable {
    let metrics: CodeMetrics
    let deadCode: DeadCodeScan.Report
    let health: HealthCheck.Report
    /// The code-quality report — always present. When a check is configured (and its rules load) the
    /// configured `quality.yml` is evaluated; otherwise the built-in curated smell budgets are, so the
    /// Code Quality Check always flags god classes, feature envy, low cohesion, and the like.
    let quality: QualityReport
    /// Whether `quality` came from a configured rules file (vs the built-in default smell budgets).
    let usesConfiguredRules: Bool
    /// The rules-load failure message, when a check is configured but its file couldn't be read (the
    /// report then falls back to the default budgets).
    let qualityError: String?

    /// Runs every report against `rawArtifact`. Pure and `nonisolated`, so callers run it off the main
    /// actor. `configuration` drives the quality check: when present its rules are loaded from disk
    /// and evaluated (any load error is captured, not thrown, and the default budgets are used).
    ///
    /// The rules' `includeGeneratedTypes` (default `false`) governs the **whole** statistics pane —
    /// metrics, health and dead-code are computed on the same filtered artifact the quality report
    /// uses, so a single per-codebase setting keeps the pane internally consistent and matches the
    /// CLI/MCP (whose tools default to the same exclude-generated behaviour).
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
