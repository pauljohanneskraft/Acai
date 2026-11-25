import Foundation

/// A decoded JSON tree the equivalence suite can rewrite and compare.
///
/// The suite compares whole `CodeArtifact`s rather than `ContractShape`s, so a field the projection
/// has never heard of — a modifier, a call site, an end line — still has to survive a variation. A
/// tree walk is exhaustive by construction, which a hand-written traversal of the model would stop
/// being the next time a field is added.
indirect enum ContractJSON: Equatable, Decodable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([ContractJSON])
    case object([String: ContractJSON])

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let bool = try? container.decode(Bool.self) {
            self = .bool(bool)
        } else if let number = try? container.decode(Double.self) {
            self = .number(number)
        } else if let string = try? container.decode(String.self) {
            self = .string(string)
        } else if let array = try? container.decode([ContractJSON].self) {
            self = .array(array)
        } else {
            self = .object(try container.decode([String: ContractJSON].self))
        }
    }

    /// Key order fixed and indentation dropped, so two trees sort and print the same way.
    var canonicalText: String {
        switch self {
        case .null:
            return "null"
        case .bool(let value):
            return value ? "true" : "false"
        case .number(let value):
            return value == value.rounded() && abs(value) < 1e15 ? String(Int64(value)) : String(value)
        case .string(let value):
            let escaped = value
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
            return "\"\(escaped)\""
        case .array(let elements):
            return "[\(elements.map(\.canonicalText).joined(separator: ","))]"
        case .object(let fields):
            let pairs = fields.keys.sorted().map { "\"\($0)\":\(fields[$0]!.canonicalText)" }
            return "{\(pairs.joined(separator: ","))}"
        }
    }
}
