import UMLConformance
import UMLCore
import UMLDiagram
import UMLLibrary

/// Every whole-artifact report shown in the codebase detail pane, computed once and cached.
///
/// Each report is an expensive scan over the full artifact that only changes when the codebase is
/// reindexed (or, for the architecture check, when its rules change). Bundling them into one
/// `Sendable` value lets the view model compute them together on a background thread and hand the
/// result back to the UI, so nothing re-runs on resize/scroll/expand. A value you instantiate over
/// the artifact (`CodebaseAnalysis(artifact:configuration:)`).
struct CodebaseAnalysis: Sendable {
    let metrics: CodeMetrics
    let smells: [Violation]
    let deadCode: DeadCodeScan.Report
    let health: HealthCheck.Report
    /// The architecture-conformance report, or `nil` when no check is configured (or its rules
    /// failed to load — see `architectureError`).
    let architecture: ConformanceReport?
    /// The rules-load failure message, when a check is configured but its file couldn't be read.
    let architectureError: String?

    /// Runs every report against `artifact`. Pure and `nonisolated`, so callers run it off the main
    /// actor. `configuration` drives the architecture check: when present its rules are loaded from
    /// disk and evaluated (any load error is captured, not thrown).
    init(artifact: CodeArtifact, configuration: ArchitectureCheckConfiguration?) {
        let language = artifact.standardLanguageConfiguration
        self.metrics = artifact.computeMetrics()
        self.smells = SmellScan(
            artifact: artifact,
            annotationStereotypes: language.annotationStereotypes
        ).findings
        self.deadCode = DeadCodeScan(
            artifact: artifact,
            entryPoints: language.entryPointMarkers
        ).report
        self.health = HealthCheck(artifact: artifact).report

        if let configuration, !configuration.rulesPath.isEmpty {
            do {
                self.architecture = try configuration.loadRules().report(for: artifact)
                self.architectureError = nil
            } catch {
                self.architecture = nil
                self.architectureError = error.localizedDescription
            }
        } else {
            self.architecture = nil
            self.architectureError = nil
        }
    }
}
