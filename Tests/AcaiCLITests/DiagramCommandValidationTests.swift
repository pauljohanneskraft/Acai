import ArgumentParser
import Testing
@testable import AcaiCLI

/// Drives `AcaiCommand.Diagram.validate()` through ArgumentParser, asserting the message for every
/// validation branch (DiagramCommand.swift). Parsing succeeds when `validate()` does not throw.
@Suite("Diagram Command Validation")
struct DiagramCommandValidationTests {

    /// Asserts that parsing `arguments` fails with a message containing `expected`.
    private func expectValidationError(_ arguments: [String], contains expected: String) {
        #expect {
            _ = try AcaiCommand.parseAsRoot(["diagram"] + arguments)
        } throws: { error in
            CLITestSupport.message(for: error).contains(expected)
        }
    }

    @Test func requiresFromOrSource() {
        expectValidationError([], contains: "Either --from or --source must be specified.")
    }

    @Test func rejectsBothFromAndSource() {
        expectValidationError(
            ["--from", "a.json", "--source", "/tmp/x"],
            contains: "Specify either --from or --source, not both."
        )
    }

    @Test func rejectsConflictingMemberFlags() {
        expectValidationError(
            ["--source", "/tmp/x", "--show-members", "--no-show-members"],
            contains: "Cannot specify both --show-members and --no-show-members."
        )
    }

    @Test func rejectsSequenceAndStateTogether() {
        expectValidationError(
            ["--source", "/tmp/x", "--sequence-from", "A.run", "--state-from", "A.state"],
            contains: "Specify either --sequence-from or --state-from, not both."
        )
    }

    @Test func rejectsMultipleModeFlags() {
        expectValidationError(
            ["--source", "/tmp/x", "--sequence-from", "A.run", "--package"],
            contains: "Specify only one of"
        )
    }

    @Test func rejectsScopeWithoutCallGraph() {
        expectValidationError(
            ["--source", "/tmp/x", "--call-graph-scope", "type:A"],
            contains: "--call-graph-scope requires --call-graph."
        )
    }

    @Test func rejectsMaxDepthBelowRange() {
        expectValidationError(
            ["--source", "/tmp/x", "--max-depth", "0"],
            contains: "--max-depth must be between 1 and 100."
        )
    }

    @Test func rejectsMaxDepthAboveRange() {
        expectValidationError(
            ["--source", "/tmp/x", "--max-depth", "101"],
            contains: "--max-depth must be between 1 and 100."
        )
    }

    @Test func rejectsMaxStatesBelowRange() {
        expectValidationError(
            ["--source", "/tmp/x", "--max-states", "0"],
            contains: "--max-states must be between 1 and 1000."
        )
    }

    @Test func rejectsMaxStatesAboveRange() {
        expectValidationError(
            ["--source", "/tmp/x", "--max-states", "1001"],
            contains: "--max-states must be between 1 and 1000."
        )
    }

    @Test func acceptsInRangeBounds() throws {
        // A well-formed invocation parses and validates without throwing.
        let cmd = try CLITestSupport.parseDiagram(
            ["--source", "/tmp/x", "--max-depth", "100", "--max-states", "1000"]
        )
        #expect(cmd.maxDepth == 100)
        #expect(cmd.maxStates == 1000)
    }

    @Test func validationErrorUsesValidationExitCode() {
        do {
            _ = try AcaiCommand.parseAsRoot(["diagram"])
            Issue.record("expected a validation error")
        } catch {
            #expect(CLITestSupport.exitCode(for: error) == ExitCode.validationFailure)
        }
    }
}
