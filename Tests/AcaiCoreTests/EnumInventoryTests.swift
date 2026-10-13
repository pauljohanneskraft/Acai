import Testing
import Foundation
@testable import AcaiCore

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

    @Test func entriesAndCasesCarryDocumentationAndNothingWhereThereIsNone() throws {
        let documented = TypeDeclaration(
            id: "Suit", name: "Suit", qualifiedName: "Suit", kind: .enum, accessLevel: .public,
            enumCases: [
                EnumCase(name: "hearts", documentation: "The red one."),
                EnumCase(name: "spades")
            ],
            documentation: "A playing card's suit.")
        let bare = enumType("Bare", cases: [EnumCase(name: "only")])

        let entries = EnumInventory(artifact: artifact([documented, bare])).entries

        let suit = try #require(entries.first { $0.type == "Suit" })
        #expect(suit.documentation == "A playing card's suit.")
        #expect(suit.cases.first { $0.name == "hearts" }?.documentation == "The red one.")
        #expect(suit.cases.first { $0.name == "spades" }?.documentation == nil)
        #expect(entries.first { $0.type == "Bare" }?.documentation == nil)
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

        #expect(entries.map(\.type) == ["Payload", "Suit"])
        let hearts = entries[1].cases[0]
        #expect(hearts.name == "hearts")
        #expect(hearts.rawValue == "H")
        let number = entries[0].cases[0]
        #expect(number.associatedValues == ["count: Int"])
        #expect(entries[0].location?.filePath == "Payload.swift")
    }
}
