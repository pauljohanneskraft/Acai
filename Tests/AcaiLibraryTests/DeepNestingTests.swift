import Testing
import AcaiCore
import AcaiLibrary

/// A deeply nested expression used to take the whole process down with `SIGBUS` (#524): parsing
/// recurses once per nesting level, and a cooperative-pool thread's 512 KB stack held about 95
/// levels of Swift and 1,000 of Java or C. The engine parses in-process, so the MCP server went
/// with it.
///
/// Every case runs through `AnalysisService.analyzeProject`, the path the CLI, the app and the MCP
/// server all take, so it covers both halves of the fix: the large-stack parse thread and the
/// iterative Tree-sitter walks. A `@Test` body is already on the cooperative pool, which is the
/// stack that used to overflow — calling a parser on a thread of the test's own choosing would
/// prove nothing.
@Suite("Deeply nested sources")
struct DeepNestingTests {

    /// The depth the issue settles on. Each shape stays on one line so the file is tens of KB
    /// rather than megabytes — `maximumSourceFileBytes` is 2 MB, and a skipped file would pass this
    /// suite without parsing anything.
    static let depth = 5_000

    /// One language's spelling of each nesting shape. Written per language rather than per
    /// language × shape, so a language cannot be given one shape and quietly miss the others.
    struct Dialect: Sendable {
        let name: String
        let fileName: String
        /// Wraps statements in whatever enclosing declaration the language requires.
        let file: @Sendable (String) -> String
        /// Binds a name to `expression`, as one statement.
        let binding: @Sendable (String) -> String
        /// One level of conditional around `inner`, or `nil` where the language's conditional needs
        /// its own line and `depth` levels of indentation would blow the file-size ceiling.
        let conditional: (@Sendable (String) -> String)?
        /// A call whose result is called again, so `root` + `hop` × depth is one long chain.
        let chainRoot: String
        let chainHop: String

        var cases: [Case] {
            let parenthesesCase = Case(dialect: self, shape: "parentheses") { depth in
                binding(String(repeating: "(", count: depth) + "1" + String(repeating: ")", count: depth))
            }
            let chainCase = Case(dialect: self, shape: "call chain") { depth in
                binding(chainRoot + String(repeating: chainHop, count: depth))
            }
            guard let conditional else { return [parenthesesCase, chainCase] }
            let conditionalCase = Case(dialect: self, shape: "conditionals") { depth in
                var nested = binding("1")
                for _ in 0..<depth { nested = conditional(nested) }
                return nested
            }
            return [parenthesesCase, conditionalCase, chainCase]
        }
    }

    struct Case: Sendable, CustomStringConvertible {
        let dialect: Dialect
        let shape: String
        /// The statements at `depth` levels of nesting, before the enclosing declaration is added.
        let nested: @Sendable (Int) -> String

        var description: String { "\(dialect.name), \(shape)" }

        func source(depth: Int) -> String { dialect.file(nested(depth)) }
    }

    static let dialects: [Dialect] = [
        Dialect(
            name: "Swift", fileName: "Deep.swift",
            file: { "struct Deep {\n    func run() {\n\($0)\n    }\n}" },
            binding: { "let value = \($0)" },
            conditional: { "if true { \($0) }" },
            chainRoot: "value", chainHop: ".hop()"
        ),
        Dialect(
            name: "Java", fileName: "Deep.java",
            file: { "class Deep {\n    void run() {\n\($0)\n    }\n}" },
            binding: { "int value = \($0);" },
            conditional: { "if (true) { \($0) }" },
            chainRoot: "value", chainHop: ".hop()"
        ),
        Dialect(
            name: "Kotlin", fileName: "Deep.kt",
            file: { "class Deep {\n    fun run() {\n\($0)\n    }\n}" },
            binding: { "val value = \($0)" },
            conditional: { "if (true) { \($0) }" },
            chainRoot: "value", chainHop: ".hop()"
        ),
        Dialect(
            name: "TypeScript", fileName: "deep.ts",
            file: { "export class Deep {\n    run(): void {\n\($0)\n    }\n}" },
            binding: { "const value = \($0)" },
            conditional: { "if (true) { \($0) }" },
            chainRoot: "value", chainHop: ".hop()"
        ),
        Dialect(
            name: "JavaScript", fileName: "deep.js",
            file: { "class Deep {\n    run() {\n\($0)\n    }\n}" },
            binding: { "const value = \($0)" },
            conditional: { "if (true) { \($0) }" },
            chainRoot: "value", chainHop: ".hop()"
        ),
        Dialect(
            name: "Dart", fileName: "deep.dart",
            file: { "class Deep {\n  void run() {\n\($0)\n  }\n}" },
            binding: { "var value = \($0);" },
            conditional: { "if (true) { \($0) }" },
            chainRoot: "value", chainHop: ".hop()"
        ),
        // Python's `if` needs its own line, and 5,000 levels of indentation is a 12 MB file. The
        // conditional *expression* nests the same way the statement would.
        Dialect(
            name: "Python", fileName: "deep.py",
            file: { "class Deep:\n    def run(self):\n        \($0)\n" },
            binding: { "value = \($0)" },
            conditional: nil,
            chainRoot: "value", chainHop: ".hop()"
        ),
        Dialect(
            name: "C", fileName: "deep.c",
            file: { "struct Deep { int field; };\nvoid run(void) {\n\($0)\n}" },
            binding: { "int value = \($0);" },
            conditional: { "if (1) { \($0) }" },
            chainRoot: "hop()", chainHop: ""
        ),
        Dialect(
            name: "C++", fileName: "deep.cpp",
            file: { "class Deep {\npublic:\n    void run() {\n\($0)\n    }\n};" },
            binding: { "int value = \($0);" },
            conditional: { "if (true) { \($0) }" },
            chainRoot: "value", chainHop: ".hop()"
        )
    ]

    static let cases: [Case] = dialects.flatMap(\.cases)

    /// Completing at all is the assertion: before the fix this killed the test process, which no
    /// `#expect` can observe. The artifact is checked for the enclosing declaration too, so a parse
    /// that bailed out and returned nothing cannot pass as a survivor.
    @Test("a 5,000-deep file analyses instead of crashing", arguments: cases)
    func analysesWithoutOverflowingTheStack(testCase: Case) async throws {
        let source = testCase.source(depth: Self.depth)
        try #require(
            source.utf8.count < 2 * 1024 * 1024,
            Comment(rawValue: "\(testCase): \(source.utf8.count) bytes is over the per-file ceiling")
        )
        try await SourceTreeFixture([testCase.dialect.fileName: source]).analysed { artifact in
            #expect(
                artifact.flattened().contains { $0.name == "Deep" }
                    || !artifact.freestandingFunctions.isEmpty,
                Comment(rawValue: "\(testCase): nothing was extracted")
            )
        }
    }

    /// Lowering SwiftParser's nesting limit was rejected because a partial parse must stay visible.
    /// SwiftParser stops at 256 levels and returns a partial tree, so the file above its limit is
    /// exactly the case that has to carry a diagnostic rather than look like a clean parse. The
    /// Tree-sitter grammars have no such limit and parse the full depth, which is why this is
    /// asserted for Swift alone.
    @Test func aPartialSwiftParseCarriesADiagnostic() async throws {
        let swift = try #require(Self.dialects.first { $0.name == "Swift" })
        let nested = String(repeating: "(", count: Self.depth) + "1" + String(repeating: ")", count: Self.depth)
        let source = swift.file(swift.binding(nested))
        try await SourceTreeFixture([swift.fileName: source]).analysed { artifact in
            #expect(artifact.metadata.parseDiagnostics.contains { $0.kind == .error })
        }
    }

    /// The Swift manifest reader recurses the same way a source file does, and discovery calls it
    /// synchronously, so it needs the large-stack thread too.
    @Test func aDeeplyNestedPackageManifestDoesNotCrash() async throws {
        let nested = String(repeating: "(", count: Self.depth) + "1" + String(repeating: ")", count: Self.depth)
        let fixture = SourceTreeFixture([
            "Package.swift": "// swift-tools-version:6.0\nimport PackageDescription\nlet unused = \(nested)\n",
            "Sources/Deep/Deep.swift": "struct Deep {}"
        ])
        try await fixture.analysed { artifact in
            #expect(artifact.flattened().contains { $0.name == "Deep" })
        }
    }
}
