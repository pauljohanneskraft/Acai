import Foundation
import Testing
@testable import AcaiLibrary

@Suite("Module-scoped type ids")
struct ModuleScopedTypeIDTests {
    private func analyze(_ files: [String: String]) async throws -> CodeArtifact {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("acai-module-ids-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        for (path, source) in files {
            let url = root.appendingPathComponent(path)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try source.write(to: url, atomically: true, encoding: .utf8)
        }
        return try await AnalysisService.standard.analyzeProject(at: root, allowedLanguages: [.swift])
    }

    @Test("Same-named types in two modules keep apart, and each module's references bind to its own")
    func sameNameInTwoModules() async throws {
        let artifact = try await analyze([
            "Sources/CLI/Option.swift": "enum Option {}\nstruct Command { var option: Option }",
            "Sources/MCP/Option.swift": "enum Option {}\nstruct Tool { var option: Option }"
        ])
        #expect(Set(artifact.flattened().map(\.id)) == ["CLI.Option", "CLI.Command", "MCP.Option", "MCP.Tool"])
        let edges = Set(artifact.relationships.map { "\($0.source)->\($0.target)" })
        #expect(edges == ["CLI.Command->CLI.Option", "MCP.Tool->MCP.Option"])
    }

    @Test("A name one module declares in two files is scoped to each file")
    func sameNameInTwoFilesOfOneModule() async throws {
        let artifact = try await analyze([
            "Sources/App/A.swift": "private struct Helper {}",
            "Sources/App/B.swift": "private struct Helper {}"
        ])
        #expect(Set(artifact.flattened().map(\.id)) == ["Sources/App/A.swift:Helper", "Sources/App/B.swift:Helper"])
    }

    @Test("A file-private type elsewhere in the module leaves an existing type's id unchanged")
    func filePrivateTypeDoesNotRenameItsNamesake() async throws {
        let before = try await analyze(["Sources/App/A.swift": "struct Helper {}"])
        let after = try await analyze([
            "Sources/App/A.swift": "struct Helper {}",
            "Sources/App/B.swift": "fileprivate struct Helper {}"
        ])
        #expect(before.flattened().map(\.id) == ["App.Helper"])
        #expect(Set(after.flattened().map(\.id)) == ["App.Helper", "Sources/App/B.swift:Helper"])
    }

    @Test("An extension in another module merges into the type it extends")
    func crossModuleExtension() async throws {
        let artifact = try await analyze([
            "Sources/Core/Base.swift": "public class Base { public struct Inner {} }",
            "Sources/App/Base+App.swift": "extension Base { func extra() {} }\nstruct User { var inner: Base.Inner }"
        ])
        let base = try #require(artifact.types.first { $0.id == "Core.Base" })
        #expect(base.members.map(\.name).contains("extra"))
        #expect(artifact.relationships.contains { $0.source == "App.User" && $0.target == "Core.Base.Inner" })
    }

    @Test("A root named the way source spells it is not its own dependent")
    func impactRootSpelledUnqualified() async throws {
        let artifact = try await analyze([
            "Sources/Core/Outer.swift": "struct Outer { struct Inner {} }\nstruct User { var inner: Outer.Inner }"
        ])
        let report = ImpactAnalysis(artifact: artifact, rootType: "Outer.Inner").report
        #expect(report.found)
        #expect(report.dependents.map(\.id) == ["Core.User"])
    }

    @Test("A state variable on a nested type is found by the name source spells")
    func stateFromNestedType() async throws {
        let artifact = try await analyze([
            "Sources/Core/Outer.swift": """
                enum Phase { case idle, running }
                struct Outer { struct Inner { var phase = Phase.idle; mutating func run() { phase = .running } } }
                """
        ])
        let diagram = try StateDiagramBuilder(
            configuration: StateDiagramConfiguration(typeName: "Outer.Inner", variableName: "phase")
        ).build(from: artifact)
        #expect(diagram.states.contains { $0.name == "running" })
    }

    @Test("A type nested in another module's extension keeps its own id and edges in the class diagram")
    func classDiagramKeepsCrossModuleExtensionNestedType() async throws {
        let artifact = try await analyze([
            "Sources/Core/Base.swift": "public class Base {}",
            "Sources/App/Base+App.swift": "extension Base { struct Extra {} }\nstruct User { var extra: Base.Extra }"
        ])
        let diagram = ClassDiagramBuilder(
            options: ClassDiagramOptions(languages: artifact.standardLanguageResolver)
        ).build(from: artifact)
        #expect(diagram.types.contains { $0.id == "App.Base.Extra" })
        #expect(diagram.externalTypes.isEmpty)
        #expect(diagram.relationships.contains { $0.source == "App.User" && $0.target == "App.Base.Extra" })
    }
}
