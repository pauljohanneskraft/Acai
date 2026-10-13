import AcaiCore
import AcaiLibrary
import AcaiQuality
import AcaiRender
import Foundation

/// The analysis behind the value-returning codebase intents. It reads the same cached,
/// background-computed `CodebaseAnalysis` the codebase screen shows, so a Shortcut and the app
/// never report different numbers, and turns the states a Shortcut has to branch on — a codebase
/// that has gone away, one that was never indexed, a type that isn't there — into thrown errors
/// rather than zero counts a Shortcut would read as an answer.
@MainActor
struct CodebaseInsights {
    let browser: ProjectBrowserViewModel

    enum Failure: LocalizedError, Equatable {
        case codebaseNotFound
        case codebaseNotIndexed(String)
        case analysisUnavailable(String)
        case typeNotFound(String, String)

        var errorDescription: String? {
            switch self {
            case .codebaseNotFound:
                String(localized: .app("Intent.CodebaseInsights.CodebaseNotFound"))
            case .codebaseNotIndexed(let name):
                String(localized: .app("Intent.CodebaseInsights.NotIndexed \(name)"))
            case .analysisUnavailable(let name):
                String(localized: .app("Intent.CodebaseInsights.AnalysisUnavailable \(name)"))
            case .typeNotFound(let type, let codebase):
                String(localized: .app("Intent.CodebaseInsights.TypeNotFound \(type) \(codebase)"))
            }
        }
    }

    func metrics(codebaseID: UUID) async throws -> CodebaseMetricsEntity {
        let (codebase, analysis) = try await analyzed(codebaseID: codebaseID)
        guard let artifact = browser.semanticArtifact(for: codebaseID) else {
            throw Failure.codebaseNotIndexed(codebase.name)
        }
        // Counted here rather than read off `analysis`, which only reports cycles when a configured
        // rule asks for them — the same `CycleFinder` at the same scope the CLI and MCP count with.
        let cycles = await Task.detached(priority: .userInitiated) {
            CycleFinder(artifact: artifact, languageResolver: artifact.standardLanguageResolver)
                .cycles(scope: .types)
                .count
        }.value
        try Task.checkCancellation()
        return CodebaseMetricsEntity(
            id: codebase.id,
            codebaseName: codebase.name,
            typeCount: analysis.metrics.counts.totalTypes,
            moduleCount: analysis.metrics.modules.count,
            maxComplexity: analysis.metrics.types.map(\.maxCyclomaticComplexity).max() ?? 0,
            cycleCount: cycles,
            deadCodeCount: analysis.deadCode.candidates.count,
            healthScore: analysis.health.score)
    }

    /// Severity comes from the shared `AtlasFinding` mapping, so a Shortcut branching on
    /// `criticalCount` splits the findings exactly where the app's own Findings list does.
    func qualityCheck(codebaseID: UUID) async throws -> QualityCheckResultEntity {
        let (codebase, analysis) = try await analyzed(codebaseID: codebaseID)
        let findings = analysis.quality.violations.map(AtlasFinding.init(violation:))
        return QualityCheckResultEntity(
            id: codebase.id,
            codebaseName: codebase.name,
            isPassing: analysis.quality.isPassing,
            criticalCount: findings.count(where: { $0.severity == .critical }),
            warningCount: findings.count(where: { $0.severity == .warning }),
            infoCount: findings.count(where: { $0.severity == .info }),
            checkedRuleCount: analysis.quality.checkedRuleCount,
            usesConfiguredRules: analysis.usesConfiguredRules)
    }

    func dependents(ofType typeName: String, codebaseID: UUID) async throws -> [TypeEntity] {
        guard let codebase = browser.codebase(for: codebaseID) else { throw Failure.codebaseNotFound }
        guard let artifact = browser.artifact(for: codebaseID) else {
            throw Failure.codebaseNotIndexed(codebase.name)
        }
        try Task.checkCancellation()
        let report = await Task.detached(priority: .userInitiated) {
            ImpactAnalysis(artifact: artifact, rootType: typeName).report
        }.value
        try Task.checkCancellation()
        // An unresolvable root reads as "no dependents" otherwise, which is a different answer.
        guard report.found else { throw Failure.typeNotFound(typeName, codebase.name) }
        return report.dependents.map { TypeEntity($0) }
    }

    /// Waits for the cached analysis the codebase screen computes, which `ensureAnalysisLoaded`
    /// already runs off the main actor.
    private func analyzed(codebaseID: UUID) async throws -> (Codebase, CodebaseAnalysis) {
        guard let codebase = browser.codebase(for: codebaseID) else { throw Failure.codebaseNotFound }
        guard browser.semanticArtifact(for: codebaseID) != nil else {
            throw Failure.codebaseNotIndexed(codebase.name)
        }
        try Task.checkCancellation()
        await browser.ensureAnalysisLoaded(codebaseID: codebaseID)
        try Task.checkCancellation()
        // The store is user-mutable and that await crossed it: look the codebase up by id again
        // rather than trusting what was read before.
        guard let current = browser.codebase(for: codebaseID) else { throw Failure.codebaseNotFound }
        // A reindex or rules edit during the computation supersedes it, leaving nothing cached.
        guard let analysis = browser.analysis(for: codebaseID) else {
            throw Failure.analysisUnavailable(current.name)
        }
        return (current, analysis)
    }
}
