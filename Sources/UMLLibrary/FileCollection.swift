import Foundation

extension FileManager {
    func fileURLs(
        in directory: URL,
        withExtensions extensions: Set<String>,
        excludingDirectories excludedDirectories: Set<String> = UMLConstants.defaultExcludedSourceDirectories
    ) -> [URL] {
        var result: [URL] = []
        guard let enumerator = enumerator(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey, .nameKey],
            options: [.skipsHiddenFiles]
        ) else { return result }

        for case let fileURL as URL in enumerator {
            if let isDir = try? fileURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory, isDir {
                if excludedDirectories.contains(fileURL.lastPathComponent) {
                    enumerator.skipDescendants()
                }
                continue
            }
            if extensions.contains(fileURL.pathExtension.lowercased()) {
                result.append(fileURL)
            }
        }
        return result
    }
}
