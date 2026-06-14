import Testing
@testable import UMLJava
@testable import UMLCore

@Suite("Java: Parse Error Surfacing")
struct JavaParseErrorTests {
    let parser = JavaCodeParser()

    @Test func validSourceHasNoParseErrors() {
        let artifact = parser.parse(source: "class Ok { int value; }", fileName: "Ok.java")
        #expect(artifact.metadata.hasParseErrors == false)
    }

    @Test func malformedSourceFlagsParseErrors() {
        let artifact = parser.parse(source: "class Broken { void m( {", fileName: "Bad.java")
        #expect(artifact.metadata.hasParseErrors == true)
    }
}
