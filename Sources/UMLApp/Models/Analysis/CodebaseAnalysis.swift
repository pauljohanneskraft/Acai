import UMLQuality
import UMLCore
import UMLDiagram
import UMLLibrary

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

    /// Runs every report against `artifact`. Pure and `nonisolated`, so callers run it off the main
    /// actor. `configuration` drives the quality check: when present its rules are loaded from disk
    /// and evaluated (any load error is captured, not thrown, and the default budgets are used).
    init(artifact: CodeArtifact, configuration: QualityCheckConfiguration?) {
        self.metrics = artifact.computeMetrics()
        self.deadCode = DeadCodeScan(
            artifact: artifact,
            languages: artifact.standardLanguageResolver
        ).report
        self.health = HealthCheck(artifact: artifact).report

        if let configuration, !configuration.rulesPath.isEmpty {
            do {
                self.quality = try configuration.loadRules().report(for: artifact)
                self.usesConfiguredRules = true
                self.qualityError = nil
            } catch {
                self.quality = QualityRules.defaultQuality.report(for: artifact)
                self.usesConfiguredRules = false
                self.qualityError = error.localizedDescription
            }
        } else {
            self.quality = QualityRules.defaultQuality.report(for: artifact)
            self.usesConfiguredRules = false
            self.qualityError = nil
        }
    }
}
