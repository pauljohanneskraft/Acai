import Foundation
import Testing
import AcaiCore

/// `AnalysisService.parseFiles` polls `Task.checkCancellation()` between files. Cancels the
/// enclosing `Task` from *inside* `parse(source:fileName:)` itself once a known number of files
/// have gone through it, rather than racing real wall-clock timing against a background cancel —
/// deterministic proof that the parse loop actually stops rather than merely having its eventual
/// result discarded by a caller.
private final class CountingParser: CodeParser, @unchecked Sendable {
    var language: CodeArtifact.SourceLanguage { .init(rawValue: "fixture") }
    var fileExtensions: [String] { ["fx"] }
    var configuration: LanguageConfiguration { LanguageConfiguration() }

    private let lock = NSLock()
    private var count = 0
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
        lock.unlock()
        if reachedLimit {
            withUnsafeCurrentTask { $0?.cancel() }
        }
        return CodeArtifact(metadata: .init(sourceLanguage: language, filePaths: [fileName]), types: [])
    }
}

@Suite("AnalysisService cancellation")
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
        let service = AnalysisService(parsers: [parser])

        let task = Task {
            try service.analyzeProject(at: root, allowedLanguages: [])
        }

        await #expect(throws: (any Error).self) {
            try await task.value
        }
        #expect(parser.parsedCount == 2, "the loop must stop as soon as cancellation is observed, not after every file")
    }
}
