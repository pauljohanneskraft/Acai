import ArgumentParser
import Foundation
import UMLLibrary

extension UMLCommand {
    struct List: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "List all stored analyses"
        )

        mutating func run() throws {
            let storageDir = UMLConstants.analysisDirectory
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

            print(String(format: "%-20s  %-12s  %6s  %5s", "NAME", "LANGUAGE", "TYPES", "FILES"))
            print(String(repeating: "-", count: 50))

            for file in jsonFiles.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                let name = file.deletingPathExtension().lastPathComponent
                do {
                    let data = try Data(contentsOf: file)
                    let artifact = try JSONDecoder().decode(CodeArtifact.self, from: data)
                    let lang = artifact.metadata.sourceLanguage.rawValue
                    let typeCount = artifact.types.count
                    let fileCount = artifact.metadata.filePaths.count
                    print(String(format: "%-20s  %-12s  %6d  %5d", name, lang, typeCount, fileCount))
                } catch {
                    print(String(format: "%-20s  %-12s", name, "(error reading)"))
                }
            }
        }
    }
}
