import Foundation

/// Runs work on a dedicated thread whose stack holds a parse of a deeply nested file.
public struct LargeStackRunner: Sendable {

    /// About 6× the 8–10 MB a 5,000-deep Swift call chain needs; untouched stack is never committed.
    public static let standard = LargeStackRunner(stackSize: 64 * 1024 * 1024)

    private let stackSize: Int

    public init(stackSize: Int) {
        self.stackSize = stackSize
    }

    public func run<Value: Sendable>(_ work: @escaping @Sendable () -> Value) async -> Value {
        await withCheckedContinuation { continuation in
            start { continuation.resume(returning: work()) }
        }
    }

    /// Blocks the caller; the work runs on its own thread, so it cannot deadlock the cooperative pool.
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

    /// Ordered by the semaphore: written before `signal()`, read after `wait()`.
    private final class ValueBox<Value: Sendable>: @unchecked Sendable {
        var value: Value?
    }
}

extension CodeParser {

    func parsedOnALargeStack(source: String, fileName: String) async -> CodeArtifact {
        await LargeStackRunner.standard.run { self.parse(source: source, fileName: fileName) }
    }
}
