import Foundation

public enum UMLConstants {
    private static let baseDirectory: URL = {
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
    }()

    public static let analysisDirectory =
        baseDirectory
            .appendingPathComponent("analysis")

    /// Directories skipped while collecting sources regardless of language. Only the universal
    /// version-control directory lives here; each language's build-output/dependency directories
    /// (`node_modules`, `Pods`, `target`, …) come from its `LanguageConfiguration.excludedDirectories`
    /// and are unioned in by the composition root.
    public static let defaultExcludedSourceDirectories: Set<String> = [".git"]

    /// Schema/tool version stamped into every analyzed `CodeArtifact`'s metadata. Bump when the
    /// stored `CodeArtifact` JSON shape changes in a way consumers need to detect.
    public static let toolVersion = "1.0.0"
}
