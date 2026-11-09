import Testing
import AcaiCore
@testable import AcaiDiff

/// A type's `id` is not stable: project analysis re-scopes it to the file path as soon as a second
/// file declares the same name, and always for a file-private type. Both sides here go through the
/// real scoping pipeline, so the ids under test are the ones analysis actually produces.
@Suite("Diff: stable type identity")
struct ArtifactDifferIdentityTests {

    private func file(
        _ path: String, _ types: [TypeDeclaration], _ relationships: [Relationship] = []
    ) -> CodeArtifact {
        CodeArtifact(
            metadata: .init(sourceLanguage: .swift, filePaths: [path]),
            types: types,
            relationships: relationships)
    }

    private func type(_ name: String, in path: String, access: AccessLevel = .internal) -> TypeDeclaration {
        TypeDeclaration(
            id: name, name: name, qualifiedName: name, kind: .class, accessLevel: access,
            location: SourceLocation(filePath: path, line: 1, column: 1))
    }

    /// Scopes each file's ids to its module, re-scopes the names two files declare, then merges and
    /// enriches — the order `AnalysisService.analyzeProject` applies.
    private func analysed(_ files: [CodeArtifact]) -> CodeArtifact {
        let modules = ModuleMap(roots: ["."], filePaths: files.flatMap(\.metadata.filePaths))
        let scoped = files.map { $0.scopingTypeIDs(modules: modules) }
        let collisions = CollidingTypeIDs(files: scoped)
        let disambiguated = scoped.map { collisions.disambiguating($0) }
        return disambiguated.dropFirst()
            .reduce(disambiguated[0]) { $0.merging(with: $1) }
            .enriched()
    }

    private let service = "Sources/App/Service.swift"
    private let helper = "Sources/App/Helper.swift"

    @Test("An unrelated file declaring the same type name adds a type and removes nothing")
    func addingASameNamedTypeElsewhereIsPurelyAnAddition() {
        let declaring = [
            file(service, [type("Service", in: service)],
                 [Relationship(kind: .dependency, source: "Service", target: "Helper")]),
            file(helper, [type("Helper", in: helper)])
        ]
        let other = "Sources/App/Other.swift"
        let old = analysed(declaring)
        let new = analysed(declaring + [file(other, [type("Service", in: other)])])

        // The collision re-scopes both `Service` ids on the new side, including the untouched one.
        #expect(new.flattened().contains { $0.id == "\(service):Service" })

        let diff = ArtifactDiffer().diff(old: old, new: new)
        #expect(diff.addedTypes == ["\(other):Service"])
        #expect(diff.removedTypes.isEmpty)
        #expect(diff.changedTypes.isEmpty)
        #expect(diff.addedRelationships.isEmpty)
        #expect(diff.removedRelationships.isEmpty)
        #expect(diff.changedRelationships.isEmpty)
    }

    @Test("Renaming the file that declares a private type removes nothing")
    func renamingAPrivateTypesFileIsNotARemoval() {
        let before = "Sources/App/Secret.swift"
        let after = "Sources/App/Hidden.swift"
        let old = analysed([
            file(service, [type("Service", in: service)]),
            file(before, [type("Secret", in: before, access: .private)])
        ])
        let new = analysed([
            file(service, [type("Service", in: service)]),
            file(after, [type("Secret", in: after, access: .private)])
        ])

        #expect(old.flattened().contains { $0.id == "\(before):Secret" })
        #expect(new.flattened().contains { $0.id == "\(after):Secret" })

        let diff = ArtifactDiffer().diff(old: old, new: new)
        #expect(diff.addedTypes.isEmpty)
        #expect(diff.removedTypes.isEmpty)
        #expect(diff.changedTypes.isEmpty)
    }

    @Test("Two files declaring one name on both sides still match by file path")
    func anAmbiguousNameFallsBackToTheFilePath() {
        let other = "Sources/App/Other.swift"
        let both = [
            file(service, [type("Service", in: service)]),
            file(other, [type("Service", in: other)])
        ]
        let old = analysed(both)
        let new = analysed([both[0]])

        let diff = ArtifactDiffer().diff(old: old, new: new)
        #expect(diff.addedTypes.isEmpty)
        // Only the copy in the deleted file goes; the one in `Service.swift` is matched by its path
        // even though its id went back from a file scope to a module scope.
        #expect(diff.removedTypes == ["\(other):Service"])
    }
}
