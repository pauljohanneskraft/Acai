import Foundation
import AcaiCore
import AcaiDiagram
import AcaiLibrary

extension ClassDiagramDOTRenderer {
    /// Test convenience: a generator whose options carry `artifact`'s standard language
    /// configuration, resolved from the composition root just as production does.
    init(for artifact: CodeArtifact) {
        self.init(options: ClassDiagramOptions(languages: artifact.standardLanguageResolver))
    }
}

/// A source tree to analyse: a set of relative paths and their contents, written into a fresh
/// temporary directory for one test and removed afterwards.
struct SourceTreeFixture {
    private let files: [String: String]

    init(_ files: [String: String]) {
        self.files = files
    }

    /// Writes the tree, analyses it exactly as the app and CLI do, and hands over the artifact.
    func analysed(by body: (CodeArtifact) async throws -> Void) async throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("source-tree-\(UUID().uuidString)", isDirectory: true)
            .standardizedFileURL
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        for (path, contents) in files {
            let file = root.appendingPathComponent(path)
            try FileManager.default.createDirectory(
                at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try contents.write(to: file, atomically: true, encoding: .utf8)
        }
        try await body(try await AnalysisService.standard.analyzeProject(at: root, allowedLanguages: []))
    }
}
