import Testing
@testable import AcaiCFamily
@testable import AcaiCore

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

    @Test func staticFreeFunctionHasFilePrivateAccess() {
        let source = """
        static int helper(int a) {
            return a * 2;
        }

        int publicApi(int a) {
            return helper(a);
        }
        """
        let artifact = parser.parse(source: source, fileName: "linkage.c")
        let helper = artifact.freestandingFunctions.first { $0.name == "helper" }
        #expect(helper?.accessLevel == .filePrivate)
        let publicApi = artifact.freestandingFunctions.first { $0.name == "publicApi" }
        #expect(publicApi?.accessLevel == .public)
    }

    @Test func typedefRestatingItsStructTagYieldsOnlyTheStruct() {
        let source = """
        typedef struct Node Node;
        struct Node { int value; Node *next; };
        """
        let artifact = parser.parse(source: source, fileName: "node.h")
        #expect(artifact.types.map(\.name) == ["Node"])
        #expect(artifact.types.first?.kind == .struct)

        let enriched = artifact.enriched(configuration: parser.configuration)
        let health = HealthCheck(artifact: enriched).report
        #expect(health.diagnostics.isEmpty)
        #expect(health.score == 1)
        // The self-reference resolves; a type is not coupled to itself, so no edge is inferred.
        let resolver = TypeIdentityResolver(types: enriched.types)
        #expect(resolver.resolve("Node") == .resolved(TypeID("Node")))
    }

    @Test func typedefRestatingItsStructTagIsDroppedWhenTheStructComesFirst() {
        let source = """
        struct Node { int value; };
        typedef struct Node Node;
        """
        let artifact = parser.parse(source: source, fileName: "node.h")
        #expect(artifact.types.map(\.name) == ["Node"])
        #expect(artifact.types.first?.kind == .struct)
    }

    @Test func typedefRestatingAnEnumOrUnionTagIsDropped() {
        let source = """
        typedef enum Color Color;
        enum Color { RED, GREEN };
        typedef union Payload Payload;
        union Payload { int i; double d; };
        """
        let artifact = parser.parse(source: source, fileName: "tags.h")
        #expect(artifact.types.map(\.name).sorted() == ["Color", "Payload"])
        #expect(artifact.types.allSatisfy { $0.kind != .typeAlias })
    }

    @Test func typedefUnderADifferentNameStaysAnAlias() {
        let source = """
        struct Node { int value; };
        typedef struct Node Other;
        typedef struct Node *NodeRef;
        """
        let artifact = parser.parse(source: source, fileName: "node.h")
        let aliases = artifact.types.filter { $0.kind == .typeAlias }
        #expect(aliases.map(\.name).sorted() == ["NodeRef", "Other"])
        #expect(aliases.allSatisfy { $0.inheritedTypes.map(\.name) == ["Node"] })
    }

    @Test func typedefOfAPointerToItsOwnTagStaysAnAlias() {
        let source = """
        struct Node { int value; };
        typedef struct Node *Node;
        """
        let artifact = parser.parse(source: source, fileName: "node.h")
        #expect(artifact.types.map(\.kind) == [.struct, .typeAlias])
        let alias = artifact.types.first { $0.kind == .typeAlias }
        #expect(alias?.name == "Node")
        #expect(alias?.inheritedTypes.map(\.name) == ["Node"])
    }
}
