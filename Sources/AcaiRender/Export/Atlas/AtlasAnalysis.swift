import AcaiCore
import AcaiDiagram
import AcaiQuality
import Foundation

/// The statistics and findings an Atlas is built from, computed from one artifact in a single pass.
/// A value you instantiate over an artifact plus the rules to judge it by.
///
/// The rules' `includeGeneratedTypes` (default `false`) governs the whole bundle — metrics, health
/// and dead code are computed on the same filtered artifact the quality report uses, so the Atlas's
/// sections stay internally consistent, matching what the app's statistics pane shows.
public struct AtlasAnalysis {
    public let metrics: CodeMetrics
    public let findings: [AtlasFinding]

    public init(
        artifact rawArtifact: CodeArtifact, rules: QualityRules, languages: LanguageConfigurationResolver
    ) {
        let artifact = rules.includeGeneratedTypes
            ? rawArtifact
            : rawArtifact.filteringGeneratedTypes(using: languages)
        self.metrics = artifact.computeMetrics()
        self.findings = AtlasFindings(
            quality: QualityEvaluator(rules: rules, languageResolver: languages).evaluate(artifact),
            deadCode: DeadCodeScan(artifact: artifact, languages: languages).report,
            health: HealthCheck(artifact: artifact).report
        ).findings
    }
}
