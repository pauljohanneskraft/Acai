import Foundation
import Testing
@testable import AcaiApp
@testable import AcaiCore

/// Covers the three value-returning intents through `CodebaseInsights`, which holds everything they
/// do — the intents themselves only reach for `ProjectStore.app`, which a test can't seed.
///
/// Module attribution is deliberately not asserted here: which build module a type belongs to is
/// `ModuleResolver`'s business and is covered where that lives.
@Suite("Codebase insights behind the Shortcuts actions", .timeLimit(.minutes(1)))
@MainActor
struct CodebaseInsightsTests {
    private func makeModel(indexed: Bool = true) -> (ProjectBrowserViewModel, codebaseID: UUID) {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("acai-codebase-insights-tests-\(UUID().uuidString)", isDirectory: true)
        let store = ProjectStore(baseDir: tempDir)
        let codebaseID = UUID()
        store.projects = [
            Project(
                id: UUID(), title: "P", subtitle: "",
                codebases: [Codebase(id: codebaseID, name: "C", directoryPath: tempDir.path)]
            )
        ]
        if indexed {
            store.saveArtifact(artifact, for: codebaseID)
        }
        return (ProjectBrowserViewModel(store: store), codebaseID)
    }

    /// `Driver` depends on `Engine`; `Wheel` depends on nothing. No members, so nothing has a
    /// measured complexity and nothing can be a dead-code candidate.
    private var artifact: CodeArtifact {
        CodeArtifact(
            metadata: .init(sourceLanguage: .swift, filePaths: ["Engine.swift", "Driver.swift", "Wheel.swift"]),
            types: [
                TypeDeclaration(
                    id: "Engine", name: "Engine", qualifiedName: "Engine", kind: .class, accessLevel: .public,
                    location: SourceLocation(filePath: "Engine.swift", line: 1, column: 1)),
                TypeDeclaration(
                    id: "Driver", name: "Driver", qualifiedName: "Driver", kind: .class, accessLevel: .public,
                    location: SourceLocation(filePath: "Driver.swift", line: 1, column: 1)),
                TypeDeclaration(
                    id: "Wheel", name: "Wheel", qualifiedName: "Wheel", kind: .struct, accessLevel: .public,
                    location: SourceLocation(filePath: "Wheel.swift", line: 1, column: 1))
            ],
            relationships: [Relationship(kind: .dependency, source: "Driver", target: "Engine")]
        )
    }

    // MARK: - Get Metrics

    @Test func metricsAnswerWithTheCodebasesOwnCounts() async throws {
        let (model, codebaseID) = makeModel()
        let metrics = try await CodebaseInsights(browser: model).metrics(codebaseID: codebaseID)

        #expect(metrics.id == codebaseID)
        #expect(metrics.codebaseName == "C")
        #expect(metrics.typeCount == 3)
        #expect(metrics.maxComplexity == 0)
        #expect(metrics.cycleCount == 0)
        #expect(metrics.deadCodeCount == 0)
        // Nothing failed to parse, so every other number here is fully trustworthy.
        #expect(metrics.healthScore == 1)
    }

    @Test func metricsFailForACodebaseThatWasNeverIndexed() async {
        let (model, codebaseID) = makeModel(indexed: false)
        await #expect(throws: CodebaseInsights.Failure.codebaseNotIndexed("C")) {
            try await CodebaseInsights(browser: model).metrics(codebaseID: codebaseID)
        }
    }

    @Test func metricsFailForACodebaseThatIsGone() async {
        let (model, _) = makeModel()
        await #expect(throws: CodebaseInsights.Failure.codebaseNotFound) {
            try await CodebaseInsights(browser: model).metrics(codebaseID: UUID())
        }
    }

    // MARK: - Run Quality Check

    @Test func qualityCheckAnswersWithItsVerdictAndSeverities() async throws {
        let (model, codebaseID) = makeModel()
        let result = try await CodebaseInsights(browser: model).qualityCheck(codebaseID: codebaseID)

        #expect(result.id == codebaseID)
        #expect(result.isPassing)
        #expect(result.criticalCount == 0)
        #expect(result.warningCount == 0)
        #expect(result.infoCount == 0)
        #expect(result.findingCount == 0)
        // No `quality.yml` is configured, so the check ran the built-in curated budgets.
        #expect(!result.usesConfiguredRules)
        #expect(result.checkedRuleCount > 0)
    }

    @Test func qualityCheckFailsForACodebaseThatWasNeverIndexed() async {
        let (model, codebaseID) = makeModel(indexed: false)
        await #expect(throws: CodebaseInsights.Failure.codebaseNotIndexed("C")) {
            try await CodebaseInsights(browser: model).qualityCheck(codebaseID: codebaseID)
        }
    }

    // MARK: - Get Dependents

    @Test func dependentsAnswerWithEveryTypeThatDependsOnTheRoot() async throws {
        let (model, codebaseID) = makeModel()
        let dependents = try await CodebaseInsights(browser: model)
            .dependents(ofType: "Engine", codebaseID: codebaseID)

        #expect(dependents.map(\.qualifiedName) == ["Driver"])
        #expect(dependents.first?.id == "Driver")
        #expect(dependents.first?.location == "Driver.swift:1")
    }

    @Test func dependentsAreEmptyForATypeNothingDependsOn() async throws {
        let (model, codebaseID) = makeModel()
        let dependents = try await CodebaseInsights(browser: model)
            .dependents(ofType: "Wheel", codebaseID: codebaseID)

        #expect(dependents.isEmpty)
    }

    /// A type that isn't there must not read as "nothing depends on it" — the two are different
    /// answers and a Shortcut branches on them differently.
    @Test func dependentsFailForATypeThatIsNotThere() async {
        let (model, codebaseID) = makeModel()
        await #expect(throws: CodebaseInsights.Failure.typeNotFound("Nope", "C")) {
            try await CodebaseInsights(browser: model).dependents(ofType: "Nope", codebaseID: codebaseID)
        }
    }

    @Test func dependentsFailForACodebaseThatWasNeverIndexed() async {
        let (model, codebaseID) = makeModel(indexed: false)
        await #expect(throws: CodebaseInsights.Failure.codebaseNotIndexed("C")) {
            try await CodebaseInsights(browser: model).dependents(ofType: "Engine", codebaseID: codebaseID)
        }
    }
}
