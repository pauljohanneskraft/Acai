import Foundation
import Testing
import AcaiCore
import AcaiQuality
@testable import AcaiApp

@Suite("Findings aggregator")
@MainActor
struct FindingsAggregatorTests {
    private let baseDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("acai-findings-aggregator-\(UUID().uuidString)", isDirectory: true)

    private var artifact: CodeArtifact {
        CodeArtifact(
            metadata: .init(sourceLanguage: .swift, filePaths: ["A.swift"]),
            types: [
                TypeDeclaration(
                    id: "A", name: "A", qualifiedName: "A", kind: .class, accessLevel: .public,
                    location: SourceLocation(filePath: "A.swift", line: 1, column: 1)),
                TypeDeclaration(
                    id: "B", name: "B", qualifiedName: "B", kind: .class, accessLevel: .public,
                    location: SourceLocation(filePath: "B.swift", line: 1, column: 1))
            ]
        )
    }

    private func analysis(violations: [Violation]) -> CodebaseAnalysis {
        let computed = CodebaseAnalysis(artifact: artifact, configuration: nil)
        return CodebaseAnalysis(
            metrics: computed.metrics, guidedRoute: computed.guidedRoute, deadCode: computed.deadCode,
            health: computed.health, quality: QualityReport(violations: violations, checkedRuleCount: 1),
            usesConfiguredRules: false, qualityError: nil)
    }

    private func budget(_ subject: String, metric: String = "methodCount", value: String = "12") -> Violation {
        Violation(
            ruleKind: "budget", message: "\(subject): \(metric) \(value) exceeds max 10", subject: subject,
            source: SourceLocation(filePath: "\(subject).swift", line: 1, column: 1),
            detail: ["metric": metric, "value": value])
    }

    private let cycle = Violation(
        ruleKind: "cycle", message: "Type dependency cycle: A → B → A.", subject: "A,B",
        source: SourceLocation(filePath: "A.swift", line: 1, column: 1), detail: ["scope": "types"])

    private func makeModel(codebases: [Codebase]) -> (ProjectBrowserViewModel, Project) {
        let store = ProjectStore(baseDir: baseDir)
        let project = Project(title: "P", subtitle: "", codebases: codebases)
        store.projects = [project]
        return (ProjectBrowserViewModel(store: store), project)
    }

    @Test func aBudgetViolationBecomesAWarningFinding() {
        let codebase = Codebase(name: "C", directoryPath: "/c", lastIndexed: Date(timeIntervalSince1970: 5))
        let (model, project) = makeModel(codebases: [codebase])
        let aggregator = FindingsAggregator(project: project, model: model)

        let findings = aggregator.findings(
            for: codebase, analysis: analysis(violations: [budget("A")]), artifact: artifact)
        let finding = findings.first { $0.kind == .violation }

        #expect(finding?.severity == .warning)
        #expect(finding?.title == "A")
        #expect(finding?.codebaseID == codebase.id)
        #expect(finding?.indexedAt == codebase.lastIndexed)
        #expect(finding?.reference == .type(id: "A"))
        #expect(finding?.cycle == nil)
    }

    @Test func aCycleViolationIsCriticalWithItsCycleReference() {
        let codebase = Codebase(name: "C", directoryPath: "/c")
        let (model, project) = makeModel(codebases: [codebase])
        let aggregator = FindingsAggregator(project: project, model: model)

        let finding = aggregator.findings(for: codebase, analysis: analysis(violations: [cycle]), artifact: artifact)
            .first { $0.kind == .violation }

        #expect(finding?.severity == .critical)
        #expect(finding?.cycle == Finding.CycleReference(scope: "types", members: ["A", "B"]))
    }

    @Test func reorderingViolationsKeepsEachFindingsID() {
        let codebase = Codebase(name: "C", directoryPath: "/c")
        let (model, project) = makeModel(codebases: [codebase])
        let aggregator = FindingsAggregator(project: project, model: model)
        let violations = [budget("A"), cycle, budget("B"), budget("A", metric: "fanOut", value: "30")]

        let ids = aggregator.findings(for: codebase, analysis: analysis(violations: violations), artifact: nil)
            .map(\.id)
        let reorderedIDs = aggregator.findings(
            for: codebase, analysis: analysis(violations: violations.reversed()), artifact: nil
        ).map(\.id)

        #expect(Set(ids).count == violations.count)
        #expect(Set(ids) == Set(reorderedIDs))
        #expect(ids.reversed() == reorderedIDs)
    }

    @Test func aBudgetFindingKeepsItsIDWhenTheMeasuredValueMoves() {
        let codebase = Codebase(name: "C", directoryPath: "/c")
        let (model, project) = makeModel(codebases: [codebase])
        let aggregator = FindingsAggregator(project: project, model: model)

        let before = aggregator.findings(
            for: codebase, analysis: analysis(violations: [budget("A", value: "12")]), artifact: nil)
        let after = aggregator.findings(
            for: codebase, analysis: analysis(violations: [budget("A", value: "13")]), artifact: nil)

        #expect(before.map(\.id) == after.map(\.id))
    }

    @Test func distinguishesNotIndexedFromStillAnalyzing() async {
        let notIndexed = Codebase(name: "Fresh", directoryPath: "/fresh")
        let analyzing = Codebase(name: "Analyzing", directoryPath: "/analyzing", hasArtifact: true)
        let analyzed = Codebase(name: "Analyzed", directoryPath: "/analyzed", hasArtifact: true)
        let (model, project) = makeModel(codebases: [notIndexed, analyzing, analyzed])
        model.store.artifacts[analyzing.id] = artifact
        model.store.artifacts[analyzed.id] = artifact
        await model.ensureAnalysisLoaded(codebaseID: analyzed.id)
        let aggregator = FindingsAggregator(project: project, model: model)

        #expect(aggregator.codebasesNotIndexed().map(\.id) == [notIndexed.id])
        #expect(aggregator.codebasesStillAnalyzing().map(\.id) == [analyzing.id])
        #expect(aggregator.findings(for: analyzing).isEmpty)
        #expect(aggregator.findings().allSatisfy { $0.codebaseID == analyzed.id })
    }
}
