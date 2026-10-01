import Foundation
import Testing
@testable import AcaiJS

/// Reading a `tsconfig.json`'s `extends` chain and its project `references`, including the shapes that
/// yielded nothing before: a file that only extends a base, a reference fan-out, and a chain that
/// leads back on itself.
@Suite("TypeScript project graph", .timeLimit(.minutes(1)))
struct TypeScriptProjectTests {

    // MARK: - Fixture Helpers

    private func withTempDir(_ body: (URL) throws -> Void) throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("tsconfig-tests-\(UUID().uuidString)", isDirectory: true)
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

    private func dirNames(_ urls: [URL]?) -> [String] {
        (urls ?? []).map(\.lastPathComponent)
    }

    // MARK: - extends

    /// The case the issue names: a config that says nothing but `extends` used to yield no directories
    /// at all, so discovery silently fell back to probing for `src/`.
    @Test func aConfigThatOnlyExtendsABaseInheritsItsDirectories() throws {
        try withTempDir { root in
            try write("tsconfig.base.json", in: root, contents: #"{"include": ["lib"]}"#)
            try write("tsconfig.json", in: root, contents: #"{"extends": "./tsconfig.base.json"}"#)
            try write("lib/a.ts", in: root)

            let reader = TypeScriptProjectReader(notAbove: root)
            #expect(dirNames(reader.sourceDirs(ofProjectIn: root)) == ["lib"])
            #expect(reader.diagnostics.isEmpty)
        }
    }

    @Test func theNearestFileWinsFieldByField() throws {
        try withTempDir { root in
            try write("base.json", in: root, contents: """
            {"compilerOptions": {"rootDir": "inherited"}, "include": ["ignored"]}
            """)
            try write("tsconfig.json", in: root, contents: #"{"extends": "./base.json", "include": ["own"]}"#)
            try write("inherited/a.ts", in: root)
            try write("own/b.ts", in: root)
            try write("ignored/c.ts", in: root)

            let reader = TypeScriptProjectReader(notAbove: root)
            // `rootDir` is inherited because the near file is silent on it; `include` is replaced outright.
            #expect(dirNames(reader.sourceDirs(ofProjectIn: root)) == ["inherited", "own"])
        }
    }

    /// `tsc` resolves a relative path against the file it was written in, so a base one folder down
    /// keeps pointing at its own neighbour.
    @Test func anInheritedPathResolvesAgainstTheFileThatDeclaredIt() throws {
        try withTempDir { root in
            try write("config/base.json", in: root, contents: #"{"include": ["../shared"]}"#)
            try write("tsconfig.json", in: root, contents: #"{"extends": "./config/base.json"}"#)
            try write("shared/a.ts", in: root)

            let reader = TypeScriptProjectReader(notAbove: root)
            let dirs = try #require(reader.sourceDirs(ofProjectIn: root))
            #expect(dirs.map(\.path) == [root.appendingPathComponent("shared").path])
        }
    }

    @Test func extendsResolvesAPathWithoutItsExtension() throws {
        try withTempDir { root in
            try write("tsconfig.base.json", in: root, contents: #"{"include": ["lib"]}"#)
            try write("tsconfig.json", in: root, contents: #"{"extends": "./tsconfig.base"}"#)
            try write("lib/a.ts", in: root)

            let reader = TypeScriptProjectReader(notAbove: root)
            #expect(dirNames(reader.sourceDirs(ofProjectIn: root)) == ["lib"])
        }
    }

    @Test func extendsResolvesADirectoryToItsOwnConfig() throws {
        try withTempDir { root in
            try write("configs/tsconfig.json", in: root, contents: #"{"include": ["../lib"]}"#)
            try write("tsconfig.json", in: root, contents: #"{"extends": "./configs"}"#)
            try write("lib/a.ts", in: root)

            let reader = TypeScriptProjectReader(notAbove: root)
            #expect(dirNames(reader.sourceDirs(ofProjectIn: root)) == ["lib"])
        }
    }

    /// A bare name is a package, looked up in `node_modules` from the referring file upwards — which is
    /// how a workspace package reaches a base installed at the monorepo root.
    @Test func extendsResolvesAPackageReferenceFromNodeModulesAbove() throws {
        try withTempDir { root in
            try write("node_modules/@tsconfig/node20/tsconfig.json", in: root, contents: """
            {"compilerOptions": {"rootDir": "../../../src"}}
            """)
            try write("packages/app/tsconfig.json", in: root, contents: """
            {"extends": "@tsconfig/node20/tsconfig.json"}
            """)
            try write("src/a.ts", in: root)

            let reader = TypeScriptProjectReader(notAbove: root)
            let dirs = try #require(reader.sourceDirs(ofProjectIn: root.appendingPathComponent("packages/app")))
            #expect(dirs.map(\.path) == [root.appendingPathComponent("src").path])
        }
    }

    @Test func aPackageReferenceIsNotSearchedAboveTheProjectRoot() throws {
        try withTempDir { root in
            let project = root.appendingPathComponent("project")
            try write("node_modules/base/tsconfig.json", in: root, contents: #"{"include": ["x"]}"#)
            try write("project/tsconfig.json", in: root, contents: #"{"extends": "base"}"#)

            let reader = TypeScriptProjectReader(notAbove: project)
            #expect(reader.sourceDirs(ofProjectIn: project) == nil)
        }
    }

    @Test func theLastEntryOfAnExtendsArrayWins() throws {
        try withTempDir { root in
            try write("first.json", in: root, contents: #"{"include": ["first"]}"#)
            try write("second.json", in: root, contents: #"{"include": ["second"]}"#)
            try write("tsconfig.json", in: root, contents: """
            {"extends": ["./first.json", "./second.json"]}
            """)
            try write("first/a.ts", in: root)
            try write("second/b.ts", in: root)

            let reader = TypeScriptProjectReader(notAbove: root)
            #expect(dirNames(reader.sourceDirs(ofProjectIn: root)) == ["second"])
        }
    }

    // MARK: - references

    @Test func referencesContributeEachProjectsOwnDirectories() throws {
        try withTempDir { root in
            try write("tsconfig.json", in: root, contents: """
            {"references": [{"path": "./packages/core"}, {"path": "./packages/ui"}]}
            """)
            try write("packages/core/tsconfig.json", in: root, contents: #"{"include": ["src"]}"#)
            try write("packages/ui/tsconfig.json", in: root, contents: #"{"include": ["src"]}"#)
            try write("packages/core/src/a.ts", in: root)
            try write("packages/ui/src/b.ts", in: root)

            let reader = TypeScriptProjectReader(notAbove: root)
            let dirs = try #require(reader.sourceDirs(ofProjectIn: root))
            #expect(dirs.map { $0.pathComponents.suffix(3).joined(separator: "/") }
                == ["packages/core/src", "packages/ui/src"])
            #expect(reader.diagnostics.isEmpty)
        }
    }

    /// Two projects referencing one shared project is a diamond, not a cycle: it contributes once and
    /// records nothing.
    @Test func aSharedReferenceIsNotACycle() throws {
        try withTempDir { root in
            try write("tsconfig.json", in: root, contents: """
            {"references": [{"path": "./a"}, {"path": "./b"}]}
            """)
            try write("a/tsconfig.json", in: root, contents: """
            {"include": ["src"], "references": [{"path": "../shared"}]}
            """)
            try write("b/tsconfig.json", in: root, contents: """
            {"include": ["src"], "references": [{"path": "../shared"}]}
            """)
            try write("shared/tsconfig.json", in: root, contents: #"{"include": ["src"]}"#)
            for package in ["a", "b", "shared"] { try write("\(package)/src/x.ts", in: root) }

            let reader = TypeScriptProjectReader(notAbove: root)
            let dirs = try #require(reader.sourceDirs(ofProjectIn: root))
            #expect(dirs.map { $0.pathComponents.suffix(2).joined(separator: "/") }
                == ["a/src", "shared/src", "b/src"])
            #expect(reader.diagnostics.isEmpty)
        }
    }

    // MARK: - Cycles

    @Test func anExtendsCycleEndsWithADiagnostic() throws {
        try withTempDir { root in
            try write("tsconfig.json", in: root, contents: """
            {"extends": "./a.json", "include": ["src"]}
            """)
            try write("a.json", in: root, contents: #"{"extends": "./b.json"}"#)
            try write("b.json", in: root, contents: #"{"extends": "./a.json"}"#)
            try write("src/x.ts", in: root)

            let reader = TypeScriptProjectReader(notAbove: root)
            #expect(dirNames(reader.sourceDirs(ofProjectIn: root)) == ["src"])
            #expect(reader.diagnostics.map(\.kind) == [.incompleteDiscovery])
            #expect(reader.diagnostics.first?.location.filePath == "a.json")
            #expect(reader.diagnostics.first?.message.contains("`extends`") == true)
        }
    }

    @Test func aSelfExtendingConfigEndsWithADiagnostic() throws {
        try withTempDir { root in
            try write("tsconfig.json", in: root, contents: #"{"extends": "./tsconfig.json"}"#)

            let reader = TypeScriptProjectReader(notAbove: root)
            #expect(reader.sourceDirs(ofProjectIn: root) == nil)
            #expect(reader.diagnostics.map(\.kind) == [.incompleteDiscovery])
        }
    }

    @Test func aReferencesCycleEndsWithADiagnostic() throws {
        try withTempDir { root in
            try write("tsconfig.json", in: root, contents: """
            {"include": ["src"], "references": [{"path": "./a"}]}
            """)
            try write("a/tsconfig.json", in: root, contents: """
            {"include": ["src"], "references": [{"path": ".."}]}
            """)
            try write("src/x.ts", in: root)
            try write("a/src/y.ts", in: root)

            let reader = TypeScriptProjectReader(notAbove: root)
            let dirs = try #require(reader.sourceDirs(ofProjectIn: root))
            #expect(dirs.map { $0.pathComponents.suffix(2).joined(separator: "/") }
                == ["\(root.lastPathComponent)/src", "a/src"])
            #expect(reader.diagnostics.map(\.kind) == [.incompleteDiscovery])
            #expect(reader.diagnostics.first?.message.contains("`references`") == true)
        }
    }

    // MARK: - Absence

    @Test func noConfigMeansNothingToGoOn() throws {
        try withTempDir { root in
            let reader = TypeScriptProjectReader(notAbove: root)
            #expect(reader.sourceDirs(ofProjectIn: root) == nil)
            try write("tsconfig.json", in: root, contents: "{}")
            let withEmptyConfig = TypeScriptProjectReader(notAbove: root)
            #expect(withEmptyConfig.sourceDirs(ofProjectIn: root) == nil)
            try write("tsconfig.json", in: root, contents: "not json at all")
            let withBrokenConfig = TypeScriptProjectReader(notAbove: root)
            #expect(withBrokenConfig.sourceDirs(ofProjectIn: root) == nil)
        }
    }

    /// `include: ["**/*.ts"]` names no directory of its own, so it means the config's own folder.
    @Test func aPatternStartingWithAWildcardMeansTheConfigsOwnFolder() throws {
        try withTempDir { root in
            try write("app/tsconfig.json", in: root, contents: #"{"include": ["**/*.ts"]}"#)
            try write("app/a.ts", in: root)

            let reader = TypeScriptProjectReader(notAbove: root)
            let dirs = try #require(reader.sourceDirs(ofProjectIn: root.appendingPathComponent("app")))
            #expect(dirs.map(\.path) == [root.appendingPathComponent("app").path])
        }
    }

    /// A directory the config names but that does not exist must not reach the file collector.
    @Test func aDeclaredDirectoryThatIsMissingIsDropped() throws {
        try withTempDir { root in
            try write("tsconfig.json", in: root, contents: #"{"include": ["src", "gone"]}"#)
            try write("src/a.ts", in: root)

            let reader = TypeScriptProjectReader(notAbove: root)
            #expect(dirNames(reader.sourceDirs(ofProjectIn: root)) == ["src"])
        }
    }

    // MARK: - JSONC

    /// What `tsc --init` writes: comments throughout and a trailing comma. Rejecting it used to lose
    /// the file silently, and in an `extends` chain the base's `include` went with it.
    @Test func aCommentedConfigIsReadLikeTscReadsIt() throws {
        try withTempDir { root in
            try write("tsconfig.base.json", in: root, contents: """
            {
              // Where the sources live.
              "include": ["lib",],
            }
            """)
            try write("tsconfig.json", in: root, contents: """
            {
              /* Inherit everything. */
              "extends": "./tsconfig.base.json" // and add nothing
            }
            """)
            try write("lib/a.ts", in: root)

            let reader = TypeScriptProjectReader(notAbove: root)
            #expect(dirNames(reader.sourceDirs(ofProjectIn: root)) == ["lib"])
            #expect(reader.diagnostics.isEmpty)
        }
    }

    /// Present but unparseable is not the same as absent: the first is a configured layout nobody
    /// read, and it says so rather than passing for a package that configures nothing.
    @Test func aConfigThatWillNotParseIsReported() throws {
        try withTempDir { root in
            try write("tsconfig.json", in: root, contents: "<<<<<<< HEAD\n{}\n=======\n{}\n>>>>>>> x")
            try write("src/a.ts", in: root)

            let reader = TypeScriptProjectReader(notAbove: root)
            #expect(reader.sourceDirs(ofProjectIn: root) == nil)
            #expect(reader.diagnostics.map(\.kind) == [.incompleteDiscovery])
            #expect(reader.diagnostics.first?.message.contains("tsconfig.json") == true)
        }
    }

    // MARK: - extends that resolves to nothing

    /// A base hoisted into a `node_modules` above the analysed folder resolves to nothing from inside
    /// it. The directories it declares are missing from the merge, which is worth saying out loud.
    @Test func anExtendsThatResolvesToNothingIsReported() throws {
        try withTempDir { root in
            let project = root.appendingPathComponent("project")
            try write("node_modules/@tsconfig/node20/tsconfig.json", in: root, contents: #"{"include": ["x"]}"#)
            try write("project/tsconfig.json", in: root, contents: """
            {"extends": "@tsconfig/node20", "include": ["src"]}
            """)
            try write("project/src/a.ts", in: root)

            let reader = TypeScriptProjectReader(notAbove: project)
            #expect(dirNames(reader.sourceDirs(ofProjectIn: project)) == ["src"])
            #expect(reader.diagnostics.map(\.kind) == [.incompleteDiscovery])
            #expect(reader.diagnostics.first?.message.contains("@tsconfig/node20") == true)
        }
    }

    /// The base is inside the analysed folder, so there is nothing to report.
    @Test func anExtendsThatResolvesRecordsNothing() throws {
        try withTempDir { root in
            try write("node_modules/base/tsconfig.json", in: root, contents: #"{"include": ["../../lib"]}"#)
            try write("tsconfig.json", in: root, contents: #"{"extends": "base"}"#)
            try write("lib/a.ts", in: root)

            let reader = TypeScriptProjectReader(notAbove: root)
            #expect(dirNames(reader.sourceDirs(ofProjectIn: root)) == ["lib"])
            #expect(reader.diagnostics.isEmpty)
        }
    }
}
