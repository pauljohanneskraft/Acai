import Foundation
import Testing
import AcaiCore
@testable import AcaiJVM

/// Gradle's module set comes from `settings.gradle`, not from whatever carries a build file on disk:
/// a module nothing includes is not Gradle's to build, and a module whose `projectDir` is redirected
/// is not where its path suggests. These also cover the source sets probed per module — Kotlin
/// Multiplatform's per-target sets and a `sourceSets` block's own `srcDir`.
@Suite("Gradle module discovery", .timeLimit(.minutes(1)))
struct GradleModuleDiscoveryTests {

    // MARK: - Fixture helpers

    private func withTempDir(_ body: (URL) throws -> Void) throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("gradle-discovery-\(UUID().uuidString)", isDirectory: true)
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

    /// A conventional Kotlin module: its own build file and one source file under `src/main/kotlin`.
    private func writeKotlinModule(_ path: String, in root: URL) throws {
        try write("\(path)/build.gradle.kts", in: root)
        try write("\(path)/src/main/kotlin/Sample.kt", in: root, contents: "class Sample")
    }

    /// Source dirs of the spec for `language`, as paths relative to `root` so assertions do not depend
    /// on the temporary directory or on which module a `kotlin` directory belongs to.
    private func sourceDirs(
        _ specs: [SourceSpec],
        for language: CodeArtifact.SourceLanguage,
        relativeTo root: URL
    ) -> [String] {
        let prefix = root.standardizedFileURL.path
        return (specs.first { $0.language == language }?.sourceDirs ?? [])
            .map(\.standardizedFileURL.path)
            .map { $0 == prefix ? "." : String($0.dropFirst(prefix.count + 1)) }
            .sorted()
    }

    private func kotlinDirs(in root: URL) -> [String] {
        let specs = JVMBuildSystemDetector.gradle.discoverSourceSpecs(at: root, requestedLanguages: [])
        return sourceDirs(specs, for: .kotlin, relativeTo: root)
    }

    // MARK: - The module set comes from the settings file

    @Test func settingsFileDecidesWhichOnDiskModulesAreAnalysed() throws {
        try withTempDir { root in
            try write("settings.gradle.kts", in: root, contents: #"include(":app", ":core")"#)
            for module in ["app", "core", "legacy"] {
                try writeKotlinModule(module, in: root)
            }

            #expect(kotlinDirs(in: root) == ["app/src/main/kotlin", "core/src/main/kotlin"])
        }
    }

    @Test func theDirectoryScanStandsInOnlyWhenThereIsNoSettingsFile() throws {
        try withTempDir { root in
            try write("build.gradle.kts", in: root)
            for module in ["app", "core", "legacy"] {
                try writeKotlinModule(module, in: root)
            }

            #expect(kotlinDirs(in: root) == [
                "app/src/main/kotlin", "core/src/main/kotlin", "legacy/src/main/kotlin"
            ])
        }
    }

    @Test func aGroovySettingsFileIsReadTheSameWay() throws {
        try withTempDir { root in
            try write("settings.gradle", in: root, contents: "include ':app', ':core'\n")
            for module in ["app", "core", "legacy"] {
                try writeKotlinModule(module, in: root)
            }

            #expect(kotlinDirs(in: root) == ["app/src/main/kotlin", "core/src/main/kotlin"])
        }
    }

    @Test func aModulePathWithoutALeadingColonNamesTheSameModule() throws {
        try withTempDir { root in
            try write("settings.gradle.kts", in: root, contents: #"include("app")"#)
            try writeKotlinModule("app", in: root)

            #expect(kotlinDirs(in: root) == ["app/src/main/kotlin"])
        }
    }

    @Test func aNestedModulePathBecomesANestedDirectory() throws {
        try withTempDir { root in
            try write("settings.gradle.kts", in: root, contents: #"include(":core:api")"#)
            try writeKotlinModule("core/api", in: root)

            #expect(kotlinDirs(in: root) == ["core/api/src/main/kotlin"])
        }
    }

    @Test func aCommentedOutIncludeNamesNoModule() throws {
        try withTempDir { root in
            try write("settings.gradle.kts", in: root, contents: """
                include(":app")
                // include(":legacy")
                /* include(":archived") */
                """)
            for module in ["app", "legacy", "archived"] {
                try writeKotlinModule(module, in: root)
            }

            #expect(kotlinDirs(in: root) == ["app/src/main/kotlin"])
        }
    }

    @Test func includeBuildIsACompositeBuildRatherThanAModule() throws {
        try withTempDir { root in
            try write("settings.gradle.kts", in: root, contents: """
                includeBuild("shared")
                include(":app")
                """)
            try writeKotlinModule("app", in: root)
            try writeKotlinModule("shared", in: root)

            #expect(kotlinDirs(in: root) == ["app/src/main/kotlin"])
        }
    }

    // MARK: - projectDir redirects

    @Test func aRedirectedProjectDirIsFollowed() throws {
        try withTempDir { root in
            try write("settings.gradle.kts", in: root, contents: """
                include(":core")
                project(":core").projectDir = file("lib/core")
                """)
            try writeKotlinModule("lib/core", in: root)

            #expect(kotlinDirs(in: root) == ["lib/core/src/main/kotlin"])
        }
    }

    @Test func aRedirectAppliesToTheModulesBeneathIt() throws {
        try withTempDir { root in
            try write("settings.gradle", in: root, contents: """
                include ':core', ':core:api'
                project(':core').projectDir = file('lib/core')
                """)
            try writeKotlinModule("lib/core", in: root)
            try writeKotlinModule("lib/core/api", in: root)

            #expect(kotlinDirs(in: root) == [
                "lib/core/api/src/main/kotlin", "lib/core/src/main/kotlin"
            ])
        }
    }

    // MARK: - Source sets

    @Test func multiplatformTargetSourceSetsAreFound() throws {
        try withTempDir { root in
            try write("settings.gradle.kts", in: root, contents: #"include(":shared")"#)
            try write("shared/build.gradle.kts", in: root)
            for sourceSet in ["commonMain", "jvmMain", "androidMain", "commonTest"] {
                try write("shared/src/\(sourceSet)/kotlin/Sample.kt", in: root, contents: "class Sample")
            }

            #expect(kotlinDirs(in: root) == [
                "shared/src/androidMain/kotlin",
                "shared/src/commonMain/kotlin",
                "shared/src/jvmMain/kotlin"
            ])
        }
    }

    @Test func aSourceSetsBlockDeclaringASrcDirIsProbed() throws {
        try withTempDir { root in
            try write("settings.gradle.kts", in: root, contents: #"include(":app")"#)
            try write("app/build.gradle.kts", in: root, contents: """
                sourceSets {
                    main {
                        java { srcDir("src/main/generated") }
                    }
                }
                """)
            try write("app/src/main/generated/Generated.java", in: root, contents: "class Generated {}")
            try write("app/src/main/kotlin/Sample.kt", in: root, contents: "class Sample")

            let specs = JVMBuildSystemDetector.gradle.discoverSourceSpecs(at: root, requestedLanguages: [])
            #expect(sourceDirs(specs, for: .java, relativeTo: root) == ["app/src/main/generated"])
            #expect(sourceDirs(specs, for: .kotlin, relativeTo: root) == ["app/src/main/kotlin"])
        }
    }

    @Test func aSrcDirOutsideASourceSetsBlockIsNotASourceSet() throws {
        try withTempDir { root in
            try write("settings.gradle.kts", in: root, contents: #"include(":app")"#)
            try write("app/build.gradle.kts", in: root, contents: #"tasks.register("x") { srcDir("extra") }"#)
            try write("app/extra/Stray.kt", in: root, contents: "class Stray")
            try write("app/src/main/kotlin/Sample.kt", in: root, contents: "class Sample")

            #expect(kotlinDirs(in: root) == ["app/src/main/kotlin"])
        }
    }

    // MARK: - Excluded directories

    @Test func aBuildOutputDirectoryIsNeverScannedForModules() throws {
        try withTempDir { root in
            try write("build.gradle.kts", in: root)
            try writeKotlinModule("build/generated-module", in: root)
            try write("src/main/kotlin/Sample.kt", in: root, contents: "class Sample")

            #expect(kotlinDirs(in: root) == ["src/main/kotlin"])
        }
    }
}
