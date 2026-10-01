import Foundation
import AcaiCore

/// One JVM module's directory, and the source sets compiled from it.
struct GradleModule {

    let directory: URL
    let excludedDirectories: Set<String>

    /// Every main source set's `kotlin` directory, every one of its `java` directories that holds
    /// Kotlin — Android's Gradle plugin compiles Kotlin straight out of `src/main/java` — and any
    /// declared `srcDir` holding Kotlin.
    var kotlinSourceDirectories: [URL] {
        conventionalSourceDirectories(named: "kotlin")
            + conventionalSourceDirectories(named: "java").filter { holds(["kt"], in: $0) }
            + declaredSourceDirectories(holding: ["kt"])
    }

    /// Every main source set's `java` directory, and any declared `srcDir` holding Java.
    var javaSourceDirectories: [URL] {
        conventionalSourceDirectories(named: "java")
            + declaredSourceDirectories(holding: ["java"])
    }

    private var sourceRoot: URL {
        directory.appending(path: "src")
    }

    /// `src/main` and every `src/<target>Main` — Kotlin Multiplatform names one source set per target,
    /// `commonMain`, `jvmMain`, `androidMain` or a custom one, so the targets are read off the tree
    /// rather than enumerated here. Test source sets are `…Test` and so are never among them.
    private var mainSourceSetRoots: [URL] {
        let entries = (try? FileManager.default.contentsOfDirectory(
            at: sourceRoot, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
        return [sourceRoot.appending(path: "main")]
            + entries.filter { $0.lastPathComponent.hasSuffix("Main") }.sorted { $0.path < $1.path }
    }

    private func conventionalSourceDirectories(named name: String) -> [URL] {
        existing(mainSourceSetRoots.map { $0.appending(path: name) })
    }

    /// Which language a declared `srcDir` holds is decided by the files in it, so a `srcDir` under a
    /// `java` block and one under a `kotlin` block are read the same way.
    private func declaredSourceDirectories(holding extensions: Set<String>) -> [URL] {
        existing(sourceDirectoriesDeclaredInBuildScript).filter { holds(extensions, in: $0) }
    }

    /// Directories a `sourceSets` block names with a string-literal `srcDir` or `srcDirs`, less those
    /// a test source set declares — tests are out of scope here exactly as they are for `…Main`.
    private var sourceDirectoriesDeclaredInBuildScript: [URL] {
        guard let source = buildScriptSource else { return [] }
        let blocks = GradleScript(source: source).blocks(named: "sourceSets")
        let declaredByTests = Set(blocks.flatMap { block in
            block.labelledBlocks
                .filter { $0.label.namesTestSourceSet }
                .flatMap { declaredPaths(in: $0.body) }
        })
        return blocks
            .flatMap(declaredPaths)
            .filter { !declaredByTests.contains($0) }
            .map { directory.appending(path: $0) }
            .removingDuplicates { $0.standardizedFileURL.path }
    }

    private func declaredPaths(in script: GradleScript) -> [String] {
        (script.statements(after: "srcDir") + script.statements(after: "srcDirs"))
            .flatMap(\.quotedLiterals)
    }

    private var buildScriptSource: String? {
        ["build.gradle.kts", "build.gradle"]
            .lazy
            .compactMap { try? String(contentsOf: directory.appending(path: $0), encoding: .utf8) }
            .first
    }

    private func holds(_ extensions: Set<String>, in directory: URL) -> Bool {
        SourceFilePresence(extensions: extensions, excludingDirectories: excludedDirectories)
            .exist(in: directory)
    }

    private func existing(_ directories: [URL]) -> [URL] {
        directories.filter { FileManager.default.fileExists(atPath: $0.path) }
    }
}

private extension String {

    /// Whether this is the text opening a test source set's block: `test`, `integrationTest`,
    /// `val commonTest by getting` and `getByName("test")` all name one, `latest` does not.
    var namesTestSourceSet: Bool {
        split(whereSeparator: { !$0.isLetter && !$0.isNumber && $0 != "_" })
            .contains { $0.lowercased() == "test" || $0.hasSuffix("Test") }
    }
}
