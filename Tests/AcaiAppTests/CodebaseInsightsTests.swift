import Foundation
import Testing
import AcaiQuality
@testable import AcaiApp
@testable import AcaiCore

/// Runs each value-returning intent against a seeded store.
@Suite("Shortcuts actions that answer with a value", .timeLimit(.minutes(1)))
@MainActor
struct CodebaseInsightsTests {
    private let codebaseID = UUID()

    private func makeStore(
        artifact: CodeArtifact? = Self.artifact(), rules: QualityRules? = nil
    ) throws -> ProjectStore {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("acai-codebase-insights-tests-\(UUID().uuidString)", isDirectory: true)
        let store = ProjectStore(baseDir: tempDir)
        var codebase = Codebase(id: codebaseID, name: "C", directoryPath: tempDir.path)
        if let rules {
            let rulesURL = try store.saveManagedRules(rules, forCodebase: codebaseID)
            codebase.qualityCheck = QualityCheckConfiguration(rulesPath: rulesURL.path)
        }
        store.projects = [Project(id: UUID(), title: "P", subtitle: "", codebases: [codebase])]
        store.artifacts[codebaseID] = artifact
        return store
    }

    private var entity: CodebaseEntity {
        CodebaseEntity(id: codebaseID, name: "C", projectTitle: "P")
    }

    /// `Driver` depends on `Engine`, `Wheel` on nothing, and `Left` and `Right` on each other.
    private static func artifact(diagnostics: [ParseDiagnostic] = []) -> CodeArtifact {
        let names = ["Engine", "Driver", "Wheel", "Left", "Right"]
        return CodeArtifact(
            metadata: .init(
                sourceLanguage: .swift, filePaths: names.map { "\($0).swift" }, parseDiagnostics: diagnostics),
            types: names.map { name in
                TypeDeclaration(
                    id: name, name: name, qualifiedName: name, kind: .class, accessLevel: .public,
                    location: SourceLocation(filePath: "\(name).swift", line: 1, column: 1))
            },
            relationships: [
                Relationship(kind: .dependency, source: "Driver", target: "Engine"),
                Relationship(kind: .dependency, source: "Left", target: "Right"),
                Relationship(kind: .dependency, source: "Right", target: "Left")
            ]
        )
    }

    // MARK: - Get Metrics

    @Test func metricsAnswerWithTheCodebasesOwnCounts() async throws {
        let metrics = try await GetCodebaseMetricsIntent(codebase: entity).answer(in: makeStore())

        #expect(metrics.id == codebaseID)
        #expect(metrics.codebaseName == "C")
        #expect(metrics.typeCount == 5)
        #expect(metrics.moduleCount == 1)
        #expect(metrics.maxComplexity == 0)
        #expect(metrics.cycleCount == 1)
        #expect(metrics.deadCodeCount == 0)
        #expect(metrics.healthScore == 1)
    }

    @Test func metricsFailForACodebaseThatWasNeverIndexed() async throws {
        let store = try makeStore(artifact: nil)
        await #expect(throws: CodebaseInsights.Failure.codebaseNotIndexed("C")) {
            try await GetCodebaseMetricsIntent(codebase: entity).answer(in: store)
        }
    }

    @Test func metricsFailForACodebaseThatIsGone() async throws {
        let store = try makeStore()
        let gone = CodebaseEntity(id: UUID(), name: "Gone", projectTitle: "P")
        await #expect(throws: CodebaseInsights.Failure.codebaseNotFound) {
            try await GetCodebaseMetricsIntent(codebase: gone).answer(in: store)
        }
    }

    // MARK: - Run Quality Check

    @Test func theBuiltInBudgetsPassACycle() async throws {
        let result = try await RunQualityCheckIntent(codebase: entity).answer(in: makeStore())

        #expect(result.id == codebaseID)
        #expect(result.isPassing)
        #expect(result.findingCount == 0)
        #expect(!result.usesConfiguredRules)
        #expect(result.checkedRuleCount > 0)
    }

    @Test func findingsSplitBySeverityAcrossEveryLens() async throws {
        let diagnostics = [
            ParseDiagnostic(
                location: SourceLocation(filePath: "Wheel.swift", line: 2, column: 1), kind: .error, message: "x"),
            ParseDiagnostic(
                location: SourceLocation(filePath: "Wheel.swift", line: 3, column: 1), kind: .missing, message: "y")
        ]
        let store = try makeStore(
            artifact: Self.artifact(diagnostics: diagnostics), rules: QualityRules(cycles: CycleRule(scope: .types)))
        let result = try await RunQualityCheckIntent(codebase: entity).answer(in: store)

        #expect(!result.isPassing)
        #expect(result.usesConfiguredRules)
        #expect(result.checkedRuleCount == 1)
        // The cycle violation and the parse error are critical; the missing token is a warning.
        #expect(result.criticalCount == 2)
        #expect(result.warningCount == 1)
        #expect(result.infoCount == 0)
    }

    @Test func qualityCheckFailsForACodebaseThatWasNeverIndexed() async throws {
        let store = try makeStore(artifact: nil)
        await #expect(throws: CodebaseInsights.Failure.codebaseNotIndexed("C")) {
            try await RunQualityCheckIntent(codebase: entity).answer(in: store)
        }
    }

    // MARK: - Get Dependents

    @Test func dependentsAnswerWithEveryTypeThatDependsOnTheRoot() async throws {
        let dependents = try await GetDependentsIntent(codebase: entity, type: "Engine").answer(in: makeStore())

        #expect(dependents.map(\.qualifiedName) == ["Driver"])
        #expect(dependents.first?.id == "\(codebaseID.uuidString)/Driver")
        #expect(dependents.first?.location == "Driver.swift:1")
    }

    @Test func dependentsAreEmptyForATypeNothingDependsOn() async throws {
        let dependents = try await GetDependentsIntent(codebase: entity, type: "Wheel").answer(in: makeStore())

        #expect(dependents.isEmpty)
    }

    @Test func dependentsFailForATypeThatIsNotThere() async throws {
        let store = try makeStore()
        await #expect(throws: CodebaseInsights.Failure.typeNotFound("Nope", "C")) {
            try await GetDependentsIntent(codebase: entity, type: "Nope").answer(in: store)
        }
    }

    @Test func dependentsFailForACodebaseThatWasNeverIndexed() async throws {
        let store = try makeStore(artifact: nil)
        await #expect(throws: CodebaseInsights.Failure.codebaseNotIndexed("C")) {
            try await GetDependentsIntent(codebase: entity, type: "Engine").answer(in: store)
        }
    }

    // MARK: - Resolving a stored type

    @Test func aTypeResolvesInTheCodebaseItsIDNames() async throws {
        let store = try makeStore()
        let otherID = UUID()
        store.projects[0].codebases.append(Codebase(id: otherID, name: "D", directoryPath: "/d"))
        store.artifacts[otherID] = CodeArtifact(
            metadata: .init(sourceLanguage: .swift, filePaths: ["Other.swift"]),
            types: [
                TypeDeclaration(
                    id: "Driver", name: "Driver", qualifiedName: "Driver", kind: .class, accessLevel: .public,
                    location: SourceLocation(filePath: "Other.swift", line: 7, column: 1))
            ])
        let identifiers = ["\(otherID.uuidString)/Driver", "\(codebaseID.uuidString)/Driver", "Driver", "nope/Driver"]

        let types = try await CodebaseInsights(store: store).types(identifiedBy: identifiers)

        #expect(types.map(\.id) == Array(identifiers.prefix(2)))
        #expect(types.map(\.location) == ["Other.swift:7", "Driver.swift:1"])
    }
}
