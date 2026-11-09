import Testing
@testable import AcaiTreeSitter

@Suite("Type Name Prepass")
struct TypeNamePrepassTests {

    private let prepass = TypeNamePrepass(
        declarationNodeTypes: ["class_declaration", "interface_declaration", "enum_declaration"])

    @Test("Every declared type's simple name is collected, nested and later declarations included")
    func everyDeclaredNameIsCollected() throws {
        let fixture = try #require(JavaFixture("""
        class Service {
            class Inner {}
            void run() {}
        }
        interface Marker {}
        enum Kind { A, B }
        """))
        let names = prepass.names(in: fixture.root) { node in
            node.child(byFieldName: "name")?.text(in: fixture.context)
        }
        #expect(names == ["Service", "Inner", "Marker", "Kind"])
    }

    @Test("A declaration whose name cannot be read is skipped rather than recorded blank")
    func unreadableNamesAreSkipped() throws {
        let fixture = try #require(JavaFixture("class Service {} interface Marker {}"))
        let names = prepass.names(in: fixture.root) { node in
            guard node.nodeType == "class_declaration" else { return nil }
            return node.child(byFieldName: "name")?.text(in: fixture.context)
        }
        #expect(names == ["Service"])
    }

    @Test("Node types outside the declaration table contribute nothing")
    func unlistedDeclarationTypesAreIgnored() throws {
        let fixture = try #require(JavaFixture("interface Marker {} enum Kind { A }"))
        let names = TypeNamePrepass(declarationNodeTypes: ["class_declaration"])
            .names(in: fixture.root) { node in
                node.child(byFieldName: "name")?.text(in: fixture.context)
            }
        #expect(names.isEmpty)
    }
}
