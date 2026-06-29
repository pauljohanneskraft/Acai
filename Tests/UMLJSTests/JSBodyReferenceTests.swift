import Testing
@testable import UMLCore
@testable import UMLJS

@Suite("JS/TS: Body Type References")
struct JSBodyReferenceTests {
    @Test func capturesConstructionInMethodBody() {
        let source = """
        class Widget {}
        class Factory {
            build() { const w = new Widget(); return w; }
        }
        """
        let artifact = JSCodeParser(isTypeScript: true).parse(source: source, fileName: "Factory.ts")
        let build = artifact.types.first { $0.name == "Factory" }?.members.first { $0.name == "build" }
        #expect(build?.referencedTypeNames.contains("Widget") == true)
    }
}
