import Foundation

public enum UMLConstants {
    private static let baseDirectory: URL = {
        #if os(macOS)
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".uml")
        #else
        // swiftlint:disable:next force_try
        try! FileManager.default.url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
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
}
