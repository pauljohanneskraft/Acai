import Testing
import Foundation
@testable import AcaiRender
@testable import AcaiCore

@Suite("Per-Type Visibility Tests")
struct PerTypeVisibilityTests {

    private func typeWithEverything(id: String) -> TypeDeclaration {
        TypeDeclaration(
            id: id, name: id, qualifiedName: id, kind: .enum,
            accessLevel: .public,
            members: [
                Member(name: "value", kind: .property, accessLevel: .internal, type: TypeReference(name: "Int")),
                Member(name: "run", kind: .method, accessLevel: .internal)
            ],
            enumCases: [EnumCase(name: "one")]
        )
    }

    @Test func perTypeOverrideHidesOnlyThatType() {
        var config = ClassDiagramConfiguration()
        config.propertyVisibility["Hidden"] = false

        let shown = GeneratedDiagramNode(from: typeWithEverything(id: "Shown"), configuration: config)
        let hidden = GeneratedDiagramNode(from: typeWithEverything(id: "Hidden"), configuration: config)

        #expect(!shown.properties.isEmpty)
        #expect(hidden.properties.isEmpty)
        #expect(!hidden.methods.isEmpty)
        #expect(!hidden.enumCases.isEmpty)
    }

    @Test func perTypeOverrideShowsEvenWhenGlobalDefaultHides() {
        var config = ClassDiagramConfiguration()
        config.showProperties = false
        config.showMethods = false
        config.showEnumCases = false
        config.propertyVisibility["Revealed"] = true
        config.methodVisibility["Revealed"] = true
        config.enumCaseVisibility["Revealed"] = true

        let revealed = GeneratedDiagramNode(from: typeWithEverything(id: "Revealed"), configuration: config)
        let collapsed = GeneratedDiagramNode(from: typeWithEverything(id: "Collapsed"), configuration: config)

        #expect(!revealed.properties.isEmpty)
        #expect(!revealed.methods.isEmpty)
        #expect(!revealed.enumCases.isEmpty)
        #expect(collapsed.properties.isEmpty)
        #expect(collapsed.methods.isEmpty)
        #expect(collapsed.enumCases.isEmpty)
    }

    @Test func bulkToggleHidesEveryIDWhenAllCurrentlyShowMembers() {
        var config = ClassDiagramConfiguration()
        let ids = ["A", "B"]
        #expect(config.showsMembers(forTypeIDs: ids))

        config.setMemberVisibility(!config.showsMembers(forTypeIDs: ids), forTypeIDs: ids)

        #expect(!config.showsMembers(forTypeIDs: ids))
        #expect(config.propertyVisibility["A"] == false)
        #expect(config.propertyVisibility["B"] == false)
        #expect(config.methodVisibility["A"] == false)
        #expect(config.methodVisibility["B"] == false)
    }

    @Test func bulkToggleShowsEveryIDWhenAnySelectedIDIsHidden() {
        var config = ClassDiagramConfiguration()
        config.propertyVisibility["A"] = false
        let ids = ["A", "B"]
        #expect(!config.showsMembers(forTypeIDs: ids))

        config.setMemberVisibility(!config.showsMembers(forTypeIDs: ids), forTypeIDs: ids)

        #expect(config.showsMembers(forTypeIDs: ids))
        #expect(config.propertyVisibility["A"] == true)
        #expect(config.propertyVisibility["B"] == true)
        #expect(config.methodVisibility["A"] == true)
        #expect(config.methodVisibility["B"] == true)
    }

    @Test func configurationRoundTripsPerTypeOverrides() throws {
        var config = ClassDiagramConfiguration()
        config.methodVisibility["A"] = false
        config.propertyVisibility["B"] = true
        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(ClassDiagramConfiguration.self, from: data)
        #expect(decoded.methodVisibility["A"] == false)
        #expect(decoded.propertyVisibility["B"] == true)
    }
}
