import AcaiCore
import AcaiLibrary
import AcaiRender
import Foundation

/// Answers the value-returning intents; a state a Shortcut must tell apart is thrown, never a zero.
@MainActor
struct CodebaseInsights {
    let store: ProjectStore

    enum Failure: LocalizedError, Equatable {
        case codebaseNotFound
        case codebaseNotIndexed(String)
        case typeNotFound(String, String)

        var errorDescription: String? {
            switch self {
            case .codebaseNotFound:
                String(localized: .app("Intent.CodebaseInsights.CodebaseNotFound"))
            case .codebaseNotIndexed(let name):
                String(localized: .app("Intent.CodebaseInsights.NotIndexed \(name)"))
            case .typeNotFound(let type, let codebase):
                String(localized: .app("Intent.CodebaseInsights.TypeNotFound \(type) \(codebase)"))
            }
        }
    }

    func metrics(codebaseID: UUID) async throws -> CodebaseMetricsEntity {
        let (codebase, analysis) = try await analyzed(codebaseID: codebaseID)
        return CodebaseMetricsEntity(
            id: codebase.id,
            codebaseName: codebase.name,
            typeCount: analysis.metrics.counts.totalTypes,
            moduleCount: analysis.metrics.modules.count,
            maxComplexity: analysis.metrics.types.map(\.maxCyclomaticComplexity).max() ?? 0,
            cycleCount: analysis.typeCycleCount,
            deadCodeCount: analysis.deadCode.candidates.count,
            healthScore: analysis.health.score)
    }

    /// Counts the same findings, by the same severities, as the widget and the Findings list.
    func qualityCheck(codebaseID: UUID) async throws -> QualityCheckResultEntity {
        let (codebase, analysis) = try await analyzed(codebaseID: codebaseID)
        let findings = AtlasFindings(
            quality: analysis.quality, deadCode: analysis.deadCode, health: analysis.health
        ).findings
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
        let (_, semantic) = try indexed(codebaseID: codebaseID)
        let report = try await offMainActor {
            ImpactAnalysis(artifact: semantic.displayReady, rootType: typeName).report
        }
        let codebase = try codebase(codebaseID)
        // An unresolvable root would otherwise read as "no dependents", which is a different answer.
        guard report.found else { throw Failure.typeNotFound(typeName, codebase.name) }
        return report.dependents.map { TypeEntity($0, in: codebaseID) }
    }

    func types(identifiedBy identifiers: [String]) async throws -> [TypeEntity] {
        let addresses = identifiers.compactMap(TypeEntity.Address.init)
        let artifacts = Set(addresses.map(\.codebaseID)).reduce(into: [UUID: CodeArtifact]()) { artifacts, id in
            artifacts[id] = store.artifact(for: id)
        }
        return try await offMainActor {
            let types = artifacts.mapValues { artifact in
                Dictionary(artifact.displayReady.flattened().map { ($0.id, $0) }) { first, _ in first }
            }
            return addresses.compactMap { address in
                types[address.codebaseID]?[address.typeID].map { TypeEntity($0, in: address.codebaseID) }
            }
        }
    }

    private func analyzed(codebaseID: UUID) async throws -> (Codebase, CodebaseAnalysis) {
        let (codebase, artifact) = try indexed(codebaseID: codebaseID)
        let configuration = codebase.qualityCheck
        let analysis = try await offMainActor {
            try CodebaseAnalysis(artifact: artifact, configuration: configuration) { try Task.checkCancellation() }
        }
        // The store is user-mutable and that await crossed it.
        return (try self.codebase(codebaseID), analysis)
    }

    private func indexed(codebaseID: UUID) throws -> (Codebase, CodeArtifact) {
        let codebase = try codebase(codebaseID)
        guard let artifact = store.artifact(for: codebaseID) else { throw Failure.codebaseNotIndexed(codebase.name) }
        return (codebase, artifact)
    }

    private func codebase(_ codebaseID: UUID) throws -> Codebase {
        guard let codebase = store.projects.lazy.flatMap(\.codebases).first(where: { $0.id == codebaseID }) else {
            throw Failure.codebaseNotFound
        }
        return codebase
    }

    private func offMainActor<Value: Sendable>(
        _ work: @escaping @Sendable () throws -> Value
    ) async throws -> Value {
        try Task.checkCancellation()
        let task = Task.detached(priority: .userInitiated, operation: work)
        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }
}
