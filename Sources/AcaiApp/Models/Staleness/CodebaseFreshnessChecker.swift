import Foundation
import AcaiCore
import AcaiGit

/// Does file I/O — call off the main actor.
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
