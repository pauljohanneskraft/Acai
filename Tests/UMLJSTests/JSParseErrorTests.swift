import Testing
@testable import UMLJS
@testable import UMLCore

@Suite("JS/TS: Parse Error Surfacing")
struct JSParseErrorTests {
    let parser = JSCodeParser(isTypeScript: true)

    @Test func validSourceHasNoParseErrors() {
        let artifact = parser.parse(source: "class Ok { value: number = 0; }", fileName: "Ok.ts")
        #expect(artifact.metadata.hasParseErrors == false)
    }

    @Test func malformedSourceFlagsParseErrors() {
        let artifact = parser.parse(source: "class Broken { method( {", fileName: "Bad.ts")
        #expect(artifact.metadata.hasParseErrors == true)
    }
}
