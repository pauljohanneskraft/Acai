import Testing
import Foundation
@testable import AcaiCore

/// Covers `EnumInventory`: enum-like types are collected with their cases, raw values and
/// associated-value shapes; non-enum types are skipped; output is sorted.
@Suite("Core: EnumInventory")
struct EnumInventoryTests {

    private func artifact(_ types: [TypeDeclaration]) -> CodeArtifact {
        CodeArtifact(metadata: .init(sourceLanguage: .swift), types: types)
    }

    private func enumType(_ name: String, cases: [EnumCase]) -> TypeDeclaration {
        TypeDeclaration(
            id: name, name: name, qualifiedName: name, kind: .enum, accessLevel: .public,
            enumCases: cases,
            location: SourceLocation(filePath: "\(name).swift", line: 1, column: 1))
    }

    @Test func collectsCasesRawAndAssociatedValues() {
        let suit = enumType("Suit", cases: [
            EnumCase(name: "hearts", rawValue: "H", associatedValues: []),
            EnumCase(name: "spades", rawValue: "S", associatedValues: [])
        ])
        let payload = enumType("Payload", cases: [
            EnumCase(name: "number", rawValue: nil, associatedValues: [
                Parameter(internalName: "count", type: TypeReference(name: "Int"))
            ])
        ])
        let plain = TypeDeclaration(
            id: "Service", name: "Service", qualifiedName: "Service", kind: .class, accessLevel: .public)

        let entries = EnumInventory(artifact: artifact([payload, suit, plain])).entries

        // Only the two enums, sorted by qualified name.
        #expect(entries.map(\.type) == ["Payload", "Suit"])
        let hearts = entries[1].cases[0]
        #expect(hearts.name == "hearts")
        #expect(hearts.rawValue == "H")
        let number = entries[0].cases[0]
        #expect(number.associatedValues == ["count: Int"])
        #expect(entries[0].location?.filePath == "Payload.swift")
    }
}
