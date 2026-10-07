import Foundation
import Testing
@testable import AcaiLibrary

/// Indexes Acai's own sources: a large, many-module Swift codebase whose type names repeat across
/// modules (`AcaiCLI.ThemeOption`, `AcaiMCP.ThemeOption`), which a hand-written fixture can't match.
@Suite("Self-analysis", .timeLimit(.minutes(5)))
struct SelfAnalysisTests {
    private let packageRoot = URL(fileURLWithPath: "\(#filePath)")
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    private func analyzeAcai() async throws -> CodeArtifact {
        try await AnalysisService.standard.analyzeProject(
            at: packageRoot, allowedLanguages: [.swift]
        ) { path in
            path.hasPrefix("Sources/")
        }
    }

    @Test("Every type in Acai has its own id, and the diagrams that index by id build")
    func indexesAcaiItself() async throws {
        let artifact = try await analyzeAcai()
        let types = artifact.flattened()

        let duplicates = Dictionary(grouping: types, by: \.id).filter { $0.value.count > 1 }.keys.sorted()
        #expect(duplicates.isEmpty, "duplicate type ids: \(duplicates.prefix(20))")
        #expect(types.count > 1_000)
        #expect(Set(types.map(\.idScope.module)).count >= 18)
        // A generated `App/Acai.xcodeproj` is a second project root, which project-qualifies every module.
        let modules = ModuleMap(artifact: artifact)
        let themeOptions = types.filter { $0.name == "ThemeOption" }
        let themeModules = themeOptions.compactMap { $0.module?.components(separatedBy: "/").last }
        #expect(themeModules.sorted() == ["AcaiCLI", "AcaiMCP"])
        #expect(themeOptions.allSatisfy {
            $0.id == "\(modules.module(forFilePath: $0.location?.filePath ?? "")).ThemeOption"
        })

        let callGraph = CallGraphBuilder().build(from: artifact)
        #expect(!callGraph.edges.isEmpty)

        var options = ClassDiagramOptions(languages: artifact.standardLanguageResolver)
        options.groupBy = .byDirectory
        #expect(!ClassDiagramDOTRenderer(options: options).generate(from: artifact).isEmpty)
    }
}
