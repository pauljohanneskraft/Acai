import Foundation
import Testing
import AcaiCore

/// `SourceFileBatchParser` polls `Task.checkCancellation()` either side of every file.
///
/// The parse itself runs on a dedicated large-stack thread (#524), where `withUnsafeCurrentTask`
/// finds no task, so a parser can no longer cancel the analysis from inside itself. The test
/// cancels from outside instead — the way the app, the CLI and the MCP server cancel. It stays
/// deterministic rather than racing a background cancel against wall-clock timing: the parser
/// reports the moment it has parsed a known number of files and holds its own worker thread until
/// the test has cancelled, so the next `checkCancellation()` is guaranteed to be the one that fires.
private final class CountingParser: CodeParser, @unchecked Sendable {
    var language: CodeArtifact.SourceLanguage { .init(rawValue: "fixture") }
    var fileExtensions: [String] { ["fx"] }
    var configuration: LanguageConfiguration { LanguageConfiguration() }

    private let lock = NSLock()
    private var count = 0
    private var limitWaiter: CheckedContinuation<Void, Never>?
    private var limitReached = false
    /// Waited on the parse's own thread, never a cooperative-pool one.
    private let release = DispatchSemaphore(value: 0)

    let cancelAfter: Int

    init(cancelAfter: Int) {
        self.cancelAfter = cancelAfter
    }

    var parsedCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }

    func parse(source: String, fileName: String) -> CodeArtifact {
        lock.lock()
        count += 1
        let reachedLimit = count == cancelAfter
        var waiter: CheckedContinuation<Void, Never>?
        if reachedLimit {
            limitReached = true
            waiter = limitWaiter
            limitWaiter = nil
        }
        lock.unlock()
        if reachedLimit {
            waiter?.resume()
            release.wait()
        }
        return CodeArtifact(metadata: .init(sourceLanguage: language, filePaths: [fileName]), types: [])
    }

    /// Suspends until `cancelAfter` files have gone through ``parse(source:fileName:)``.
    func waitUntilLimitReached() async {
        await withCheckedContinuation { continuation in
            lock.lock()
            guard !limitReached else {
                lock.unlock()
                continuation.resume()
                return
            }
            limitWaiter = continuation
            lock.unlock()
        }
    }

    /// Lets the held parse return, so the loop reaches its next cancellation check.
    func releaseHeldParse() {
        release.signal()
    }
}

@Suite("AnalysisService cancellation", .timeLimit(.minutes(1)))
struct AnalysisServiceCancellationTests {
    private func makeTempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("AcaiCoreCancellationTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test("Cancelling mid-parse stops the loop instead of only discarding its eventual result")
    func cancellationStopsTheParseLoop() async throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let fileCount = 5
        for index in 0..<fileCount {
            try "".write(to: root.appendingPathComponent("File\(index).fx"), atomically: true, encoding: .utf8)
        }

        let parser = CountingParser(cancelAfter: 2)
        // Forces strictly serial parsing so cancelling mid-parse has a deterministic file count —
        // with real concurrency, several files can already be in flight when cancellation fires.
        let service = AnalysisService(parsers: [parser], fileParsingConcurrencyLimit: 1)

        let task = Task {
            try await service.analyzeProject(at: root, allowedLanguages: [])
        }

        await parser.waitUntilLimitReached()
        task.cancel()
        parser.releaseHeldParse()

        await #expect(throws: (any Error).self) {
            try await task.value
        }
        #expect(parser.parsedCount == 2, "the loop must stop as soon as cancellation is observed, not after every file")
    }
}
