import Foundation
import AcaiCore

/// Detects JVM build systems (Gradle and Maven) and locates Kotlin / Java source directories.
///
/// A single type parameterised by the indicator files it looks for, so that Gradle
/// and Maven detection share one implementation instead of two identical structs.
public struct JVMBuildSystemDetector: BuildSystemDetector {

    /// File names (relative to the project root) whose presence signals this build system.
    public let indicatorFiles: [String]

    private static let excludedDirs: Set<String> = [
        "build", ".gradle", ".build", "node_modules", ".git", "target", ".idea"
    ]

    public init(indicatorFiles: [String]) {
        self.indicatorFiles = indicatorFiles
    }

    /// Preset for Gradle projects.
    public static let gradle = JVMBuildSystemDetector(indicatorFiles: [
        "build.gradle", "build.gradle.kts", "settings.gradle", "settings.gradle.kts"
    ])

    /// Preset for Maven projects.
    public static let maven = JVMBuildSystemDetector(indicatorFiles: ["pom.xml"])

    public func isPresent(at root: URL) -> Bool {
        IndicatorFiles(indicatorFiles).present(at: root)
    }

    public func discoverSourceSpecs(
        at root: URL,
        requestedLanguages: [CodeArtifact.SourceLanguage]
    ) -> [SourceSpec] {
        let request = LanguageRequest(requestedLanguages)
        let (kotlinDirs, javaDirs) = findSourceDirs(in: root)
        var specs: [SourceSpec] = []

        if !kotlinDirs.isEmpty, request.wants(.kotlin) {
            specs.append(SourceSpec(language: .kotlin, sourceDirs: kotlinDirs))
        } else if request.wants(.kotlin), SourceFilePresence(extensions: ["kt", "kts"]).exist(in: root) {
            specs.append(SourceSpec(language: .kotlin, sourceDirs: [root]))
        }

        if !javaDirs.isEmpty, request.wants(.java) {
            specs.append(SourceSpec(language: .java, sourceDirs: javaDirs))
        } else if request.wants(.java), SourceFilePresence(extensions: ["java"]).exist(in: root) {
            specs.append(SourceSpec(language: .java, sourceDirs: [root]))
        }

        return specs
    }

    private func findSourceDirs(in root: URL) -> (kotlin: [URL], java: [URL]) {
        let fileManager = FileManager.default
        let indicator = IndicatorFiles(indicatorFiles)
        var kotlinDirs: [URL] = []
        var javaDirs: [URL] = []

        func probe(_ dir: URL) {
            let kotlinSrc = dir.appendingPathComponent("src/main/kotlin")
            let javaSrc   = dir.appendingPathComponent("src/main/java")
            if fileManager.fileExists(atPath: kotlinSrc.path) { kotlinDirs.append(kotlinSrc) }
            if fileManager.fileExists(atPath: javaSrc.path) { javaDirs.append(javaSrc) }

            guard let entries = try? fileManager.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]
            ) else { return }

            for entry in entries {
                guard !Self.excludedDirs.contains(entry.lastPathComponent) else { continue }
                guard (try? entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }
                if indicator.present(at: entry) {
                    probe(entry)
                }
            }
        }

        probe(root)

        return (kotlinDirs.removingDuplicates { $0 }, javaDirs.removingDuplicates { $0 })
    }
}
