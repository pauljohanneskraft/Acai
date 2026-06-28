import Testing
@testable import UMLCFamily
@testable import UMLCore

@Suite("C/C++: Body Type References")
struct CFamilyBodyReferenceTests {
    @Test func cppCapturesConstructionInMethodBody() {
        let source = """
        class Widget {};
        class Factory {
        public:
            void build() { Widget w; (void)w; }
        };
        """
        let artifact = CppCodeParser().parse(source: source, fileName: "Factory.cpp")
        let build = artifact.types.first { $0.name == "Factory" }?.members.first { $0.name == "build" }
        #expect(build?.referencedTypeNames.contains("Widget") == true)
    }
}
