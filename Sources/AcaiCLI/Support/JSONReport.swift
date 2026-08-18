import ArgumentParser
import Foundation

struct JSONReport {
    let text: String

    init(_ value: some Encodable) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let text = String(data: try encoder.encode(value), encoding: .utf8) else {
            throw ValidationError("Failed to encode \(type(of: value)) as JSON.")
        }
        self.text = text
    }
}
