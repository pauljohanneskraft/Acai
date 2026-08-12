import Foundation
import Testing
@testable import AcaiApp

/// `CIQualityCheckInvocation` formats the "Export CI Check" snippet next to `QualityCheckSection`:
/// a plain `acai quality` shell command plus a GitHub Actions step. Both must reference the
/// codebase's actually-configured rules path — the acceptance bar is "the correct, real rules
/// path for a codebase that has one configured," and a sensible fallback when that path can't be
/// expressed relative to a CI checkout (an app-managed or otherwise out-of-repo rules file).
@Suite("CIQualityCheckInvocation")
struct CIQualityCheckInvocationTests {
    @Test("Rules file inside the codebase's directory uses the checkout-relative path in the Actions step")
    func rulesFileInsideDirectoryUsesRelativePath() {
        let invocation = CIQualityCheckInvocation(
            directoryPath: "/Users/alice/dev/myrepo",
            rulesPath: "/Users/alice/dev/myrepo/quality.yml")

        #expect(invocation.shellCommand ==
            "acai quality --source '/Users/alice/dev/myrepo' --rules '/Users/alice/dev/myrepo/quality.yml'")
        #expect(invocation.gitHubActionsStep.contains("--rules 'quality.yml'"))
        #expect(invocation.gitHubActionsStep.contains("acai quality --source ."))
        #expect(!invocation.needsExportNote)
        #expect(!invocation.gitHubActionsStep.contains("commit a copy"))
    }

    @Test("Rules file nested in a subdirectory: Actions step keeps the relative subpath")
    func rulesFileInSubdirectoryKeepsRelativeSubpath() {
        let invocation = CIQualityCheckInvocation(
            directoryPath: "/Users/alice/dev/myrepo",
            rulesPath: "/Users/alice/dev/myrepo/config/quality.yml")

        #expect(invocation.gitHubActionsStep.contains("--rules 'config/quality.yml'"))
        #expect(!invocation.needsExportNote)
    }

    @Test("Rules file outside the codebase's directory falls back to a placeholder path with a note")
    func rulesFileOutsideDirectoryFallsBackToPlaceholder() {
        let invocation = CIQualityCheckInvocation(
            directoryPath: "/Users/alice/dev/myrepo",
            rulesPath: "/Users/alice/Library/Application Support/Acai/Rules/codebase_1234.yaml")

        #expect(invocation.needsExportNote)
        #expect(invocation.gitHubActionsStep.contains("--rules 'quality.yml'"))
        #expect(invocation.gitHubActionsStep.contains("commit a copy"))
        // The shell command must still surface the correct, real configured rules path — the
        // fallback is only for the checkout-relative Actions step, which can't see that file.
        #expect(invocation.shellCommand.contains(
            "'/Users/alice/Library/Application Support/Acai/Rules/codebase_1234.yaml'"))
    }

    @Test("A path containing a single quote is shell-escaped safely")
    func pathWithSingleQuoteIsEscaped() {
        let invocation = CIQualityCheckInvocation(
            directoryPath: "/Users/alice/dev/Bob's Repo",
            rulesPath: "/Users/alice/dev/Bob's Repo/quality.yml")

        #expect(invocation.shellCommand.contains("'/Users/alice/dev/Bob'\\''s Repo'"))
    }
}
