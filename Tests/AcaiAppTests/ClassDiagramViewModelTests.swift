import Testing
import AcaiCore
import AcaiRender
@testable import AcaiApp

@Suite("Class Diagram View Model")
@MainActor
struct ClassDiagramViewModelTests {

    private func type(_ name: String, _ access: AccessLevel) -> TypeDeclaration {
        TypeDeclaration(
            id: name, name: name, qualifiedName: name, kind: .class,
            accessLevel: access,
            location: SourceLocation(filePath: "A.swift", line: 1, column: 1)
        )
    }

    private func viewModel(
        types: [TypeDeclaration],
        configure: (inout ClassDiagramConfiguration) -> Void = { _ in }
    ) -> ClassDiagramViewModel {
        let artifact = CodeArtifact(
            metadata: .init(sourceLanguage: .swift, filePaths: ["A.swift"]),
            types: types
        )
        var config = ClassDiagramConfiguration()
        configure(&config)
        return ClassDiagramViewModel(
            codebase: Codebase(name: "c", directoryPath: "/tmp"),
            artifact: artifact,
            configuration: config
        )
    }

    @Test func typesBelowMinimumAccessAreHidden() {
        let vm = viewModel(
            types: [type("Pub", .public), type("Inter", .internal), type("Priv", .private)]
        ) { $0.minimumAccessLevel = .public }
        #expect(Set(vm.nodes.map(\.id)) == ["Pub"])
    }

    @Test func allTypesShownWhenNoMinimum() {
        let vm = viewModel(types: [type("Pub", .public), type("Inter", .internal)])
        #expect(Set(vm.nodes.map(\.id)) == ["Pub", "Inter"])
    }

    private func type(_ name: String, file: String) -> TypeDeclaration {
        TypeDeclaration(
            id: name, name: name, qualifiedName: name, kind: .class, accessLevel: .public,
            location: SourceLocation(filePath: file, line: 1, column: 1)
        )
    }

    @Test func groupingBoxesNestPerDirectoryLevelAndEmptyWhenUngrouped() {
        let types = [type("A", file: "Sources/Foo/A.swift"), type("B", file: "Sources/Bar/B.swift")]
        let directory = viewModel(types: types) { $0.grouping = .directory }
        // One outer box for `Sources`, plus one for each of `Sources/Foo` and `Sources/Bar`.
        let boxes = directory.groupingBoxes
        #expect(boxes.count == 3)
        #expect(boxes.filter { $0.depth == 1 }.map(\.label) == ["Sources"])
        #expect(Set(boxes.filter { $0.depth == 2 }.map(\.label)) == ["Foo", "Bar"])
        let ungrouped = viewModel(types: types) { $0.grouping = .none }
        #expect(ungrouped.groupingBoxes.isEmpty)
    }
}
