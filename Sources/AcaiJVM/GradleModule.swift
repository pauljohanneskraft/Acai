import Foundation
import AcaiCore

/// One JVM module's directory, and the source sets compiled from it.
struct GradleModule {

    let directory: URL

    /// `src/main/kotlin`, every `src/<target>Main/kotlin`, and any declared `srcDir` holding Kotlin.
    var kotlinSourceDirectories: [URL] {
        conventionalSourceDirectory(named: "kotlin")
            + multiplatformSourceDirectories
            + declaredSourceDirectories(containing: ["kt"])
    }

    /// `src/main/java`, and any declared `srcDir` holding Java.
    var javaSourceDirectories: [URL] {
        conventionalSourceDirectory(named: "java")
            + declaredSourceDirectories(containing: ["java"])
    }

    private var sourceRoot: URL {
        directory.appending(path: "src")
    }

    private func conventionalSourceDirectory(named name: String) -> [URL] {
        existing([sourceRoot.appending(path: "main").appending(path: name)])
    }

    /// Kotlin Multiplatform names one source set per target — `commonMain`, `jvmMain`, `androidMain`
    /// and any custom one — so the targets are read off the tree rather than enumerated here. Test
    /// source sets are `…Test` and so are never matched.
    private var multiplatformSourceDirectories: [URL] {
        let entries = (try? FileManager.default.contentsOfDirectory(
            at: sourceRoot, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
        return existing(
            entries
                .filter { $0.lastPathComponent.hasSuffix("Main") }
                .map { $0.appending(path: "kotlin") }
                .sorted { $0.path < $1.path })
    }

    /// Which language a declared `srcDir` holds is decided by the files in it, so a `srcDir` under a
    /// `java` block and one under a `kotlin` block are read the same way.
    private func declaredSourceDirectories(containing extensions: Set<String>) -> [URL] {
        let presence = SourceFilePresence(
            extensions: extensions, excludingDirectories: jvmExcludedDirectories)
        return existing(sourceDirectoriesDeclaredInBuildScript).filter { presence.exist(in: $0) }
    }

    /// Directories a `sourceSets` block names with a string-literal `srcDir` or `srcDirs`.
    private var sourceDirectoriesDeclaredInBuildScript: [URL] {
        guard let source = buildScriptSource else { return [] }
        return GradleScript(source: source)
            .blocks(named: "sourceSets")
            .flatMap { block in
                (block.statements(after: "srcDir") + block.statements(after: "srcDirs"))
                    .flatMap(\.quotedLiterals)
            }
            .map { directory.appending(path: $0) }
            .removingDuplicates { $0.standardizedFileURL.path }
    }

    private var buildScriptSource: String? {
        ["build.gradle.kts", "build.gradle"]
            .lazy
            .compactMap { try? String(contentsOf: directory.appending(path: $0), encoding: .utf8) }
            .first
    }

    private func existing(_ directories: [URL]) -> [URL] {
        directories.filter { FileManager.default.fileExists(atPath: $0.path) }
    }
}
