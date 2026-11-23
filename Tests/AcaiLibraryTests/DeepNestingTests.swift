import Testing
import AcaiCore
import AcaiLibrary

/// Runs on the cooperative pool through `analyzeProject`, the 512 KB stack a deep parse overflows.
@Suite("Deeply nested sources")
struct DeepNestingTests {

    /// Each shape stays on one line, since a file over `maximumSourceFileBytes` is skipped unparsed.
    static let depth = 5_000

    struct Dialect: Sendable {
        let name: String
        let fileName: String
        let file: @Sendable (String) -> String
        let binding: @Sendable (String) -> String
        /// `nil` where the conditional needs its own line and `depth` indents would exceed the size cap.
        let conditional: (@Sendable (String) -> String)?
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

    /// A crash here takes the test process down; the declaration check rules out an empty parse.
    @Test("a 5,000-deep file analyses instead of crashing", arguments: cases)
    func analysesWithoutOverflowingTheStack(testCase: Case) async throws {
        try await expectAnalyses(testCase, with: .standard)
    }

    /// Swift alone, as the only language whose deep parse outgrows a pool thread.
    @Test("a 5,000-deep file analyses through shared parses", arguments: cases.filter { $0.dialect.name == "Swift" })
    func analysesThroughSharedParses(testCase: Case) async throws {
        try await expectAnalyses(testCase, with: AnalysisService.standard.sharing(SharedParses()))
    }

    private func expectAnalyses(_ testCase: Case, with service: AnalysisService) async throws {
        let source = testCase.source(depth: Self.depth)
        try #require(
            source.utf8.count < 2 * 1024 * 1024,
            Comment(rawValue: "\(testCase): \(source.utf8.count) bytes is over the per-file ceiling")
        )
        try await SourceTreeFixture([testCase.dialect.fileName: source]).analysed(with: service) { artifact in
            #expect(
                artifact.flattened().contains { $0.name == "Deep" }
                    || !artifact.freestandingFunctions.isEmpty,
                Comment(rawValue: "\(testCase): nothing was extracted")
            )
        }
    }

    /// SwiftParser stops at its nesting limit; Tree-sitter grammars parse the full depth.
    @Test func aPartialSwiftParseCarriesADiagnostic() async throws {
        let swift = try #require(Self.dialects.first { $0.name == "Swift" })
        let nested = String(repeating: "(", count: Self.depth) + "1" + String(repeating: ")", count: Self.depth)
        let source = swift.file(swift.binding(nested))
        try await SourceTreeFixture([swift.fileName: source]).analysed { artifact in
            #expect(artifact.metadata.parseDiagnostics.contains { $0.kind == .error })
        }
    }

    @Test func aDeeplyNestedPackageManifestDoesNotCrash() async throws {
        let chain = "value" + String(repeating: ".hop()", count: Self.depth)
        let fixture = SourceTreeFixture([
            "Package.swift": "// swift-tools-version:6.0\nimport PackageDescription\nlet unused = \(chain)\n",
            "Sources/Deep/Deep.swift": "struct Deep {}"
        ])
        try await fixture.analysed { artifact in
            #expect(artifact.flattened().contains { $0.name == "Deep" })
        }
    }
}
