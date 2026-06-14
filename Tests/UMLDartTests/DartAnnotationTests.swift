import Testing
@testable import UMLCore
@testable import UMLDart

@Suite("Dart: Annotation Tests")
struct DartAnnotationTests {
    let parser = DartCodeParser()

    @Test func typeAndMemberAnnotations() {
        let source = """
        @deprecated
        @Deprecated('use Bar')
        class Foo extends Base {
            @override
            String name = "x";

            @pragma('vm:prefer-inline')
            void doThing() {}
        }
        """
        let artifact = parser.parse(source: source, fileName: "Foo.dart")
        let foo = artifact.types.first { $0.name == "Foo" }
        // Type-level annotations (arguments dropped, leading `@` kept).
        #expect(foo?.annotations == ["@deprecated", "@Deprecated"])

        let name = foo?.members.first { $0.name == "name" }
        #expect(name?.annotations == ["@override"])

        let doThing = foo?.members.first { $0.name == "doThing" }
        #expect(doThing?.annotations == ["@pragma"])
    }

    @Test func unannotatedMembersStayEmpty() {
        let source = """
        class Plain {
            int count = 0;
            void go() {}
        }
        """
        let artifact = parser.parse(source: source, fileName: "Plain.dart")
        let plain = artifact.types.first { $0.name == "Plain" }
        #expect(plain?.annotations.isEmpty == true)
        #expect(plain?.members.allSatisfy { $0.annotations.isEmpty } == true)
    }

    @Test func enumAnnotations() {
        let source = """
        @deprecated
        enum Color {
            red, green, blue;

            @override
            String toString() => 'color';
        }
        """
        let artifact = parser.parse(source: source, fileName: "Color.dart")
        let color = artifact.types.first { $0.name == "Color" }
        #expect(color?.annotations == ["@deprecated"])
        let toString = color?.members.first { $0.name == "toString" }
        #expect(toString?.annotations == ["@override"])
    }
}
