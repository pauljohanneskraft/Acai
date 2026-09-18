import Foundation
import Testing
@testable import AcaiApp

@Suite("Codebase guided route offer")
@MainActor
struct CodebaseGuidedRouteOfferTests {
    @Test func legacyCodebaseWithoutTheFieldDecodesAsNeverOffered() throws {
        let legacyJSON = Data("""
        {
            "id": "8C7E6B2B-8B8B-4B8B-8B8B-8B8B8B8B8B8B",
            "name": "MyLibrary",
            "directoryPath": "/Users/me/Code/MyLibrary",
            "hasArtifact": true,
            "hasParseErrors": false,
            "parseDiagnosticCount": 0
        }
        """.utf8)

        let codebase = try JSONDecoder().decode(Codebase.self, from: legacyJSON)

        #expect(codebase.guidedRoute == nil)
    }

    @Test func dismissalRoundTrips() throws {
        var codebase = Codebase(name: "MyLibrary", directoryPath: "/Users/me/Code/MyLibrary")
        codebase.guidedRoute = .dismissed

        let decoded = try JSONDecoder().decode(Codebase.self, from: JSONEncoder().encode(codebase))

        #expect(decoded.guidedRoute == .dismissed)
    }

    @Test func firstIndexOffersTheRoute() async throws {
        try await withIndexableModel(initial: nil) { model, codebaseID in
            await model.editing.reindex(codebaseID: codebaseID)
            #expect(model.codebase(for: codebaseID)?.guidedRoute == .offered)
        }
    }

    @Test func aDismissedRouteIsNotOfferedAgainOnALaterFirstIndex() async throws {
        try await withIndexableModel(initial: .dismissed) { model, codebaseID in
            await model.editing.reindex(codebaseID: codebaseID)
            #expect(model.codebase(for: codebaseID)?.guidedRoute == .dismissed)
        }
    }

    @Test func reindexingAnAlreadyIndexedCodebaseDoesNotOfferTheRoute() async throws {
        try await withIndexableModel(initial: nil) { model, codebaseID in
            await model.editing.reindex(codebaseID: codebaseID)
            model.editing.mutateCodebase(codebaseID) { $0.guidedRoute = nil }
            await model.editing.reindex(codebaseID: codebaseID)
            #expect(model.codebase(for: codebaseID)?.guidedRoute == nil)
        }
    }

    private func withIndexableModel(
        initial: GuidedRouteOffer?, _ body: (ProjectBrowserViewModel, UUID) async throws -> Void
    ) async throws {
        let baseDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let sourceDir = baseDir.appendingPathComponent("source", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: baseDir) }
        try "class Widget {}\n".write(
            to: sourceDir.appendingPathComponent("Widget.swift"), atomically: true, encoding: .utf8)

        let codebaseID = UUID()
        var codebase = Codebase(id: codebaseID, name: "C", directoryPath: sourceDir.path)
        codebase.guidedRoute = initial
        let store = ProjectStore(baseDir: baseDir)
        store.projects = [Project(title: "P", subtitle: "", codebases: [codebase])]
        try await body(ProjectBrowserViewModel(store: store), codebaseID)
    }
}
