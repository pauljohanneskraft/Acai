/// The phases a download moves through.
public enum DownloadState {
    case idle
    case requested
    case downloading
    case verifying
    case finished
    case failed
}

/// A download whose `state` advances through a pipeline. `run()` walks the happy path as a
/// sequence of assignments — which the value-flow analysis renders as a transition chain —
/// while `fail()` is a branch reachable from the start.
public final class Download {
    public private(set) var state: DownloadState = .idle

    public func run() {
        state = .requested
        state = .downloading
        state = .verifying
        state = .finished
    }

    public func fail() {
        state = .failed
    }
}
