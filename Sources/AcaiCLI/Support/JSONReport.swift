import ArgumentParser
import Foundation

/// A pretty-printed, key-sorted JSON rendering of a value — the single output shape shared by every
/// JSON-producing command (`analyze`, `metrics`, `cycles`, `check`, `diff`, and the analysis
/// commands). A value you construct from what you want to emit (`JSONReport(payload).text`), so the
/// encoder configuration lives in exactly one place instead of being copy-pasted into each command.
struct JSONReport {
    /// The rendered JSON document.
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
