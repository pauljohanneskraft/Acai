import Foundation
import Testing
import AcaiCore
@testable import AcaiLibrary

/// The declared monorepo layout has to survive the whole pipeline, not just the detector: a package the
/// workspace globs name must be parsed, one outside them must not, and a `tsconfig` graph that could
/// not be followed must reach the artifact so `HealthCheck` can report it.
@Suite("Node workspace analysis", .timeLimit(.minutes(1)))
struct NodeWorkspaceAnalysisTests {

    private func withTempDir(_ body: (URL) async throws -> Void) async throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("node-workspace-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try await body(dir.standardizedFileURL)
    }

    private func write(_ relativePath: String, in root: URL, contents: String) throws {
        let url = root.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }

    @Test func declaredWorkspacePackagesDecideWhichFilesAreParsed() async throws {
        try await withTempDir { root in
            try write("package.json", in: root, contents: #"{"workspaces": ["packages/*"]}"#)
            try write("packages/core/package.json", in: root, contents: "{}")
            try write("packages/core/src/core.ts", in: root, contents: "export class Core {}")
            try write("packages/ui/package.json", in: root, contents: "{}")
            try write("packages/ui/src/ui.ts", in: root, contents: "export class Widget {}")
            // Not under any declared workspace, so not part of the build.
            try write("scratch/stray.ts", in: root, contents: "export class Stray {}")

            let artifact = try await AnalysisService.standard
                .analyzeProject(at: root, allowedLanguages: [.typeScript])
            #expect(artifact.flattened().map(\.name).sorted() == ["Core", "Widget"])
            #expect(artifact.metadata.parseDiagnostics.isEmpty)
        }
    }

    @Test func aTsconfigCycleReachesTheArtifactsDiagnostics() async throws {
        try await withTempDir { root in
            try write("package.json", in: root, contents: "{}")
            try write("tsconfig.json", in: root, contents: """
            {"include": ["src"], "references": [{"path": "./nested"}]}
            """)
            try write("nested/tsconfig.json", in: root, contents: #"{"references": [{"path": ".."}]}"#)
            try write("src/a.ts", in: root, contents: "export class Sample {}")

            let artifact = try await AnalysisService.standard
                .analyzeProject(at: root, allowedLanguages: [.typeScript])
            #expect(artifact.flattened().map(\.name) == ["Sample"])
            #expect(artifact.metadata.parseDiagnostics.map(\.kind) == [.incompleteDiscovery])
        }
    }
}
