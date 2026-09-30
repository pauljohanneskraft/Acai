import Foundation
import AcaiCore

public struct JVMBuildSystemDetector: BuildSystemDetector {

    public let indicatorFiles: [String]

    /// The settings files whose `include` list defines the module set. Empty for a build system that has
    /// no such file — Maven's modules are still found by scanning the tree.
    public let settingsFiles: [String]

    public init(indicatorFiles: [String], settingsFiles: [String] = []) {
        self.indicatorFiles = indicatorFiles
        self.settingsFiles = settingsFiles
    }

    public static let gradle = JVMBuildSystemDetector(
        indicatorFiles: [
            "build.gradle", "build.gradle.kts", "settings.gradle", "settings.gradle.kts"
        ],
        settingsFiles: ["settings.gradle", "settings.gradle.kts"])

    public static let maven = JVMBuildSystemDetector(indicatorFiles: ["pom.xml"])

    public func isPresent(at root: URL) -> Bool {
        IndicatorFiles(indicatorFiles).present(at: root)
    }

    public func discoverSourceSpecs(
        at root: URL,
        requestedLanguages: [CodeArtifact.SourceLanguage]
    ) -> [SourceSpec] {
        let request = LanguageRequest(requestedLanguages)
        let modules = modules(in: root)
        var specs: [SourceSpec] = []

        if request.wants(.kotlin) {
            specs += spec(
                .kotlin, in: modules.flatMap(\.kotlinSourceDirectories), extensions: ["kt", "kts"],
                looseSourcesAt: root)
        }
        if request.wants(.java) {
            specs += spec(
                .java, in: modules.flatMap(\.javaSourceDirectories), extensions: ["java"],
                looseSourcesAt: root)
        }

        return specs
    }

    /// The module source sets when there are any, else the root itself when it holds loose sources.
    private func spec(
        _ language: CodeArtifact.SourceLanguage,
        in sourceDirs: [URL],
        extensions: Set<String>,
        looseSourcesAt root: URL
    ) -> [SourceSpec] {
        guard sourceDirs.isEmpty else {
            return [SourceSpec(
                language: language,
                sourceDirs: sourceDirs.removingDuplicates { $0.standardizedFileURL.path })]
        }
        let presence = SourceFilePresence(
            extensions: extensions, excludingDirectories: jvmExcludedDirectories)
        guard presence.exist(in: root) else { return [] }
        return [SourceSpec(language: language, sourceDirs: [root])]
    }

    /// The root project plus every module its settings file includes; only when there is no settings
    /// file does the directory scan stand in for one.
    private func modules(in root: URL) -> [GradleModule] {
        let directories = settings(at: root)
            .map { [root] + $0.moduleDirectories(relativeTo: root) }
            ?? scannedModuleDirectories(in: root)
        return directories.map { GradleModule(directory: $0) }
    }

    private func settings(at root: URL) -> GradleSettings? {
        settingsFiles
            .lazy
            .compactMap { try? String(contentsOf: root.appending(path: $0), encoding: .utf8) }
            .first
            .map { GradleSettings(source: $0) }
    }

    /// Every directory carrying an indicator file — the best a build system that does not list its
    /// modules allows. Sorted, because the filesystem's own order varies by machine.
    private func scannedModuleDirectories(in root: URL) -> [URL] {
        let indicator = IndicatorFiles(indicatorFiles)
        var directories: [URL] = []
        var pending: [URL] = [root]
        while let directory = pending.popLast() {
            directories.append(directory)
            let entries = (try? FileManager.default.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles])) ?? []
            for entry in entries where !jvmExcludedDirectories.contains(entry.lastPathComponent) {
                guard (try? entry.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true,
                      indicator.present(at: entry) else { continue }
                pending.append(entry)
            }
        }
        return directories.sorted { $0.path < $1.path }
    }
}
