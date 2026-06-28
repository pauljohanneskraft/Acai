import Testing
@testable import UMLCore
@testable import UMLDart

@Suite("Dart: Body Type References")
struct DartBodyReferenceTests {
    @Test func capturesConstructionInMethodBody() {
        let source = """
        class Widget {}
        class Factory {
          void build() { var w = Widget(); }
        }
        """
        let artifact = DartCodeParser().parse(source: source, fileName: "factory.dart")
        let build = artifact.types.first { $0.name == "Factory" }?.members.first { $0.name == "build" }
        #expect(build?.referencedTypeNames.contains("Widget") == true)
    }
}
