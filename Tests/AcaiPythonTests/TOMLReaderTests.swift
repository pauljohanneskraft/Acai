import Testing
@testable import AcaiPython

@Suite("Python: TOML reader")
struct TOMLReaderTests {

    private func parse(_ source: String) throws -> TOMLValue {
        try TOMLReader(source).parse()
    }

    // MARK: - The grammar it accepts

    @Test func readsTablesDottedKeysAndStrings() throws {
        let document = try parse("""
        [tool.setuptools]
        package-dir = {"" = "lib"}

        [tool.poetry]
        name = 'demo'
        """)
        #expect(document.value(at: ["tool", "setuptools", "package-dir", ""])?.stringValue == "lib")
        #expect(document.value(at: ["tool", "poetry", "name"])?.stringValue == "demo")
    }

    @Test func readsDottedKeysOutsideATableHeader() throws {
        let document = try parse(#"tool.hatch.build.targets.wheel.packages = ["src/pkg"]"#)
        #expect(document.value(at: ["tool", "hatch", "build", "targets", "wheel", "packages"])
            == .array([.string("src/pkg")]))
    }

    @Test func readsMultiLineArraysWithCommentsAndTrailingCommas() throws {
        let document = try parse("""
        [tool.setuptools.packages.find]
        where = [
            "python",  # the real root
            "extra",
        ]
        """)
        #expect(document.value(at: ["tool", "setuptools", "packages", "find", "where"])
            == .array([.string("python"), .string("extra")]))
    }

    @Test func readsArraysOfInlineTables() throws {
        let document = try parse("""
        [tool.poetry]
        packages = [{include = "mypkg", from = "libs"}, {include = "other"}]
        """)
        let packages = try #require(document.value(at: ["tool", "poetry", "packages"])?.arrayValue)
        #expect(packages.count == 2)
        #expect(packages[0].tableValue?["from"]?.stringValue == "libs")
        #expect(packages[1].tableValue?["include"]?.stringValue == "other")
    }

    /// `[[tool.poetry.packages]]` is the same declaration spelled as an array of tables.
    @Test func readsArrayOfTablesHeaders() throws {
        let document = try parse("""
        [[tool.poetry.packages]]
        include = "mypkg"
        from = "libs"

        [[tool.poetry.packages]]
        include = "other"
        """)
        let packages = try #require(document.value(at: ["tool", "poetry", "packages"])?.arrayValue)
        #expect(packages.count == 2)
        #expect(packages[0].tableValue?["from"]?.stringValue == "libs")
        #expect(packages[1].tableValue?["include"]?.stringValue == "other")
    }

    @Test func readsLiteralAndMultiLineStrings() throws {
        let document = try parse("""
        literal = 'C:\\path'
        block = \"\"\"
        line one
        \"\"\"
        """)
        #expect(document.value(at: ["literal"])?.stringValue == #"C:\path"#)
        #expect(document.value(at: ["block"])?.stringValue == "line one\n")
    }

    /// Numbers, booleans and dates are kept verbatim so a valid manifest is never rejected over a
    /// value nothing reads.
    @Test func keepsUninterpretedScalarsVerbatim() throws {
        let document = try parse("""
        [project]
        version = 1.2
        released = 2026-09-20
        strict = true
        """)
        #expect(document.value(at: ["project", "version"]) == .scalar("1.2"))
        #expect(document.value(at: ["project", "released"]) == .scalar("2026-09-20"))
        #expect(document.value(at: ["project", "strict"]) == .scalar("true"))
    }

    @Test func ignoresCommentsAndBlankLines() throws {
        let document = try parse("""
        # leading comment

        [project]  # trailing comment
        name = "demo"  # another
        """)
        #expect(document.value(at: ["project", "name"])?.stringValue == "demo")
    }

    @Test func readsAnEmptyDocument() throws {
        #expect(try parse("") == .table([:]))
        #expect(try parse("# nothing but a comment\n") == .table([:]))
    }

    // MARK: - The shapes it rejects

    @Test(arguments: [
        ("name = \"unterminated", "unterminated string"),
        ("name = 'unterminated", "unterminated string"),
        ("[project", "expected ']'"),
        ("name", "expected '='"),
        ("name =", "expected a value"),
        ("where = [\"a\"", "expected ',' or ']' in an array"),
        ("dir = {\"\" = \"lib\"", "expected ',' or '}' in an inline table"),
        ("= \"value\"", "expected a key"),
    ])
    func rejectsMalformedInput(source: String, message: String) throws {
        do {
            _ = try parse(source)
            Issue.record("expected \(source) to be rejected")
        } catch let error as TOMLParseError {
            #expect(error.message.contains(message))
        }
    }

    @Test func reportsTheLineAndColumnOfTheFailure() throws {
        do {
            _ = try parse("""
            [project]
            name = "demo"
            broken = "unterminated
            """)
            Issue.record("expected the manifest to be rejected")
        } catch let error as TOMLParseError {
            #expect(error.line == 3)
        }
    }
}
