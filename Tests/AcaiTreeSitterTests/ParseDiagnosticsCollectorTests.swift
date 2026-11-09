import AcaiCore
import Testing
@testable import AcaiTreeSitter

@Suite("Parse Diagnostics Collector")
struct ParseDiagnosticsCollectorTests {

    private func diagnostics(in source: String) throws -> [ParseDiagnostic] {
        let fixture = try #require(JavaFixture(source))
        return ParseDiagnosticsCollector(context: fixture.context).diagnostics(in: fixture.root)
    }

    @Test("A token the source omitted is reported as `missing`, naming the token")
    func missingTokensAreNamed() throws {
        let fixture = try #require(JavaFixture("class A {\n    void m() { run() }\n}"))
        #expect(fixture.root.hasError)
        let diagnostics = ParseDiagnosticsCollector(context: fixture.context)
            .diagnostics(in: fixture.root)
        #expect(diagnostics.count == 1)
        let diagnostic = try #require(diagnostics.first)
        #expect(diagnostic.kind == .missing)
        #expect(diagnostic.message == "missing ;")
        #expect(diagnostic.location.line == 2)
        #expect(diagnostic.location.filePath == "Fixture.java")
    }

    @Test("Input the parser could not make sense of is reported as an `error`")
    func errorNodesAreReported() throws {
        let diagnostics = try diagnostics(in: "class A { int x = ")
        #expect(diagnostics.map(\.kind) == [.error])
        #expect(diagnostics.map(\.message) == ["unexpected syntax"])
    }

    @Test("A clean tree yields nothing")
    func cleanTreeYieldsNothing() throws {
        #expect(try diagnostics(in: "class A { void m() { run(); } }").isEmpty)
    }
}
