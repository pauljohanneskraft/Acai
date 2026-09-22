import Testing
@testable import AcaiDiagram
@testable import AcaiCore

@Suite("Diagram Node Limit")
struct DiagramNodeLimitTests {

    // MARK: - DiagramNodeLimit

    @Test func unlimitedNeverThrows() throws {
        try DiagramNodeLimit(maximum: nil).validate(nodeCount: 1_000_000)
    }

    @Test func withinLimitDoesNotThrow() throws {
        try DiagramNodeLimit(maximum: 10).validate(nodeCount: 10)
    }

    @Test func exceedingLimitThrowsWithCountAndLimit() {
        #expect {
            try DiagramNodeLimit(maximum: 5).validate(nodeCount: 6)
        } throws: { error in
            guard let requestError = error as? DiagramRequestError else { return false }
            return requestError.message.contains("6 nodes")
                && requestError.message.contains("limit of 5")
                && requestError.message.contains("focus")
        }
    }

    // MARK: - ClassDiagramTextExporter

    private func twoTypeArtifact() -> CodeArtifact {
        CodeArtifact(
            metadata: .init(sourceLanguage: .swift, filePaths: ["A.swift", "B.swift"]),
            types: [
                TypeDeclaration(id: "A", name: "A", qualifiedName: "A", kind: .class, accessLevel: .public),
                TypeDeclaration(id: "B", name: "B", qualifiedName: "B", kind: .class, accessLevel: .public)
            ]
        )
    }

    @Test func classDiagramWithinLimitSucceeds() throws {
        var options = ClassDiagramOptions()
        options.maxNodes = 2
        let export = try ClassDiagramTextExporter(options: options).export(from: twoTypeArtifact())
        #expect(export.render(.dot).contains("digraph"))
    }

    @Test func classDiagramExceedingLimitThrows() {
        var options = ClassDiagramOptions()
        options.maxNodes = 1
        #expect {
            try ClassDiagramTextExporter(options: options).export(from: twoTypeArtifact())
        } throws: { error in
            (error as? DiagramRequestError)?.message.contains("2 nodes") ?? false
        }
    }

    @Test func classDiagramWithNoLimitNeverThrows() throws {
        let options = ClassDiagramOptions()
        #expect(options.maxNodes == nil)
        _ = try ClassDiagramTextExporter(options: options).export(from: twoTypeArtifact())
    }

    // MARK: - PackageDiagramTextExporter

    private func twoModuleArtifact() -> CodeArtifact {
        CodeArtifact(
            metadata: .init(sourceLanguage: .swift),
            types: [
                TypeDeclaration(
                    id: "A", name: "A", qualifiedName: "A", kind: .class, accessLevel: .public,
                    location: .init(filePath: "Sources/ModuleA/A.swift", line: 1, column: 1)
                ),
                TypeDeclaration(
                    id: "B", name: "B", qualifiedName: "B", kind: .class, accessLevel: .public,
                    location: .init(filePath: "Sources/ModuleB/B.swift", line: 1, column: 1)
                )
            ]
        )
    }

    @Test func packageDiagramExceedingLimitThrows() {
        let languages = LanguageConfigurationResolver(single: .test)
        #expect {
            try PackageDiagramTextExporter(languages: languages, theme: nil, maxNodes: 1)
                .export(from: twoModuleArtifact())
        } throws: { error in
            (error as? DiagramRequestError)?.message.contains("2 nodes") ?? false
        }
    }

    @Test func packageDiagramWithinLimitSucceeds() throws {
        let languages = LanguageConfigurationResolver(single: .test)
        let export = try PackageDiagramTextExporter(languages: languages, theme: nil, maxNodes: 2)
            .export(from: twoModuleArtifact())
        #expect(export.render(.dot).contains("digraph"))
    }
}
