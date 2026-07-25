import ArgumentParser
import Foundation

/// A pretty-printed, key-sorted JSON rendering of a value — the shared output shape for every
/// JSON-producing command.
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
