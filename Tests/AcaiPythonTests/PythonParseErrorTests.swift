import Testing
@testable import AcaiPython
@testable import AcaiCore

@Suite("Python: Parse Error Tests")
struct PythonParseErrorTests {
    let parser = PythonCodeParser()

    @Test func wellFormedSourceHasNoDiagnostics() {
        let source = """
        class User:
            def __init__(self, name: str):
                self.name = name
        """
        let artifact = parser.parse(source: source, fileName: "user.py")
        #expect(artifact.metadata.hasParseErrors == false)
    }

    @Test func malformedSourceSurfacesDiagnostics() {
        // A class header with no body / dangling colon is a recoverable parse error.
        let source = """
        class Broken(:
            def method(self)
                return
        """
        let artifact = parser.parse(source: source, fileName: "broken.py")
        #expect(artifact.metadata.hasParseErrors == true)
        #expect(!artifact.metadata.parseDiagnostics.isEmpty)
    }
}
