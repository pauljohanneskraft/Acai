import Testing
@testable import AcaiSwift
@testable import AcaiCore

@Suite("Swift: Parse Error Surfacing")
struct SwiftParseErrorTests {
    let parser = SwiftCodeParser()

    @Test func validSourceHasNoParseErrors() {
        let artifact = parser.parse(source: "struct Ok { let value = 0 }", fileName: "Ok.swift")
        #expect(artifact.metadata.hasParseErrors == false)
        #expect(artifact.metadata.parseDiagnostics.isEmpty)
    }

    @Test func malformedSourceReportsConcreteDiagnostics() {
        let artifact = parser.parse(source: "struct Broken { func m( {", fileName: "Bad.swift")
        #expect(artifact.metadata.hasParseErrors == true)
        let diagnostics = artifact.metadata.parseDiagnostics
        #expect(!diagnostics.isEmpty)
        // SwiftSyntax gives a real location and a human-readable message.
        #expect(diagnostics.allSatisfy { $0.location.filePath == "Bad.swift" })
        #expect(diagnostics.allSatisfy { $0.location.line >= 1 })
        #expect(diagnostics.allSatisfy { !$0.message.isEmpty })
    }
}
