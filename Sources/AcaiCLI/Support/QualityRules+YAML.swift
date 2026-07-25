import ArgumentParser
import Foundation
import AcaiQuality
import Yams

extension QualityRules {
    /// Decodes a rules file, wrapping decode errors in a `ValidationError` so the CLI surfaces a
    /// clean message rather than a raw dump.
    static func load(yaml: String) throws -> QualityRules {
        do {
            return try YAMLDecoder().decode(QualityRules.self, from: yaml)
        } catch let error as DecodingError {
            throw ValidationError("Invalid rules file: \(error.readableDescription)")
        } catch {
            throw ValidationError("Invalid rules file: \(error)")
        }
    }

    static func load(contentsOf path: String) throws -> QualityRules {
        let yaml = try String(contentsOf: URL(fileURLWithPath: path), encoding: .utf8)
        return try load(yaml: yaml)
    }
}

extension DecodingError {
    /// A concise one-line description: the decoder's explanation plus the coding path to the
    /// offending key, instead of the multi-line `Context(...)` dump of interpolating the error directly.
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
