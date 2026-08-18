import Foundation

public struct AcaiConstants: Sendable {
    public static let standard = AcaiConstants()

    public init() {}

    private var baseDirectory: URL {
        #if os(macOS)
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".acai")
        #else
        (try? FileManager.default.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? FileManager.default.temporaryDirectory.appendingPathComponent("acai", isDirectory: true)
        #endif
    }

    public var analysisDirectory: URL {
        baseDirectory.appendingPathComponent("analysis")
    }

    /// Directories skipped while collecting sources regardless of language. Only the universal
    /// version-control directory lives here; each language's build-output/dependency directories
    /// (`node_modules`, `Pods`, `target`, …) come from its `LanguageConfiguration.excludedDirectories`
    /// and are unioned in by the composition root.
    public let defaultExcludedSourceDirectories: Set<String> = [".git"]

    /// Schema/tool version stamped into every analyzed `CodeArtifact`'s metadata. Bump when the
    /// stored `CodeArtifact` JSON shape changes in a way consumers need to detect.
    public let toolVersion = "1.0.0"
}
