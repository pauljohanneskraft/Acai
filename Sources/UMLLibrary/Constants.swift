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

    public static let defaultExcludedSourceDirectories: Set<String> = [
        "node_modules", ".build", "build", "Pods", ".git",
        "DerivedData", "target", "bin", "obj"
    ]
}
