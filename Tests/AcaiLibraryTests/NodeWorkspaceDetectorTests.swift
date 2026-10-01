import Foundation
import Testing
import AcaiCore
@testable import AcaiLibrary

/// How a Node project's packages are discovered when the manifest is not a plain npm `workspaces`
/// array: pnpm's separate file, a manifest or workspace file that cannot be read, and a
/// solution-style root whose own `tsconfig` would otherwise re-admit the whole repository.
@Suite("Node workspace discovery", .timeLimit(.minutes(1)))
struct NodeWorkspaceDetectorTests {

    // MARK: - Fixture helpers

    private func withTempDir(_ body: (URL) throws -> Void) throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("node-workspace-detector-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try body(dir.standardizedFileURL)
    }

    private func write(_ relativePath: String, in root: URL, contents: String = "// file") throws {
        let url = root.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }

    /// The last path components of a spec's source dirs (stable, location-independent assertions).
    private func dirNames(_ specs: [SourceSpec], for language: CodeArtifact.SourceLanguage) -> [String] {
        specs.first { $0.language == language }?.sourceDirs.map(\.lastPathComponent) ?? []
    }

    /// The last two components of each source dir, so a package's own folder is visible.
    private func packageDirs(_ specs: [SourceSpec]) -> [String] {
        specs.first?.sourceDirs.map { $0.pathComponents.suffix(2).joined(separator: "/") } ?? []
    }

    // MARK: - pnpm

    /// pnpm declares the same flat list of globs in `pnpm-workspace.yaml` and leaves the manifest key
    /// out entirely, so a pnpm monorepo must be read the same way an npm one is.
    @Test func nodeReadsPnpmWorkspacePackages() throws {
        let detector = NodeDetector()
        try withTempDir { root in
            try write("package.json", in: root, contents: "{}")
            try write("pnpm-workspace.yaml", in: root, contents: """
            packages:
              # Everything under packages, except the fixtures.
              - 'packages/*'
              - "!packages/legacy"
            """)
            try write("packages/core/package.json", in: root, contents: "{}")
            try write("packages/core/src/core.ts", in: root)
            try write("packages/legacy/package.json", in: root, contents: "{}")
            try write("packages/legacy/src/old.ts", in: root)

            let specs = detector.discoverSourceSpecs(at: root, requestedLanguages: [])
            #expect(packageDirs(specs) == ["core/src"])
            #expect(specs.first?.diagnostics.isEmpty == true)
        }
    }

    @Test func nodeReadsPnpmPackagesWrittenAsAFlowSequence() throws {
        let detector = NodeDetector()
        try withTempDir { root in
            try write("package.json", in: root, contents: "{}")
            try write("pnpm-workspace.yaml", in: root, contents: "packages: ['packages/*']\n")
            try write("packages/core/package.json", in: root, contents: "{}")
            try write("packages/core/src/core.ts", in: root)

            let specs = detector.discoverSourceSpecs(at: root, requestedLanguages: [])
            #expect(packageDirs(specs) == ["core/src"])
        }
    }

    /// A `pnpm-workspace.yaml` whose `packages:` list cannot be read leaves the packages unknown —
    /// which is not the same as a project that declares none.
    @Test func nodeRecordsADiagnosticForAnUnreadablePnpmWorkspace() throws {
        let detector = NodeDetector()
        try withTempDir { root in
            try write("package.json", in: root, contents: "{}")
            try write("pnpm-workspace.yaml", in: root, contents: "packages:\n  nested:\n    - 'a/*'\n")
            try write("src/app.ts", in: root)

            let specs = detector.discoverSourceSpecs(at: root, requestedLanguages: [])
            #expect(dirNames(specs, for: .typeScript) == ["src"])
            #expect(specs.first?.diagnostics.map(\.location.filePath) == ["pnpm-workspace.yaml"])
        }
    }

    /// A manifest that will not parse is a monorepo about to be analysed as a single package. On disk
    /// it is indistinguishable from one that declares no workspaces, so it has to say so.
    @Test func nodeRecordsADiagnosticForAnUnreadableManifest() throws {
        let detector = NodeDetector()
        try withTempDir { root in
            try write("package.json", in: root, contents: #"{"name": "app",}"# + "\n  oops")
            try write("src/app.ts", in: root)

            let specs = detector.discoverSourceSpecs(at: root, requestedLanguages: [])
            #expect(dirNames(specs, for: .typeScript) == ["src"])
            #expect(specs.first?.diagnostics.map(\.kind) == [.incompleteDiscovery])
            #expect(specs.first?.diagnostics.first?.location.filePath == "package.json")
        }
    }

    /// A `tsc --init` manifest is still strict JSON, but a trailing comma gets added by hand often
    /// enough that the distinction matters: this one parses, so nothing is reported.
    @Test func nodeReadsAManifestWithATrailingComma() throws {
        let detector = NodeDetector()
        try withTempDir { root in
            try write("package.json", in: root, contents: #"{"workspaces": ["packages/*",],}"#)
            try write("packages/core/package.json", in: root, contents: "{}")
            try write("packages/core/src/core.ts", in: root)

            let specs = detector.discoverSourceSpecs(at: root, requestedLanguages: [])
            #expect(packageDirs(specs) == ["core/src"])
            #expect(specs.first?.diagnostics.isEmpty == true)
        }
    }

    /// A solution-style root declares `workspaces` *and* a `tsconfig.json` whose `include` has no
    /// literal prefix, which resolves to the root itself. Admitting it would re-import every package
    /// through the back door — exactly what reading the globs is for.
    @Test func nodeNeverAdmitsAWorkspaceRootViaAWildcardInclude() throws {
        let detector = NodeDetector()
        try withTempDir { root in
            try write("package.json", in: root, contents: #"{"workspaces": ["packages/*"]}"#)
            try write("tsconfig.json", in: root, contents: #"{"include": ["**/*.ts"]}"#)
            try write("packages/core/package.json", in: root, contents: "{}")
            try write("packages/core/src/core.ts", in: root)
            // Only reachable if the root itself were used as a source dir.
            try write("scratch/stray.ts", in: root)

            let specs = detector.discoverSourceSpecs(at: root, requestedLanguages: [])
            #expect(packageDirs(specs) == ["core/src"])
        }
    }
}
