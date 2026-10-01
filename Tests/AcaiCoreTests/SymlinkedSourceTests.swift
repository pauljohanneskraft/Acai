import Foundation
import Testing
import AcaiCore

/// A repository that symlinks a source directory into place — a JavaScript workspace, a
/// Bazel-style layout, a monorepo sharing a package — used to lose that directory with no warning
/// and no diagnostic: just fewer types than the codebase has. Links are followed now, so the
/// central assertion here is that linking a directory in and copying it in place produce the same
/// artifact.
private struct LinkFixtureParser: CodeParser {
    var language: CodeArtifact.SourceLanguage { .init(rawValue: "linkFixture") }
    var fileExtensions: [String] { ["lx"] }
    var configuration: LanguageConfiguration { LanguageConfiguration() }

    func parse(source: String, fileName: String) -> CodeArtifact {
        let name = (fileName as NSString).lastPathComponent.replacingOccurrences(of: ".lx", with: "")
        let type = TypeDeclaration(
            id: name, name: name, qualifiedName: name, kind: .class, accessLevel: .public,
            location: .init(filePath: fileName, line: 1, column: 1)
        )
        return CodeArtifact(metadata: .init(sourceLanguage: language, filePaths: [fileName]), types: [type])
    }
}

@Suite("Symlinked sources", .timeLimit(.minutes(1)))
struct SymlinkedSourceTests {

    private let manager = FileManager.default

    private func makeContainer() throws -> URL {
        let url = manager.temporaryDirectory
            .appendingPathComponent("AcaiSymlinkTests-\(UUID().uuidString)", isDirectory: true)
        try manager.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func writeTree(at root: URL) throws {
        try manager.createDirectory(
            at: root.appendingPathComponent("Nested"), withIntermediateDirectories: true)
        try "Alpha".write(to: root.appendingPathComponent("Alpha.lx"), atomically: true, encoding: .utf8)
        try "Beta".write(
            to: root.appendingPathComponent("Nested/Beta.lx"), atomically: true, encoding: .utf8)
    }

    private func analyze(_ root: URL) async throws -> CodeArtifact {
        try await AnalysisService(parsers: [LinkFixtureParser()])
            .analyzeProject(at: root, allowedLanguages: [])
    }

    @Test("a symlinked source directory yields the same artifact as the same directory copied in place")
    func linkedDirectoryMatchesCopy() async throws {
        let container = try makeContainer()
        defer { try? manager.removeItem(at: container) }

        let shared = container.appendingPathComponent("shared/Sources", isDirectory: true)
        try manager.createDirectory(at: shared, withIntermediateDirectories: true)
        try writeTree(at: shared)

        let copied = container.appendingPathComponent("copied", isDirectory: true)
        try manager.createDirectory(at: copied, withIntermediateDirectories: true)
        try manager.copyItem(at: shared, to: copied.appendingPathComponent("Sources"))

        let linked = container.appendingPathComponent("linked", isDirectory: true)
        try manager.createDirectory(at: linked, withIntermediateDirectories: true)
        try manager.createSymbolicLink(
            at: linked.appendingPathComponent("Sources"), withDestinationURL: shared)

        let fromCopy = try await analyze(copied)
        let fromLink = try await analyze(linked)

        #expect(fromCopy.types.map(\.name) == ["Alpha", "Beta"])
        #expect(fromLink.types.map(\.name) == fromCopy.types.map(\.name))
        #expect(fromLink.metadata.filePaths == fromCopy.metadata.filePaths)
        #expect(fromLink.types.map(\.location?.filePath) == fromCopy.types.map(\.location?.filePath))
    }

    @Test("a symlinked file is followed")
    func linkedFileIsFollowed() async throws {
        let container = try makeContainer()
        defer { try? manager.removeItem(at: container) }
        let root = container.appendingPathComponent("root", isDirectory: true)
        try manager.createDirectory(at: root, withIntermediateDirectories: true)
        try "Gamma".write(
            to: container.appendingPathComponent("Gamma.lx"), atomically: true, encoding: .utf8)
        try manager.createSymbolicLink(
            at: root.appendingPathComponent("Gamma.lx"),
            withDestinationURL: container.appendingPathComponent("Gamma.lx"))

        #expect(try await analyze(root).types.map(\.name) == ["Gamma"])
    }

    @Test("a link pointing at an ancestor terminates instead of looping")
    func selfReferentialLinkTerminates() async throws {
        let container = try makeContainer()
        defer { try? manager.removeItem(at: container) }
        let root = container.appendingPathComponent("root", isDirectory: true)
        try manager.createDirectory(at: root, withIntermediateDirectories: true)
        try "Delta".write(to: root.appendingPathComponent("Delta.lx"), atomically: true, encoding: .utf8)
        try manager.createSymbolicLink(
            at: root.appendingPathComponent("loop"), withDestinationURL: root)

        #expect(try await analyze(root).types.map(\.name) == ["Delta"])
    }

    @Test("a link aliasing a directory the walk already covered contributes its files once")
    func aliasedDirectoryIsNotDoubleCounted() async throws {
        let container = try makeContainer()
        defer { try? manager.removeItem(at: container) }
        let root = container.appendingPathComponent("root", isDirectory: true)
        let real = root.appendingPathComponent("Real", isDirectory: true)
        try manager.createDirectory(at: real, withIntermediateDirectories: true)
        try "Epsilon".write(to: real.appendingPathComponent("Epsilon.lx"), atomically: true, encoding: .utf8)
        try manager.createSymbolicLink(at: root.appendingPathComponent("alias"), withDestinationURL: real)

        let artifact = try await analyze(root)
        #expect(artifact.types.map(\.name) == ["Epsilon"])
        #expect(artifact.metadata.filePaths == ["Real/Epsilon.lx"])
    }

    @Test("a dangling link is left out of the artifact, and reported rather than silently dropped")
    func danglingLinkIsReported() async throws {
        let container = try makeContainer()
        defer { try? manager.removeItem(at: container) }
        let root = container.appendingPathComponent("root", isDirectory: true)
        try manager.createDirectory(at: root, withIntermediateDirectories: true)
        try "Zeta".write(to: root.appendingPathComponent("Zeta.lx"), atomically: true, encoding: .utf8)
        try manager.createSymbolicLink(
            at: root.appendingPathComponent("Missing.lx"),
            withDestinationURL: container.appendingPathComponent("nowhere.lx"))

        let artifact = try await analyze(root)
        #expect(artifact.types.map(\.name) == ["Zeta"])
        let skipped = artifact.metadata.parseDiagnostics.filter { $0.kind == .skipped }
        #expect(skipped.map(\.location.filePath) == ["Missing.lx"])
    }

    @Test("two links to the same file contribute it once, not twice")
    func aliasedFileIsNotDoubleCounted() async throws {
        let container = try makeContainer()
        defer { try? manager.removeItem(at: container) }
        let root = container.appendingPathComponent("root", isDirectory: true)
        try manager.createDirectory(at: root, withIntermediateDirectories: true)
        let target = container.appendingPathComponent("Eta.lx")
        try "Eta".write(to: target, atomically: true, encoding: .utf8)
        try manager.createSymbolicLink(at: root.appendingPathComponent("First.lx"), withDestinationURL: target)
        try manager.createSymbolicLink(at: root.appendingPathComponent("Second.lx"), withDestinationURL: target)

        let artifact = try await analyze(root)
        #expect(artifact.types.map(\.name) == ["First"])
        #expect(artifact.metadata.filePaths == ["First.lx"])
    }
}
