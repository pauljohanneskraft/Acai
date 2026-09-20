import libgit2

/// How much history a clone or fetch transfers. A fetch at `.full` into an already-shallow
/// repository keeps it shallow; only `.unshallow` deepens it to the complete history.
public enum GitHistoryDepth: Sendable, Hashable {
    case full
    /// Only the tip commit of each fetched ref.
    case latestSnapshot
    case unshallow

    var libgit2Depth: Int32 {
        switch self {
        case .full:
            Int32(GIT_FETCH_DEPTH_FULL.rawValue)
        case .latestSnapshot:
            1
        case .unshallow:
            Int32(GIT_FETCH_DEPTH_UNSHALLOW.rawValue)
        }
    }
}
