import Foundation

/// One in-flight background operation the app wants the user to be able to see and cancel — a
/// codebase reindex, a GitHub fetch/clone, or (in the future) a pull-request list load. Purely a
/// display+bookkeeping value; the actual work lives wherever `ActivityCenter.run` was called from.
struct ActivityOperation: Identifiable, Sendable {
    /// What kind of work this is — drives the row's icon; kept open-ended (not every future
    /// operation kind needs a case of its own) via `.other`'s associated label.
    enum Kind: Sendable {
        case reindex
        case gitFetch
        case gitClone
        case other(systemImage: String)

        var systemImage: String {
            switch self {
            case .reindex:
                "arrow.triangle.2.circlepath"
            case .gitFetch:
                "arrow.down.circle"
            case .gitClone:
                "square.and.arrow.down"
            case .other(let systemImage):
                systemImage
            }
        }
    }

    /// What this operation is *about*, so a row (a codebase, a repository) can ask "is work
    /// in flight for me specifically" without string-matching titles — see
    /// `ActivityCenter.isBusy(_:)`, the mechanism each per-row spinner reads.
    enum Subject: Hashable, Sendable {
        case codebase(UUID)
        case repository(URL)
        case none
    }

    var id = UUID()
    var title: String
    var kind: Kind
    var subject: Subject
    /// `nil` = indeterminate (no operation kind reports real byte/object progress yet — that's
    /// `AcaiGit`'s libgit2 transfer-callback plumbing, a separate, not-yet-built piece of work).
    /// Kept here so a future operation that *can* report progress has somewhere to put it without
    /// another model change.
    var progress: Double?
    var startedAt: Date = Date()
    /// Requests cancellation of the underlying work. See `ActivityCenter.run`'s doc comment for
    /// exactly what "cancel" does and doesn't guarantee for the operation kinds wired in today.
    var requestCancel: @Sendable () -> Void
}
