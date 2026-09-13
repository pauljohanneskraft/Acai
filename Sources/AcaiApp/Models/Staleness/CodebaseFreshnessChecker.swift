import Foundation
import AcaiGit

/// Computes a codebase's current on-disk state, to compare against the fingerprint captured when it
/// was last indexed (`Codebase.indexedFingerprint`) and say whether the analysis still matches the
/// code. Prefers the checkout's own git state; falls back to file modification times when there's no
/// repository to consult, so a plain folder is covered too. Does file I/O — call off the main actor.
struct CodebaseFreshnessChecker {
    let directoryPath: String

    func currentFingerprint() -> CodeStateFingerprint {
        let directory = URL(fileURLWithPath: directoryPath)
        if let checkout = try? GitCheckout(directory: directory),
           let headCommitSHA = try? checkout.headCommitSHA,
           let isDirty = try? checkout.hasUncommittedChanges {
            return .git(headCommitSHA: headCommitSHA, isDirty: isDirty)
        }
        return SourceTreeFingerprint(directory: directory).compute()
    }
}
