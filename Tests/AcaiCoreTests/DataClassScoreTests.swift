import Foundation
import Testing
@testable import AcaiCore

/// Computed properties (a SwiftUI `View`'s `body`, derived getters) are behaviour, not data, and
/// must not inflate ``TypeDeclaration/dataClassScore``. See ``Member/isStoredProperty``/``Member/isBehaviour``.
@Suite("Core: Data-Class Score")
struct DataClassScoreTests {

    private func type(
        _ name: String, kind: TypeKind, module: String, members: [Member]
    ) -> TypeDeclaration {
        TypeDeclaration(
            id: name, name: name, qualifiedName: name, kind: kind, accessLevel: .internal, members: members,
            location: SourceLocation(filePath: "Sources/\(module)/\(name).swift", line: 1, column: 1))
    }

    private func score(of name: String, in type: TypeDeclaration) -> Double? {
        CodeArtifact(metadata: .init(sourceLanguage: .swift), types: [type], relationships: [])
            .enriched().computeMetrics().types.first { $0.name == name }?.dataClassScore
    }

    @Test func computedPropertiesCountAsBehaviour() {
        let view = type("Row", kind: .struct, module: "App", members: [
            Member(name: "title", kind: .property, accessLevel: .internal),
            Member(name: "body", kind: .property, accessLevel: .internal, isComputed: true)
        ])
        #expect(score(of: "Row", in: view) == 0.5)
    }

    @Test func pureDataTransferObjectStaysFullyData() {
        let dto = type("Point", kind: .struct, module: "App", members: [
            Member(name: "x", kind: .property, accessLevel: .public),
            Member(name: "y", kind: .property, accessLevel: .public),
            Member(name: "z", kind: .property, accessLevel: .public)
        ])
        #expect(score(of: "Point", in: dto) == 1.0)
    }

    @Test func computedOnlyTypeIsPureBehaviour() {
        let gate = type("Gate", kind: .struct, module: "App", members: [
            Member(name: "isOpen", kind: .property, accessLevel: .public, isComputed: true)
        ])
        #expect(score(of: "Gate", in: gate) == 0.0)
    }
}
