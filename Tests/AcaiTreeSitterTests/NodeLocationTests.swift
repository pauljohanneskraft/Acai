import Testing
@testable import AcaiTreeSitter

@Suite("Node source locations")
struct NodeLocationTests {

    @Test("an indented declaration reports its code-unit column")
    func indentedDeclarationColumn() throws {
        let source = """
        interface Priced {
            double price();
        }
        """
        let fixture = try #require(JavaFixture(source))
        let method = try #require(fixture.firstNode(ofType: "method_declaration"))
        let location = method.location(in: fixture.context)

        #expect(location.line == 2)
        #expect(location.column == 5)
    }

    @Test("a non-ASCII character before a declaration counts as one code unit")
    func nonASCIIColumn() throws {
        let source = """
        class Café {
            /* café */ double price();
        }
        """
        let fixture = try #require(JavaFixture(source))
        let method = try #require(fixture.firstNode(ofType: "method_declaration"))

        #expect(method.location(in: fixture.context).column == 16)
    }

    @Test("a declaration after an astral character counts its two code units")
    func astralColumn() throws {
        let source = """
        class Shop {
            /* 🛒 */ double price();
        }
        """
        let fixture = try #require(JavaFixture(source))
        let method = try #require(fixture.firstNode(ofType: "method_declaration"))

        #expect(method.location(in: fixture.context).column == 14)
    }

    @Test("the first declaration on a line starts at column 1")
    func unindentedDeclarationColumn() throws {
        let fixture = try #require(JavaFixture("interface Priced {}"))
        let declaration = try #require(fixture.firstNode(ofType: "interface_declaration"))

        #expect(declaration.location(in: fixture.context).column == 1)
    }
}
