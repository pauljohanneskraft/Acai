import Foundation

/// Runs one piece of work on a dedicated thread with a stack far larger than the 512 KB a
/// cooperative-pool thread gets.
///
/// Parsing recurses once per level of a declaration's nesting — a SwiftSyntax visitor, or a
/// recursive-descent parser's own frames — so a generated or hostile file nested thousands of levels
/// deep overflows a pool thread and takes the whole process down with `SIGBUS`. The engine parses
/// in-process, so that would also take the MCP server with it.
public struct LargeStackRunner: Sendable {

    /// 64 MB: 128× a cooperative-pool thread. The deepest case the parsers are tested against, a
    /// 5,000-level Swift call chain, was measured to need between 8 and 10 MB — and how much a
    /// nesting level costs is set by the toolchain's frame layout, not by this package, so the
    /// margin has to absorb a compiler change rather than merely clear today's figure. The stack is
    /// virtual address space, committed only as it is touched, so an ordinary file costs nothing
    /// extra.
    public static let standard = LargeStackRunner(stackSize: 64 * 1024 * 1024)

    private let stackSize: Int

    public init(stackSize: Int) {
        self.stackSize = stackSize
    }

    /// Suspends the caller — it does not block a pool thread — until the work finishes on the
    /// dedicated thread.
    public func run<Value: Sendable>(_ work: @escaping @Sendable () -> Value) async -> Value {
        await withCheckedContinuation { continuation in
            start { continuation.resume(returning: work()) }
        }
    }

    /// For a synchronous caller that cannot suspend, such as a `BuildSystemDetector`. Blocks the
    /// calling thread; the work runs on a thread of its own, so it cannot deadlock against the
    /// cooperative pool.
    public func runSynchronously<Value: Sendable>(_ work: @escaping @Sendable () -> Value) -> Value {
        let box = ValueBox<Value>()
        let finished = DispatchSemaphore(value: 0)
        start {
            box.value = work()
            finished.signal()
        }
        finished.wait()
        guard let value = box.value else {
            preconditionFailure("the worker thread signalled before storing its value")
        }
        return value
    }

    private func start(_ body: @escaping @Sendable () -> Void) {
        let thread = Thread(block: body)
        thread.stackSize = stackSize
        thread.name = "com.acai.large-stack"
        thread.start()
    }

    /// Hand-off between the worker thread and the waiter, ordered by the semaphore rather than by a
    /// lock: the write happens before `signal()` and the read after `wait()`.
    private final class ValueBox<Value: Sendable>: @unchecked Sendable {
        var value: Value?
    }
}

extension CodeParser {

    /// Every parse goes through here, so a deeply nested file cannot overflow the 512 KB stack of
    /// the cooperative-pool thread that asked for it.
    func parsedOnALargeStack(source: String, fileName: String) async -> CodeArtifact {
        await LargeStackRunner.standard.run { self.parse(source: source, fileName: fileName) }
    }
}
