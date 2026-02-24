import ArgumentParser
import Foundation
import UMLLibrary

extension CodeArtifact {
    func encodedJSON() throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(self)
        guard let json = String(data: data, encoding: .utf8) else {
            throw ValidationError("Failed to encode artifact as JSON.")
        }
        return json
    }
}
