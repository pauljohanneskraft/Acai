import ArgumentParser
import Foundation
import Testing
import AcaiCore
@testable import AcaiCLI

/// Covers `analyze`, `store`, and `list` at the safe level: validation/parse paths and the
/// `analyze` run path via `--output`. The `store`/`list` run paths write/read the user's
/// `~/.config/acai`, so they are only exercised at the parse level (plus `store`'s source-dir guard,
/// which runs before any storage write).
@Suite("Analyze / Store / List Commands")
struct AnalyzeListStoreCommandTests {

    // MARK: - analyze

    @Test func analyzeNonexistentSourceThrows() throws {
        var cmd = try CLITestSupport.parseAnalyze(["--source", CLITestSupport.nonexistentPath()])
        #expect {
            try cmd.run()
        } throws: { error in
            CLITestSupport.message(for: error).contains("Source directory does not exist:")
        }
    }

    @Test func analyzeWritesDecodableArtifactToOutput() throws {
        try CLITestSupport.withTempDirectory { dir in
            try CLITestSupport.writeSampleSwiftSource(in: dir)
            let output = dir.appendingPathComponent("artifact.json")
            var cmd = try CLITestSupport.parseAnalyze(
                ["--source", dir.path, "--language", "swift", "--output", output.path]
            )
            try cmd.run()

            let data = try Data(contentsOf: output)
            let artifact = try JSONDecoder().decode(CodeArtifact.self, from: data)
            #expect(artifact.metadata.sourceLanguage == .swift)
            #expect(artifact.types.contains { $0.name == "Service" })
        }
    }

    @Test func analyzeRequiresSourceArgument() throws {
        // A source is required, but it may come from --source or --from, so the requirement is
        // enforced at run time rather than by ArgumentParser.
        var cmd = try CLITestSupport.parseAnalyze([])
        #expect {
            try cmd.run()
        } throws: { error in
            CLITestSupport.message(for: error).contains("Either --from or --source")
        }
    }

    // MARK: - store

    @Test func storeParsesNameAndSource() throws {
        let root = try AcaiCommand.parseAsRoot(["store", "my-analysis", "/tmp/src"])
        let cmd = try #require(root as? AcaiCommand.Store)
        #expect(cmd.name == "my-analysis")
        #expect(cmd.sourceDir == "/tmp/src")
    }

    @Test func storeRequiresBothPositionalArguments() {
        // Only one of the two required positionals supplied.
        #expect {
            _ = try AcaiCommand.parseAsRoot(["store", "only-name"])
        } throws: { error in
            CLITestSupport.exitCode(for: error) == ExitCode.validationFailure
        }
    }

    @Test func storeNonexistentSourceThrowsBeforeWriting() throws {
        // The source-dir guard runs before any write to `~/.config/acai`, so this is safe to run.
        let root = try AcaiCommand.parseAsRoot(["store", "name", CLITestSupport.nonexistentPath()])
        var cmd = try #require(root as? AcaiCommand.Store)
        #expect {
            try cmd.run()
        } throws: { error in
            CLITestSupport.message(for: error).contains("Source directory does not exist:")
        }
    }

    // MARK: - list

    @Test func listParsesWithNoArguments() throws {
        let root = try AcaiCommand.parseAsRoot(["list"])
        #expect(root is AcaiCommand.List)
    }

    @Test func listRejectsUnexpectedArgument() {
        #expect {
            _ = try AcaiCommand.parseAsRoot(["list", "unexpected"])
        } throws: { error in
            CLITestSupport.exitCode(for: error) == ExitCode.validationFailure
        }
    }
}
