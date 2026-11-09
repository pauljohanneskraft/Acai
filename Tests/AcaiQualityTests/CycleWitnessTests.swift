import Testing
import AcaiCore
@testable import AcaiQuality

/// A module cycle used to be reported as member names only, which gave no hint of which type
/// references formed it. Each hop now carries the referencing edge and where it is written.
@Suite("Quality: Cycle witnesses")
struct CycleWitnessTests {

    private func type(_ name: String, module: String, line: Int = 1) -> TypeDeclaration {
        TypeDeclaration(
            id: name, name: name, qualifiedName: name, kind: .class, accessLevel: .internal,
            location: SourceLocation(filePath: "Sources/\(module)/\(name).swift", line: line, column: 1))
    }

    /// `Core.A` ⇄ `Infra.B`: one hop each way, each witnessed by exactly one edge.
    private func twoModuleCycle() -> CodeArtifact {
        CodeArtifact(
            metadata: .init(sourceLanguage: .swift),
            types: [type("A", module: "Core", line: 12), type("B", module: "Infra", line: 30)],
            relationships: [
                Relationship(kind: .aggregation, source: "A", target: "B"),
                Relationship(kind: .dependency, source: "B", target: "A")
            ]
        ).enriched()
    }

    private func finder(_ artifact: CodeArtifact) -> CycleFinder {
        CycleFinder(
            artifact: artifact,
            languageResolver: LanguageConfigurationResolver(single: .test))
    }

    @Test func eachModuleHopNamesItsReferencingEdgeAndLocation() throws {
        let cycle = try #require(finder(twoModuleCycle()).cycles(scope: .modules).first)
        #expect(cycle.members == ["Core", "Infra"])
        #expect(cycle.witnesses.count == 2)

        let outbound = try #require(cycle.witnesses.first { $0.from == "Core" })
        #expect(outbound.to == "Infra")
        #expect(outbound.sourceType == "A")
        #expect(outbound.targetType == "B")
        #expect(outbound.kind == .aggregation)
        #expect(outbound.location?.filePath == "Sources/Core/A.swift")
        #expect(outbound.location?.line == 12)
        #expect(outbound.referenceFile == nil)

        let inbound = try #require(cycle.witnesses.first { $0.from == "Infra" })
        #expect(inbound.sourceType == "B")
        #expect(inbound.targetType == "A")
        #expect(inbound.kind == .dependency)
        #expect(inbound.location?.line == 30)
    }

    @Test func theViolationCarriesTheWitnessesInItsMessageAndDetail() throws {
        let violation = try #require(finder(twoModuleCycle()).violations(scope: .modules).first)
        #expect(violation.ruleKind == "cycle")
        #expect(violation.subject == "Core,Infra")
        #expect(violation.detail["scope"] == "modules")
        let witnesses = try #require(violation.detail["witnesses"])
        #expect(witnesses.contains("Core → Infra via A → B (aggregation) at Sources/Core/A.swift:12"))
        #expect(witnesses.contains("Infra → Core via B → A (dependency) at Sources/Infra/B.swift:30"))
        #expect(violation.message.contains("Module dependency cycle: Core → Infra → Core."))
        #expect(violation.message.contains(witnesses))
    }

    /// A witness names the file the reference is written in whenever provenance puts it outside the
    /// referencing type's own file — the same provenance that decided which module the hop leaves.
    @Test func aWitnessNamesTheReferencingFileWhenProvenanceDiffers() throws {
        let artifact = CodeArtifact(
            metadata: .init(sourceLanguage: .swift),
            types: [type("A", module: "Core"), type("B", module: "Infra")],
            relationships: [
                Relationship(kind: .dependency, source: "A", target: "B", origin: "Sources/Core/A+Extras.swift"),
                Relationship(kind: .dependency, source: "B", target: "A")
            ]
        ).enriched()
        let cycle = try #require(finder(artifact).cycles(scope: .modules).first)
        let outbound = try #require(cycle.witnesses.first { $0.from == "Core" })
        #expect(outbound.referenceFile == "Sources/Core/A+Extras.swift")
        #expect(outbound.description.contains("(reference in Sources/Core/A+Extras.swift)"))
    }

    /// Several edges can form the same hop; the reported witness is the stable first one.
    @Test func oneWitnessPerHopChosenDeterministically() throws {
        let artifact = CodeArtifact(
            metadata: .init(sourceLanguage: .swift),
            types: [
                type("A", module: "Core"), type("Z", module: "Core"),
                type("B", module: "Infra"), type("Y", module: "Infra")
            ],
            relationships: [
                Relationship(kind: .dependency, source: "Z", target: "Y"),
                Relationship(kind: .dependency, source: "A", target: "B"),
                Relationship(kind: .dependency, source: "B", target: "A")
            ]
        ).enriched()
        let cycle = try #require(finder(artifact).cycles(scope: .modules).first)
        #expect(cycle.witnesses.count == 2)
        #expect(cycle.witnesses.map(\.sourceType) == ["A", "B"])
    }

    @Test func typeScopeCyclesCarryNoWitnessesAndStillPointAtAMember() throws {
        let violation = try #require(finder(twoModuleCycle()).violations(scope: .types).first)
        #expect(violation.detail["witnesses"] == nil)
        #expect(violation.detail["scope"] == "types")
        #expect(violation.source?.filePath == "Sources/Core/A.swift")
        #expect(violation.message == "Type dependency cycle: A → B → A.")
    }

    @Test func anAcyclicModuleGraphReportsNothing() {
        let artifact = CodeArtifact(
            metadata: .init(sourceLanguage: .swift),
            types: [type("A", module: "Core"), type("B", module: "Infra")],
            relationships: [Relationship(kind: .dependency, source: "A", target: "B")]
        ).enriched()
        #expect(finder(artifact).cycles(scope: .modules).isEmpty)
    }
}
