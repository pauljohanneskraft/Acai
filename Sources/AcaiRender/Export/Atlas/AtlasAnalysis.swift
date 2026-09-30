import AcaiCore
import AcaiDiagram
import AcaiQuality
import Foundation

/// The rules' `includeGeneratedTypes` governs every section, not just the quality report.
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
