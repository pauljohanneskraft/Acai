import Testing
@testable import UMLKotlin
@testable import UMLCore

@Suite("Kotlin: Parse Error Surfacing")
struct KotlinParseErrorTests {
    let parser = KotlinCodeParser()

    @Test func validSourceHasNoParseErrors() {
        let source = """
        class Account(val id: String) {
            var balance: Double = 0.0

            fun deposit(amount: Double) {
                balance = balance + amount
            }
        }
        """
        let artifact = parser.parse(source: source, fileName: "Account.kt")
        #expect(artifact.metadata.hasParseErrors == false)
    }

    @Test func malformedSourceFlagsParseErrors() {
        let artifact = parser.parse(source: "class Broken { fun (", fileName: "Bad.kt")
        #expect(artifact.metadata.hasParseErrors == true)
    }
}
