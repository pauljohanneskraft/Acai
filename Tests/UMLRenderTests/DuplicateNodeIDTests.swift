import CoreGraphics
import Testing
@testable import UMLRender
import UMLCore

/// Two distinct types can carry the same `id` when a language doesn't qualify by module — e.g.
/// two top-level Python classes of the same name in different files. The diagram layout maps
/// type ids with `Dictionary(uniqueKeysWithValues:)`, which traps on duplicate keys (the crash
/// reported on a real Python codebase). `DiagramLayoutModel` must collapse such nodes to a
/// unique-by-id set.
@Suite("Duplicate node-id handling")
struct DuplicateNodeIDTests {

    private func artifactWithDuplicateIDs() -> CodeArtifact {
        let makeType = { (file: String) in
            TypeDeclaration(
                id: "Config", name: "Config", qualifiedName: "Config", kind: .class,
                accessLevel: .public,
                location: SourceLocation(filePath: file, line: 1, column: 1)
            )
        }
        return CodeArtifact(
            metadata: .init(sourceLanguage: .init(rawValue: "python"), filePaths: ["a.py", "b.py"]),
            types: [makeType("a.py"), makeType("b.py")]
        )
    }

    @Test func layoutModelCollapsesDuplicateIDs() {
        let model = DiagramLayoutModel(
            artifact: artifactWithDuplicateIDs(),
            configuration: ClassDiagramConfiguration(),
            language: LanguageConfiguration()
        )
        let ids = model.nodes.map(\.id)
        #expect(Set(ids).count == ids.count, "diagram node ids must be unique")
        #expect(ids == ["Config"])
    }

    @Test func performLayoutDoesNotTrapOnDuplicateIDs() {
        let model = DiagramLayoutModel(
            artifact: artifactWithDuplicateIDs(),
            configuration: ClassDiagramConfiguration(),
            language: LanguageConfiguration()
        )
        // Mirrors the app's `Dictionary(uniqueKeysWithValues:)` layout map, which traps on dupes.
        let sizes = Dictionary(uniqueKeysWithValues: model.nodes.map { ($0.id, CGSize(width: 100, height: 60)) })
        let positions = model.performLayout(sizes: sizes)
        #expect(positions["Config"] != nil)
    }
}
