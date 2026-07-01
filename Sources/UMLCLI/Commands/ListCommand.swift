import ArgumentParser
import Foundation
import UMLLibrary

extension UMLCommand {
    struct List: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "List all stored analyses"
        )

        mutating func run() throws {
            let storageDir = UMLConstants.standard.analysisDirectory
            let fileManager = FileManager.default

            guard fileManager.fileExists(atPath: storageDir.path) else {
                print("No stored analyses found.")
                return
            }

            let contents = try fileManager.contentsOfDirectory(
                at: storageDir,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )

            let jsonFiles = contents.filter { $0.pathExtension == "json" }

            if jsonFiles.isEmpty {
                print("No stored analyses found.")
                return
            }

            print(Row(name: "NAME", language: "LANGUAGE", types: "TYPES", files: "FILES").formatted)
            print(String(repeating: "-", count: 50))

            for file in jsonFiles.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                let name = file.deletingPathExtension().lastPathComponent
                do {
                    let data = try Data(contentsOf: file)
                    let artifact = try JSONDecoder().decode(CodeArtifact.self, from: data)
                    let row = Row(
                        name: name,
                        language: artifact.metadata.sourceLanguage.rawValue,
                        types: String(artifact.types.count),
                        files: String(artifact.metadata.filePaths.count)
                    )
                    print(row.formatted)
                } catch {
                    print(Row(name: name, language: "(error reading)", types: "", files: "").formatted)
                }
            }
        }

        /// One line of the `uml list` table. Columns are space-padded to fixed widths;
        /// Swift `String`s can't go through C `%s`, so the table is assembled manually.
        private struct Row {
            var name: String
            var language: String
            var types: String
            var files: String

            var formatted: String {
                name.paddedTrailing(to: 20) + "  "
                    + language.paddedTrailing(to: 12) + "  "
                    + types.paddedLeading(to: 6) + "  "
                    + files.paddedLeading(to: 5)
            }
        }
    }
}
