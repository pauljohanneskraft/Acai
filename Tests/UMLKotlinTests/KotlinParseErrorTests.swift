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

    @Test func malformedSourceReportsConcreteDiagnostics() {
        let artifact = parser.parse(source: "class Broken { fun (", fileName: "Bad.kt")
        let diagnostics = artifact.metadata.parseDiagnostics
        #expect(!diagnostics.isEmpty)
        // Tree-sitter gives a location and a kind (error/missing) for each problem.
        #expect(diagnostics.allSatisfy { $0.location.filePath == "Bad.kt" })
        #expect(diagnostics.allSatisfy { $0.location.line >= 1 && $0.location.column >= 1 })
        #expect(diagnostics.allSatisfy { [.error, .missing].contains($0.kind) })
    }
}
