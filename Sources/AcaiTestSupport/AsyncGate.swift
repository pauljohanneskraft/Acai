import Foundation

/// A one-shot signal an in-flight operation can `wait()` on, so a test can hold an operation open
/// until it has actually observed the state it's asserting on — a fixed `Task.sleep` races the
/// scheduling latency `Eventually` is designed to avoid, and flakes under a loaded parallel test run
/// for the same reason.
public actor AsyncGate {
    public struct TimedOut: Error {}

    private var isOpen = false
    private var continuations: [CheckedContinuation<Void, Never>] = []

    public init() {}

    public func open() {
        isOpen = true
        for continuation in continuations { continuation.resume() }
        continuations = []
    }

    public func wait() async {
        if isOpen { return }
        await withCheckedContinuation { continuations.append($0) }
    }

    /// Like `wait()`, but bounded — for a negative assertion ("this must not have happened") whose
    /// only legitimate failure mode should be a real timeout, never a guessed sleep racing the thing
    /// under test.
    public func wait(timeout: Duration) async throws {
        let deadline = ContinuousClock.now + timeout
        while !isOpen, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(5))
        }
        if !isOpen {
            throw TimedOut()
        }
    }
}
