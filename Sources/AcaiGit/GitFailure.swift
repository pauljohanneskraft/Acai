import Foundation
import SwiftGitX

/// A user-facing wrapper for every failure `AcaiGit` throws. `SwiftGitX`'s own `SwiftGitXError`
/// doesn't conform to `LocalizedError`, so callers relying on `error.localizedDescription`
/// (`USABILITY_GUARDRAILS.md` §3: every thrown error needs a specific, actionable
/// `errorDescription`) would otherwise see a generic message instead of the real one.
struct GitFailure: LocalizedError {
    let message: String

    var errorDescription: String? { message }
}

extension SwiftGitXError {
    /// Wraps this error with `context` prefixed onto libgit2's own message, so the result reads as
    /// a full sentence (e.g. "Couldn't clone the repository: repository not found").
    func asFailure(_ context: String) -> GitFailure {
        GitFailure(message: "\(context): \(message)")
    }
}
