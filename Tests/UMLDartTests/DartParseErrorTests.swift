import Testing
@testable import UMLDart
@testable import UMLCore

@Suite("Dart: Parse Error Surfacing")
struct DartParseErrorTests {
    let parser = DartCodeParser()

    @Test func validSourceHasNoParseErrors() {
        let artifact = parser.parse(source: "class Ok { int value = 0; }", fileName: "Ok.dart")
        #expect(artifact.metadata.hasParseErrors == false)
    }

    @Test func malformedSourceFlagsParseErrors() {
        let artifact = parser.parse(source: "class Broken { void m( {", fileName: "Bad.dart")
        #expect(artifact.metadata.hasParseErrors == true)
    }
}
