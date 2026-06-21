import Testing
@testable import UMLCFamily
@testable import UMLCore

@Suite("C: Type Tests")
struct CTests {
    let parser = CCodeParser()

    @Test func structWithFields() {
        let source = """
        struct Point {
            int x;
            int y;
        };
        """
        let artifact = parser.parse(source: source, fileName: "point.c")
        #expect(artifact.metadata.sourceLanguage == .c)
        #expect(artifact.types.count == 1)
        let point = artifact.types[0]
        #expect(point.name == "Point")
        #expect(point.kind == .struct)
        #expect(point.members.map(\.name).sorted() == ["x", "y"])
    }

    @Test func enumWithCases() {
        let source = """
        enum Color {
            RED,
            GREEN,
            BLUE
        };
        """
        let artifact = parser.parse(source: source, fileName: "color.c")
        #expect(artifact.types.count == 1)
        let color = artifact.types[0]
        #expect(color.kind == .enum)
        #expect(color.enumCases.map(\.name) == ["RED", "GREEN", "BLUE"])
    }

    @Test func typedefAnonymousStruct() {
        let source = """
        typedef struct {
            double width;
            double height;
        } Size;
        """
        let artifact = parser.parse(source: source, fileName: "size.c")
        #expect(artifact.types.count == 1)
        let size = artifact.types[0]
        #expect(size.name == "Size")
        #expect(size.kind == .struct)
        #expect(size.members.count == 2)
    }

    @Test func typedefAlias() {
        let source = """
        typedef unsigned int Handle;
        """
        let artifact = parser.parse(source: source, fileName: "handle.c")
        #expect(artifact.types.count == 1)
        #expect(artifact.types[0].name == "Handle")
        #expect(artifact.types[0].kind == .typeAlias)
    }

    @Test func freeFunctionAndStructPointerField() {
        let source = """
        struct Node {
            int value;
            struct Node *next;
        };

        int compute(int a, int b) {
            return a + b;
        }
        """
        let artifact = parser.parse(source: source, fileName: "node.c")
        let node = artifact.types.first { $0.name == "Node" }
        #expect(node != nil)
        #expect(node?.members.contains { $0.name == "next" } == true)
        #expect(artifact.freestandingFunctions.contains { $0.name == "compute" } == true)
    }
}
