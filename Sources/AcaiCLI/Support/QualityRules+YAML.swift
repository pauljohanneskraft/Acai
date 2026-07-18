import ArgumentParser
import Foundation
import AcaiQuality
import Yams

extension QualityRules {
    /// Decodes a rules file. The model is `Codable`, so the YAML keys map directly onto the rule
    /// types (`forbidden`, `cycles`, `budgets`, `from`/`to`, `target`, `metric`, …). Decoding errors
    /// are wrapped in a `ValidationError` so the CLI surfaces a clean message, not a raw dump.
    static func load(yaml: String) throws -> QualityRules {
        do {
            return try YAMLDecoder().decode(QualityRules.self, from: yaml)
        } catch let error as DecodingError {
            // A schema mismatch (wrong type, missing key, …). Surface where and why, not the
            // multi-line `Context(...)` reflection dump that interpolating the error would emit.
            throw ValidationError("Invalid rules file: \(error.readableDescription)")
        } catch {
            // A YAML syntax error (Yams describes these with a line/column mark already).
            throw ValidationError("Invalid rules file: \(error)")
        }
    }

    static func load(contentsOf path: String) throws -> QualityRules {
        let yaml = try String(contentsOf: URL(fileURLWithPath: path), encoding: .utf8)
        return try load(yaml: yaml)
    }
}

extension DecodingError {
    /// A concise, cause-preserving one-line description: the decoder's own explanation plus the
    /// coding path that locates the offending key in the source — without the multi-line
    /// `Context(...)` reflection that string-interpolating a `DecodingError` produces.
    var readableDescription: String {
        switch self {
        case let .typeMismatch(_, context),
             let .valueNotFound(_, context),
             let .keyNotFound(_, context),
             let .dataCorrupted(context):
            let path = context.codingPath.map(\.stringValue).joined(separator: ".")
            return path.isEmpty ? context.debugDescription : "\(context.debugDescription) (at '\(path)')"
        @unknown default:
            return localizedDescription
        }
    }
}
