import Foundation
import Testing
import AcaiCore

/// `.gitignore` was invisible to discovery: the only exclusion mechanism was the fixed
/// build-output directory list, so anything a repository ignores for its own reasons was analyzed
/// anyway. The rules now reach the engine through the same `includingFile` seam a caller's own
/// filter uses, which is what keeps `AcaiCore` from learning anything about any language.
private struct IgnoreFixtureParser: CodeParser {
    var language: CodeArtifact.SourceLanguage { .init(rawValue: "ignoreFixture") }
    var fileExtensions: [String] { ["gx"] }
    var configuration: LanguageConfiguration { LanguageConfiguration() }

    func parse(source: String, fileName: String) -> CodeArtifact {
        let name = (fileName as NSString).lastPathComponent.replacingOccurrences(of: ".gx", with: "")
        let type = TypeDeclaration(
            id: fileName, name: name, qualifiedName: fileName, kind: .class, accessLevel: .public,
            location: .init(filePath: fileName, line: 1, column: 1)
        )
        return CodeArtifact(metadata: .init(sourceLanguage: language, filePaths: [fileName]), types: [type])
    }
}

@Suite("Gitignore filtering", .timeLimit(.minutes(1)))
struct GitignoreFilterTests {

    private let manager = FileManager.default

    private func makeRoot(_ files: [String: String]) throws -> URL {
        let root = manager.temporaryDirectory
            .appendingPathComponent("AcaiGitignoreTests-\(UUID().uuidString)", isDirectory: true)
        for (path, contents) in files.sorted(by: { $0.key < $1.key }) {
            let url = root.appendingPathComponent(path)
            try manager.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try contents.write(to: url, atomically: true, encoding: .utf8)
        }
        return root
    }

    private func filter(_ files: [String: String]) throws -> (GitignoreFilter, URL) {
        let root = try makeRoot(files)
        return (GitignoreFilter(root: root), root)
    }

    @Test("a directory rule excludes everything beneath it")
    func directoryRule() throws {
        let (filter, root) = try filter([".gitignore": "build/\n", "build/Gen.gx": "", "src/Keep.gx": ""])
        defer { try? manager.removeItem(at: root) }
        #expect(filter.includes("build/Gen.gx") == false)
        #expect(filter.includes("src/Keep.gx"))
    }

    @Test("an unanchored rule matches at every depth")
    func unanchoredRuleMatchesAtDepth() throws {
        let (filter, root) = try filter([".gitignore": "*.log\n", "a/b/debug.log": "", "a/b/Keep.gx": ""])
        defer { try? manager.removeItem(at: root) }
        #expect(filter.includes("a/b/debug.log") == false)
        #expect(filter.includes("a/b/Keep.gx"))
    }

    @Test("a later rule in the same file overrides an earlier one")
    func lastRuleWins() throws {
        let (filter, root) = try filter([".gitignore": "*.gx\n!Keep.gx\n", "Keep.gx": "", "Drop.gx": ""])
        defer { try? manager.removeItem(at: root) }
        #expect(filter.includes("Keep.gx"))
        #expect(filter.includes("Drop.gx") == false)
    }

    @Test("a nested .gitignore overrides the root's rules for its own subtree")
    func nestedFileWins() throws {
        let (filter, root) = try filter([
            ".gitignore": "*.gx\n", "pkg/.gitignore": "!*.gx\n", "pkg/Kept.gx": "", "Dropped.gx": ""
        ])
        defer { try? manager.removeItem(at: root) }
        #expect(filter.includes("pkg/Kept.gx"))
        #expect(filter.includes("Dropped.gx") == false)
    }

    @Test("a negation cannot re-include a file inside an ignored directory")
    func negationCannotEscapeAnIgnoredDirectory() throws {
        let (filter, root) = try filter([
            ".gitignore": "vendor/\n!vendor/Keep.gx\n", "vendor/Keep.gx": ""
        ])
        defer { try? manager.removeItem(at: root) }
        #expect(filter.includes("vendor/Keep.gx") == false)
    }

    @Test("a rooted rule applies only at the file's own directory")
    func rootedRule() throws {
        let (filter, root) = try filter([".gitignore": "/Top.gx\n", "Top.gx": "", "nested/Top.gx": ""])
        defer { try? manager.removeItem(at: root) }
        #expect(filter.includes("Top.gx") == false)
        #expect(filter.includes("nested/Top.gx"))
    }

    @Test("a tree with no .gitignore includes everything")
    func noRulesIncludesEverything() throws {
        let (filter, root) = try filter(["src/Keep.gx": ""])
        defer { try? manager.removeItem(at: root) }
        #expect(filter.includes("src/Keep.gx"))
        #expect(filter.diagnostics.isEmpty)
    }

    @Test("a rule that cannot be read is reported against its own line")
    func malformedRuleIsReported() throws {
        let (filter, root) = try filter([".gitignore": "# fine\nok.gx\na//b\n"])
        defer { try? manager.removeItem(at: root) }
        let problems = filter.diagnostics
        #expect(problems.count == 1)
        #expect(problems.first?.kind == .invalidPattern)
        #expect(problems.first?.location.filePath == ".gitignore")
        #expect(problems.first?.location.line == 3)
        // The rules around it still apply — one bad line does not discard the file.
        #expect(filter.includes("ok.gx") == false)
    }

    @Test("an ignored file is never parsed, and the rules' problems reach the artifact")
    func analysisRespectsGitignore() async throws {
        let root = try makeRoot([
            ".gitignore": "Generated/\n*.gen.gx\na[b\n",
            "Generated/Machine.gx": "",
            "src/Hand.gx": "",
            "src/Machine.gen.gx": ""
        ])
        defer { try? manager.removeItem(at: root) }

        let artifact = try await AnalysisService(parsers: [IgnoreFixtureParser()])
            .analyzeProject(at: root, allowedLanguages: [])

        #expect(artifact.metadata.filePaths == ["src/Hand.gx"])
        #expect(artifact.metadata.parseDiagnostics.map(\.kind) == [.invalidPattern])
    }

    @Test("respectingGitignore: false analyzes the tree exactly as it sits on disk")
    func gitignoreCanBeTurnedOff() async throws {
        let root = try makeRoot([".gitignore": "Generated/\n", "Generated/Machine.gx": "", "Hand.gx": ""])
        defer { try? manager.removeItem(at: root) }

        let artifact = try await AnalysisService(parsers: [IgnoreFixtureParser()])
            .analyzeProject(at: root, allowedLanguages: [], respectingGitignore: false)

        #expect(artifact.metadata.filePaths.sorted() == ["Generated/Machine.gx", "Hand.gx"])
    }

    @Test("the caller's own filter still applies alongside the repository's rules")
    func callerFilterComposesWithGitignore() async throws {
        let root = try makeRoot([".gitignore": "Ignored.gx\n", "Ignored.gx": "", "Kept.gx": "", "Blocked.gx": ""])
        defer { try? manager.removeItem(at: root) }

        let artifact = try await AnalysisService(parsers: [IgnoreFixtureParser()])
            .analyzeProject(at: root, allowedLanguages: []) { $0 != "Blocked.gx" }

        #expect(artifact.metadata.filePaths == ["Kept.gx"])
    }
}
