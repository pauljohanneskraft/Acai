import Foundation

/// Process-wide configuration values. A value you read from `.standard` (the configured instance),
/// rather than a caseless-enum namespace — so it can be substituted in tests and isn't a bag of
/// global statics.
public struct UMLConstants: Sendable {
    /// The shared configuration used throughout the tool.
    public static let standard = UMLConstants()

    public init() {}

    /// The tool's base directory for stored state.
    private var baseDirectory: URL {
        #if os(macOS)
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".uml")
        #else
        (try? FileManager.default.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? FileManager.default.temporaryDirectory.appendingPathComponent("uml", isDirectory: true)
        #endif
    }

    /// Where stored analyses live.
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
