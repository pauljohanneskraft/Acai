import Testing
import Foundation
@testable import UMLRender
@testable import UMLCore

@Suite("Per-Type Visibility Tests")
struct PerTypeVisibilityTests {

    private func typeWithEverything(id: String) -> TypeDeclaration {
        TypeDeclaration(
            id: id, name: id, qualifiedName: id, kind: .enum,
            members: [
                Member(name: "value", kind: .property, type: TypeReference(name: "Int")),
                Member(name: "run", kind: .method)
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
        // Methods and enum cases are unaffected by the property override.
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

    @Test func decodesConfigurationMissingPerTypeKeys() throws {
        // JSON saved before the per-type maps existed must still decode, with empty overrides.
        let json = """
        {"showProperties": true, "showMethods": true, "showEnumCases": true,
         "showRelationships": true, "showInheritance": true, "showComposition": true,
         "showDependency": true, "grouping": "product", "showExternalTypes": false,
         "hideGeneratedTypes": true}
        """
        let config = try JSONDecoder().decode(ClassDiagramConfiguration.self, from: Data(json.utf8))
        #expect(config.propertyVisibility.isEmpty)
        #expect(config.methodVisibility.isEmpty)
        #expect(config.enumCaseVisibility.isEmpty)
        #expect(config.showProperties)
        #expect(config.grouping == .product)
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
