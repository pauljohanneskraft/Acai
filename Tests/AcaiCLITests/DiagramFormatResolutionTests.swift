import AcaiDiagram
import Foundation
import Testing
@testable import AcaiCLI

@Suite("Diagram Format Resolution")
struct DiagramFormatResolutionTests {

    private static let shapes: [[String]] = [
        [],
        ["--sequence-from", "Service.run"],
        ["--state-from", "Service.phase"],
        ["--package"],
        ["--module-coupling"],
        ["--call-graph"]
    ]

    private func writeSource(in dir: URL) throws {
        let source = """
        enum Phase { case idle, running }

        class Service {
            var phase: Phase = .idle
            let repository: Repository = Repository()
            func run() {
                phase = .running
                repository.save()
            }
        }

        class Repository {
            func save() {}
        }
        """
        try source.write(to: dir.appendingPathComponent("Service.swift"), atomically: true, encoding: .utf8)
    }

    private func render(_ arguments: [String], in dir: URL, to fileName: String) async throws -> String {
        let output = dir.appendingPathComponent(fileName)
        var cmd = try CLITestSupport.parseDiagram(
            ["--source", dir.path, "--language", "swift", "--output", output.path] + arguments
        )
        try await cmd.run()
        return try String(contentsOf: output, encoding: .utf8)
    }

    @Test(arguments: shapes)
    func omittingTheFormatRendersMermaidForEveryShape(_ shape: [String]) async throws {
        try await CLITestSupport.withTempDirectory { dir in
            try writeSource(in: dir)
            let inferred = try await render(shape, in: dir, to: "diagram.txt")
            let mermaid = try await render(shape + ["--format", "mermaid"], in: dir, to: "explicit.txt")
            #expect(inferred == mermaid)
            #expect(!inferred.contains("digraph"))
        }
    }

    @Test(arguments: ["diagram.dot", "diagram.gv", "DIAGRAM.DOT"])
    func aGraphvizExtensionInfersDOT(_ fileName: String) async throws {
        try await CLITestSupport.withTempDirectory { dir in
            try writeSource(in: dir)
            #expect(try await render([], in: dir, to: fileName).contains("digraph"))
        }
    }

    @Test(arguments: ["diagram.mmd", "diagram.md", "diagram.mermaid"])
    func aMermaidExtensionInfersMermaid(_ fileName: String) async throws {
        try await CLITestSupport.withTempDirectory { dir in
            try writeSource(in: dir)
            let contents = try await render([], in: dir, to: fileName)
            #expect(contents.contains("classDiagram"))
            #expect(!contents.contains("digraph"))
        }
    }

    @Test func anExplicitFormatWinsOverTheExtension() async throws {
        try await CLITestSupport.withTempDirectory { dir in
            try writeSource(in: dir)
            let contents = try await render(["--format", "mermaid"], in: dir, to: "diagram.dot")
            #expect(contents.contains("classDiagram"))
            #expect(!contents.contains("digraph"))
        }
    }

    @Test func stdoutUsesTheStandardFormat() {
        #expect(DiagramFormat(inferredFromOutput: nil) == .standard)
        #expect(DiagramFormat.standard == .mermaid)
    }
}
