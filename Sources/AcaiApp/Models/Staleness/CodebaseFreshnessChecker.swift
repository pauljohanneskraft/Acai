import Foundation
import AcaiGit

/// Does file I/O — call off the main actor.
struct CodebaseFreshnessChecker {
    let directoryPath: String
    /// A pinned revision (`Codebase.pinnedRevision`) is fresh until it names a different commit;
    /// edits to the working tree don't concern it.
    var revision: String?

    func currentFingerprint() -> CodeStateFingerprint {
        let directory = URL(fileURLWithPath: directoryPath)
        if let revision {
            let sha = (try? GitDiffSnapshot(directory: directory, reference: revision).commitSHA()) ?? revision
            return .git(headCommitSHA: sha, isDirty: false)
        }
        if let checkout = try? GitCheckout(directory: directory),
           let headCommitSHA = try? checkout.headCommitSHA,
           let isDirty = try? checkout.hasUncommittedChanges {
            return .git(headCommitSHA: headCommitSHA, isDirty: isDirty)
        }
        return SourceTreeFingerprint(directory: directory).compute()
    }
}
