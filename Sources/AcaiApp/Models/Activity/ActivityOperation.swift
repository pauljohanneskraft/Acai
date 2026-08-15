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
    /// `nil` = indeterminate. A git fetch/clone reports real `received_objects / total_objects`
    /// progress here once libgit2 knows the pack's total size (see `GitFetch`, `ActivityCenter`'s
    /// progress-reporting `run` overload); a reindex's parse pass has no comparable notion of
    /// total work and stays indeterminate throughout.
    var progress: Double?
    var startedAt: Date = Date()
    /// Requests cancellation of the underlying work. See `ActivityCenter.run`'s doc comment for
    /// exactly what "cancel" does and doesn't guarantee for the operation kinds wired in today.
    var requestCancel: @Sendable () -> Void
}

/// Throttles how often a noisy progress source (libgit2's transfer-progress callback fires on
/// every packet) is allowed to reach `ActivityCenter.updateProgress` — without this, a fetch of any
/// real size would queue thousands of main-actor hops. `@unchecked Sendable`: `NSLock` already
/// provides the exclusion `advance(to:)` needs across the arbitrary threads libgit2 calls back on.
final class ActivityProgressGate: @unchecked Sendable {
    private let lock = NSLock()
    private var lastReported = -1.0

    /// Whether `value` has moved far enough past the last reported value (or reached completion)
    /// to be worth publishing.
    func advance(to value: Double) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard value - lastReported >= 0.01 || value >= 1 else { return false }
        lastReported = value
        return true
    }
}
