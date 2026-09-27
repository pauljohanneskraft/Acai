import Foundation
import Testing
import AcaiCore

/// A `CodeParser` whose `parse` call takes a fixed, measurable amount of wall-clock time (real CPU
/// work, not `Task.sleep`, since `parse` is synchronous) — lets a test observe whether files were
/// parsed one after another or overlapped, without depending on the real Tree-sitter/SwiftSyntax
/// parsers' actual speed.
private struct SlowParser: CodeParser {
    var language: CodeArtifact.SourceLanguage { .init(rawValue: "fixture") }
    var fileExtensions: [String] { ["fx"] }
    var configuration: LanguageConfiguration { LanguageConfiguration() }
    let delay: TimeInterval

    func parse(source: String, fileName: String) -> CodeArtifact {
        Thread.sleep(forTimeInterval: delay)
        let name = (fileName as NSString).lastPathComponent.replacingOccurrences(of: ".fx", with: "")
        let type = TypeDeclaration(
            id: name, name: name, qualifiedName: name, kind: .class, accessLevel: .public,
            location: .init(filePath: fileName, line: 1, column: 1)
        )
        return CodeArtifact(metadata: .init(sourceLanguage: language, filePaths: [fileName]), types: [type])
    }
}

@Suite("AnalysisService file-parsing concurrency")
struct AnalysisServiceConcurrencyTests {
    private static let fileCount = 8
    private static let delayPerFile: TimeInterval = 0.03

    private func makeFixture() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("AcaiCoreConcurrencyTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        for index in 0..<Self.fileCount {
            try "".write(to: root.appendingPathComponent("File\(index).fx"), atomically: true, encoding: .utf8)
        }
        return root
    }

    /// Skipped on a single-core host, where bounded concurrency degenerates to the serial case and
    /// there is nothing to measure a speed-up against.
    @Test(
        "Concurrent parsing is faster than serial parsing of the same files, and produces the same result",
        .disabled(if: ProcessInfo.processInfo.activeProcessorCount < 2)
    )
    func concurrentParsingIsFasterAndDeterministic() async throws {
        let root = try makeFixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let parser = SlowParser(delay: Self.delayPerFile)

        let serialService = AnalysisService(parsers: [parser], fileParsingConcurrencyLimit: 1)
        let serialStart = Date()
        let serialArtifact = try await serialService.analyzeProject(at: root, allowedLanguages: [])
        let serialDuration = Date().timeIntervalSince(serialStart)

        let concurrentService = AnalysisService(parsers: [parser])
        let concurrentStart = Date()
        let concurrentArtifact = try await concurrentService.analyzeProject(at: root, allowedLanguages: [])
        let concurrentDuration = Date().timeIntervalSince(concurrentStart)

        // Every file is parsed exactly once either way — a byte-identical result (same names, same
        // order) is the property the issue calls "critical": fan-out must not change the output.
        #expect(serialArtifact.types.map(\.name).sorted() == concurrentArtifact.types.map(\.name).sorted())
        #expect(serialArtifact == concurrentArtifact)

        let cores = ProcessInfo.processInfo.activeProcessorCount
        #expect(
            concurrentDuration < serialDuration * 0.75,
            """
            expected concurrent parsing of \(Self.fileCount) files to be meaningfully faster than serial \
            (serial: \(serialDuration)s, concurrent: \(concurrentDuration)s, activeProcessorCount: \(cores))
            """
        )
    }
}
