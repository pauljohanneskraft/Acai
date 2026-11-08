import Foundation
import Testing
import AcaiCore
@testable import AcaiLibrary

/// A Latin-1 source — the common case in older C, C++ and Java trees — through the real parsers the
/// app and CLI use, rather than a stub: its types have to come out, and the substitution has to be
/// reported once.
@Suite("Non-UTF-8 sources", .timeLimit(.minutes(1)))
struct LossyDecodingAnalysisTests {

    private func withTempDir(_ body: (URL) async throws -> Void) async throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("lossy-decoding-\(UUID().uuidString)", isDirectory: true)
            .standardizedFileURL
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try await body(root)
    }

    @Test func aLatin1SourceIsAnalysedAndReportsOneLossyDecodingDiagnostic() async throws {
        try await withTempDir { root in
            try "project(Demo)\n".write(
                to: root.appendingPathComponent("CMakeLists.txt"), atomically: true, encoding: .utf8)
            let source = """
            // Grüße aus München
            class Widget {
            public:
                int value;
            };
            """
            try #require(source.data(using: .isoLatin1)).write(to: root.appendingPathComponent("widget.cpp"))

            let artifact = try await AnalysisService.standard.analyzeProject(at: root, allowedLanguages: [])

            #expect(artifact.flattened().map(\.name) == ["Widget"])

            let report = HealthCheck(artifact: artifact).report
            #expect(report.diagnostics.map(\.kind) == [.lossyDecoding])
            #expect(report.diagnostics.first?.location.filePath == "widget.cpp")
            #expect(report.score == 1)
        }
    }

    @Test func aUTF8SourceWithTheSameTextReportsNothing() async throws {
        try await withTempDir { root in
            try "project(Demo)\n".write(
                to: root.appendingPathComponent("CMakeLists.txt"), atomically: true, encoding: .utf8)
            try "// Grüße aus München\nclass Widget {\npublic:\n    int value;\n};\n".write(
                to: root.appendingPathComponent("widget.cpp"), atomically: true, encoding: .utf8)

            let artifact = try await AnalysisService.standard.analyzeProject(at: root, allowedLanguages: [])

            #expect(artifact.flattened().map(\.name) == ["Widget"])
            #expect(artifact.metadata.parseDiagnostics.isEmpty)
        }
    }
}
