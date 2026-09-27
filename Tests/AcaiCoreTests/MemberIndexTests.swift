import Testing
@testable import AcaiCore

@Suite("MemberIndex")
struct MemberIndexTests {

    @Test func unambiguousNamesResolveAndAmbiguousOnesAreReportedApart() {
        var names = UnambiguousTypeNames()
        names.record("Int", for: "count")
        names.record("Helper", for: "make")
        names.record("Helper", for: "make")
        names.record("Int", for: "size")
        names.record("Double", for: "size")

        #expect(names.resolved == ["count": "Int", "make": "Helper"])
        #expect(names.ambiguous == ["size"])
    }

    @Test func indexSeparatesTypedPropertiesFromAllPropertyNames() {
        let index = MemberIndex(members: [
            Member(name: "typed", kind: .property, accessLevel: .public, type: TypeReference(name: "Foo")),
            Member(name: "untyped", kind: .property, accessLevel: .public),
            Member(name: "make", kind: .method, accessLevel: .public, type: TypeReference(name: "Foo")),
            Member(name: "make", kind: .method, accessLevel: .public, type: TypeReference(name: "Bar"))
        ])

        #expect(index.propertyTypes == ["typed": "Foo"])
        #expect(index.propertyNames == ["typed", "untyped"])
        #expect(index.methodReturnTypes.isEmpty)
    }

    @Test func nestedTypeIDsAreQualifiedByTheirStructuralParent() {
        func type(_ name: String, nested: [TypeDeclaration] = []) -> TypeDeclaration {
            TypeDeclaration(
                id: name, name: name, qualifiedName: name, kind: .class, accessLevel: .internal, nestedTypes: nested
            )
        }
        var builder = DeclarationBuilder()
        builder.types = [type("Outer", nested: [type("Inner", nested: [type("Leaf")])])]

        builder.qualifyNestedTypeIDs()

        #expect(builder.types[0].id == "Outer")
        #expect(builder.types[0].nestedTypes[0].qualifiedName == "Outer.Inner")
        #expect(builder.types[0].nestedTypes[0].nestedTypes[0].id == "Outer.Inner.Leaf")
    }
}
