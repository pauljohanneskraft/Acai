import Foundation
import Testing
import AcaiCore
import AcaiDiff
@testable import AcaiApp

@Suite("CompareChangedFiles")
struct CompareChangedFilesTests {
    private func type(_ name: String, file: String, access: AccessLevel = .public) -> TypeDeclaration {
        TypeDeclaration(
            id: name, name: name, qualifiedName: name, kind: .class, accessLevel: access,
            location: SourceLocation(filePath: file, line: 1, column: 1))
    }

    private func artifact(_ types: [TypeDeclaration]) -> CodeArtifact {
        CodeArtifact(metadata: .init(sourceLanguage: CodeArtifact.SourceLanguage(rawValue: "swift")), types: types)
    }

    @Test func groupsAddedRemovedAndChangedTypesByTheirOwnFile() {
        let old = artifact([
            type("A", file: "Sources/A.swift"),
            type("B", file: "Sources/B.swift")
        ])
        let new = artifact([
            type("A", file: "Sources/A.swift", access: .internal),
            type("C", file: "Sources/C.swift")
        ])
        let diff = ArtifactDiffer().diff(old: old, new: new)

        let files = CompareChangedFiles(diff: diff, oldArtifact: old, newArtifact: new).files

        let byPath = Dictionary(uniqueKeysWithValues: files.map { ($0.filePath, $0.typeIDs) })
        #expect(byPath["Sources/A.swift"] == ["A"])
        #expect(byPath["Sources/B.swift"] == ["B"])
        #expect(byPath["Sources/C.swift"] == ["C"])
        #expect(files.count == 3)
    }

    @Test func twoChangedTypesInTheSameFileGroupTogether() {
        let old = artifact([
            type("A", file: "Sources/Shared.swift"),
            type("B", file: "Sources/Shared.swift")
        ])
        let new = artifact([
            type("A", file: "Sources/Shared.swift", access: .internal),
            type("B", file: "Sources/Shared.swift", access: .internal)
        ])
        let diff = ArtifactDiffer().diff(old: old, new: new)

        let files = CompareChangedFiles(diff: diff, oldArtifact: old, newArtifact: new).files

        #expect(files.count == 1)
        #expect(files.first?.typeIDs == ["A", "B"])
    }

    @Test func noStructuralChangeMeansNoChangedFiles() {
        let same = artifact([type("A", file: "Sources/A.swift")])
        let diff = ArtifactDiffer().diff(old: same, new: same)

        let files = CompareChangedFiles(diff: diff, oldArtifact: same, newArtifact: same).files

        #expect(files.isEmpty)
    }
}
