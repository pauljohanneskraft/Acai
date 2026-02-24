import Foundation

public enum UMLConstants {
    public static let analysisDirectory =
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".uml")
            .appendingPathComponent("analysis")
    
    public static let defaultExcludedSourceDirectories: Set<String> = [
        "node_modules", ".build", "build", "Pods", ".git",
        "DerivedData", "target", "bin", "obj",
    ]
}
