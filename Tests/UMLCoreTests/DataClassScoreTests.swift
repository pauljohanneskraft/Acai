import Foundation
import Testing
@testable import UMLCore

/// Regression tests for the data-class / anemic score after the computed-property fix: computed
/// properties (a SwiftUI `View`'s `body`, derived getters) are behaviour, not data, so they no longer
/// inflate ``TypeDeclaration/dataClassScore`` toward the 1.0 false positive that dominated the smell
/// output. See ``TypeDeclaration/dataClassScore`` and ``Member/isStoredProperty``/``Member/isBehaviour``.
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
        // A SwiftUI-View shape: one stored `let` + a computed `body`. The computed property is
        // behaviour (its getter is code), so this is 1 stored of 2 → 0.5, not the old 1.0 false positive.
        let view = type("Row", kind: .struct, module: "App", members: [
            Member(name: "title", kind: .property, accessLevel: .internal),
            Member(name: "body", kind: .property, accessLevel: .internal, isComputed: true)
        ])
        #expect(score(of: "Row", in: view) == 0.5)
    }

    @Test func pureDataTransferObjectStaysFullyData() {
        // Guard against over-correction: a DTO of stored `let`s only must still score 1.0 (pure data).
        let dto = type("Point", kind: .struct, module: "App", members: [
            Member(name: "x", kind: .property, accessLevel: .public),
            Member(name: "y", kind: .property, accessLevel: .public),
            Member(name: "z", kind: .property, accessLevel: .public)
        ])
        #expect(score(of: "Point", in: dto) == 1.0)
    }

    @Test func computedOnlyTypeIsPureBehaviour() {
        // A type whose only member is a computed property is pure behaviour → 0.0, never flagged as data.
        let gate = type("Gate", kind: .struct, module: "App", members: [
            Member(name: "isOpen", kind: .property, accessLevel: .public, isComputed: true)
        ])
        #expect(score(of: "Gate", in: gate) == 0.0)
    }
}
