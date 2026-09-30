#if os(macOS)
import Foundation
import Testing
import AcaiLibrary
@testable import AcaiRender

@Suite("Atlas Diagram Set")
struct AtlasDiagramSetTests {

    @Test func theCallGraphPageHonoursTheNodeLimit() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("atlas-diagram-set-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try """
        class Service {
            let repository: Repository = Repository()
            func run() { repository.save() }
        }
        class Repository {
            func save() {}
        }
        """.write(to: dir.appendingPathComponent("Sample.swift"), atomically: true, encoding: .utf8)
        let artifact = try await AnalysisService.standard.analyzeProject(at: dir, allowedLanguages: [.swift])

        let pages = await AtlasDiagramSet(
            scale: 1, palette: .light, languages: artifact.standardLanguageResolver, maxNodes: 1
        ).pages(for: artifact)

        let callGraph = try #require(pages.first { $0.name == "Call Graph" })
        #expect(callGraph.image.failureReason?.contains("exceeding the limit of 1") == true)
    }
}
#endif
